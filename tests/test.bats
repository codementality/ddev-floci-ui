#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
#
# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'

setup() {
  set -eu -o pipefail

  # Override this variable for your add-on:
  export GITHUB_REPO=codementality/ddev-floci-ui

  # An emulator add-on to test the dependency relationship against.
  #
  # This add-on has to be RELEASED BEFORE the emulator ones, because each of
  # them declares it as a dependency. So on a first release the sibling does not
  # exist yet, and the tests that need it skip rather than fail. Override to
  # test against a branch or a fork once both are published:
  #   FLOCI_EMULATOR_ADDON=codementality/ddev-floci-az bats ./tests/test.bats
  #
  # A local path works only if that checkout's own floci-ui dependency also
  # resolves; otherwise its install fails and those tests simply skip.
  export FLOCI_EMULATOR_ADDON="${FLOCI_EMULATOR_ADDON:-codementality/ddev-floci-gcp}"

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"

  mkdir -p "${TESTDIR}/web"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site \
    --project-type=php --docroot=web
  assert_success
  run ddev start -y
  assert_success
}

# Installs the emulator add-on, or skips the calling test if it is not
# published yet. `ddev add-on get` on a missing repo fails with "not found in
# cached add-on registry" — a red CI run on a brand-new repo, for a reason that
# has nothing to do with this add-on being broken.
require_emulator_addon() {
  if ! ddev add-on get "${FLOCI_EMULATOR_ADDON}" >/dev/null 2>&1; then
    skip "${FLOCI_EMULATOR_ADDON} is not published yet"
  fi
}

health_checks() {
  # The console answers through ddev-router.
  run ddev floci-ui url
  assert_success
  assert_output "https://${PROJNAME}.ddev.site:4511"

  run curl -sfk "$(ddev floci-ui url)"
  assert_success
  assert_output --partial "Floci UI"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

@test "with no emulator installed, every cloud reports unavailable" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  # This is the cross-project test in disguise. The console sits on DDEV's
  # shared ddev_default network, where every OTHER project's emulator is aliased
  # by its bare service hostname — so if the endpoints named `floci-aws` rather
  # than `ddev-<project>-floci-aws`, a project with no AWS emulator would report
  # "reachable" and show another project's data. Unavailable is the truth here.
  run ddev floci-ui clouds
  assert_success
  assert_output --partial "aws    unavailable"
  assert_output --partial "azure  unavailable"
  assert_output --partial "gcp    unavailable"

  # And the endpoints must be container-scoped, not bare hostnames.
  run docker exec "ddev-${PROJNAME}-floci-ui" printenv FLOCI_GCP_ENDPOINT
  assert_success
  assert_output "http://ddev-${PROJNAME}-floci-gcp:4588"
}

@test "an installed emulator shows as reachable" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  require_emulator_addon

  # Reinstall from the working tree, because the line above just replaced it.
  #
  # The emulator add-on declares `dependencies: [codementality/ddev-floci-ui]`.
  # DDEV matches that string against installed manifest NAMES, and an add-on
  # installed from a local directory registers as plain `floci-ui` — so the
  # dependency looks unsatisfied and DDEV installs floci-ui from its published
  # release, silently overwriting the code under test with the last tagged
  # version. Without this, the test measures the previous release rather than
  # this branch, and passes or fails for reasons that have nothing to do with
  # the change being tested.
  run ddev add-on get "${DIR}"
  assert_success

  run ddev restart -y
  assert_success

  run ddev floci-ui clouds
  assert_success
  assert_output --partial "gcp    reachable"
  assert_output --partial "aws    unavailable"

  # The console reads that emulator, not some other project's.
  run docker exec "ddev-${PROJNAME}-floci-ui" sh -c \
    'wget -qO- --timeout=5 "$FLOCI_GCP_ENDPOINT/_floci-gcp/health"'
  assert_success
}

@test "emulator add-ons pull this one in, and it cannot be removed while needed" {
  set -eu -o pipefail
  # No explicit install of floci-ui — the dependency does it.
  require_emulator_addon
  assert_file_exist "${TESTDIR}/.ddev/docker-compose.floci-ui.yaml"

  # DDEV refuses to orphan a console another add-on still declares.
  run ddev add-on remove floci-ui
  assert_failure
  assert_output --partial "depend on it"

  # Removing the last emulator warns rather than silently deleting the console.
  run ddev add-on remove floci-gcp
  assert_success
  assert_file_exist "${TESTDIR}/.ddev/docker-compose.floci-ui.yaml"

  # Now it can go.
  run ddev add-on remove floci-ui
  assert_success
  assert_file_not_exist "${TESTDIR}/.ddev/docker-compose.floci-ui.yaml"
}

@test "nothing claims a fixed host port" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  # The console is reached through ddev-router by hostname, so any number of
  # projects can run one. A published port here would break that — and would
  # also collide with the global container the AWS landing page's button starts
  # on 0.0.0.0:4500.
  run docker port "ddev-${PROJNAME}-floci-ui"
  assert_output ""
}

@test "add-on removes cleanly" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  run ddev add-on remove floci-ui
  assert_success
  assert_file_not_exist "${TESTDIR}/.ddev/docker-compose.floci-ui.yaml"
  assert_file_not_exist "${TESTDIR}/.ddev/commands/host/floci-ui"
  run ddev restart -y
  assert_success
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
