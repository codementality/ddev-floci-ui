# ddev-floci-ui <!-- omit in toc -->

[![tests](https://github.com/codementality/ddev-floci-ui/actions/workflows/tests.yml/badge.svg)](https://github.com/codementality/ddev-floci-ui/actions/workflows/tests.yml)
[![last commit](https://img.shields.io/github/last-commit/codementality/ddev-floci-ui)](https://github.com/codementality/ddev-floci-ui/commits)
[![release](https://img.shields.io/github/v/release/codementality/ddev-floci-ui)](https://github.com/codementality/ddev-floci-ui/releases/latest)

A [DDEV](https://ddev.com) add-on that runs [Floci UI](https://github.com/floci-io/floci-ui)
— the local cloud console — against whichever Floci emulators your project has
installed.

One console per project, showing AWS, Azure and GCP side by side.

- [Installation](#installation)
- [Why it is a separate add-on](#why-it-is-a-separate-add-on)
- [How it finds your emulators](#how-it-finds-your-emulators)
- [Versus the "Open Floci UI" button](#versus-the-open-floci-ui-button)
- [The `ddev floci-ui` command](#the-ddev-floci-ui-command)
- [Configuration](#configuration)
- [Removing the add-on](#removing-the-add-on)
- [Credits](#credits)

## Installation

You usually do not install this directly. Each emulator add-on declares it as a
dependency, so DDEV pulls it in:

```bash
ddev add-on get codementality/ddev-floci-aws   # or -gcp, or -az
ddev restart
ddev floci-ui
```

Installing it on its own works too, and is worth doing if you want the console
before you have picked a cloud:

```bash
ddev add-on get codementality/ddev-floci-ui
```

## Why it is a separate add-on

The console is multi-cloud: it takes one endpoint per cloud and shows whichever
are reachable. So there should be exactly one per project, no matter how many
emulators you install.

Shipping it inside each emulator add-on would break that. Install two of them
and you would have two compose files both defining a service named `floci-ui` —
Compose merges them into one incoherent service, and removing either add-on
takes the shared console with it. A separate add-on has one definition and one
owner.

DDEV handles the bookkeeping. Because each emulator declares
`dependencies: [codementality/ddev-floci-ui]`, DDEV installs it automatically,
and refuses to remove it while any emulator still needs it:

```
$ ddev add-on remove floci-ui
Unable to remove add-on: cannot remove add-on 'floci-ui' because the
following add-ons depend on it: floci-gcp
```

Remove the last emulator and DDEV tells you the console is now orphaned rather
than deleting it out from under you.

## How it finds your emulators

By container name — `ddev-<project>-floci-aws`, `-floci-az`, `-floci-gcp` — not
by the service hostnames `floci-aws`, `floci-az`, `floci-gcp`.

That distinction is load-bearing, and it is worth understanding if you run
several projects. This service has to sit on DDEV's shared `ddev_default`
network so ddev-router can reach it. Every project's emulator is also aliased by
its bare service hostname on that same shared network. So a project with **no**
AWS emulator, asking for `floci-aws`, resolves to some *other* project's AWS
emulator — and the console would happily display another project's buckets and
queues. Container names are unique per project, so they cannot collide that way.

The upshot: a cloud you have not installed shows as unavailable, which is the
truth.

```bash
ddev floci-ui clouds
# aws    unavailable   http://ddev-myproject-floci-aws:4566
# azure  reachable     http://ddev-myproject-floci-az:4577
# gcp    reachable     http://ddev-myproject-floci-gcp:4588
```

All three endpoints are set whether or not the emulators exist, so installing
another one later needs no change here — just `ddev restart`.

## Versus the "Open Floci UI" button

The AWS emulator serves a landing page with an **Open Floci UI** button, which
starts a console of its own. That one is *not* this one, and it is worth knowing
the difference:

| | The button's console | This add-on |
|---|---|---|
| Container name | `floci-ui` — global | `ddev-<project>-floci-ui` |
| Host port | `0.0.0.0:4500`, all interfaces | none; ddev-router by hostname |
| Scope | whichever project launched it first | the project it belongs to |
| Several projects at once | second project sees the first one's data | each sees its own |

So prefer `ddev floci-ui`. The button still works, and this add-on deliberately
stays off port 4500 so the two do not fight — but the button's console is shared
across every project on your machine.

The GCP and Azure emulators have no such landing page or button at all: upstream
`floci-gcp` and `floci-az` ship no UI controller, so `/` on those returns
`Resource not found`. This add-on is how those two get a console.

> *Measured against `floci/floci-ui:0.3.0`, `floci/floci:1.7.0`, `floci/floci-gcp:0.7.0` and `floci/floci-az:0.11.0` on 2026-08-26. Floci is under active development, so this may already be out of date — in particular, a landing page may appear in floci-gcp or floci-az.*


## The `ddev floci-ui` command

| Command | Does |
|---|---|
| `ddev floci-ui` | Opens the console in your browser |
| `ddev floci-ui url` | Prints the console URL |
| `ddev floci-ui clouds` | Which emulators the console can actually reach |
| `ddev floci-ui status` | Container state |
| `ddev floci-ui logs [-f]` | Container logs |

## Configuration

```bash
ddev dotenv set .ddev/.env.floci-ui --floci-ui-https-port=4611
ddev restart
```

| Variable | Default | Purpose |
|---|---|---|
| `FLOCI_UI_IMAGE` | `floci/floci-ui:latest` | Image tag |
| `FLOCI_UI_HTTP_PORT` | `4510` | ddev-router port (http), shared between projects |
| `FLOCI_UI_HTTPS_PORT` | `4511` | ddev-router port (https), shared between projects |
| `FLOCI_UI_AWS_ENDPOINT` | `http://ddev-<project>-floci-aws:4566` | Override the AWS runtime |
| `FLOCI_UI_AZURE_ENDPOINT` | `http://ddev-<project>-floci-az:4577` | Override the Azure runtime |
| `FLOCI_UI_GCP_ENDPOINT` | `http://ddev-<project>-floci-gcp:4588` | Override the GCP runtime |

Ports 4510/4511 rather than the console's native 4500, because the button's
global container publishes `0.0.0.0:4500` and a router entrypoint there would
lose the race to it.

The router routes by hostname, so these ports are shared cleanly between every
project running this add-on — any number can be up at once.

## Removing the add-on

```bash
ddev add-on remove floci-ui
```

DDEV refuses while any emulator add-on still declares it as a dependency; remove
those first, or keep the console. `.ddev/.env.floci-ui` is left in place so your
settings survive a reinstall.

## Credits

Floci UI is by the [floci-io](https://github.com/floci-io/floci-ui) project, MIT
licensed. This add-on only packages it; no Floci source is vendored here.

Behavioural notes in this README were verified against `floci/floci-ui:0.3.0` on 2026-08-26.
Upstream ships frequently; the nightly workflow in `.github/workflows/tests.yml`
re-runs the suite against `latest` every day, which is what catches drift.

**Contributed and maintained by [@codementality](https://github.com/codementality)**
