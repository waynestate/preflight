---
title: The squire-kit component
description: Fails the pipeline when a Squire deploy kit drifts from the Squire release recorded in its .squire.json.
---

# The squire-kit component

This page covers the `squire-kit` component: what the job checks, how to include it, every input it takes, and what to
do when it goes red. Goal: a deploy kit that [Squire](https://github.com/waynestate/squire) wrote stays exactly what
Squire wrote, so a fix to the kit reaches every app the day Squire ships it. A squire keeps the armor polished; this job
is the inspection before the joust.

Version 1 · Category: Testing/Validation · Tags: squire,deploy,drift

## What the job checks

Squire writes the deploy kit (`build.sh`, the release script, the health check, the local parity files) and records
the Squire version it used and a SHA-256 of every file in `.squire.json`. The job:

1. Moves to the kit folder given by `working_dir` (the stack's own repos keep the kit in `deploy`).
2. Reads the version recorded in `.squire.json`, unless `squire_version` names one.
3. Installs that exact Squire release from Packagist into a temporary folder outside the project, with `--no-dev` and
   `--no-scripts`, so nothing from the project and none of Squire's dev tools run.
4. Runs `squire init --check` on the kit folder.

It passes only when every kit file is that release's template, untouched. The exit codes are Squire's:

| Exit | Meaning |
|------|---------|
| 0 | The kit matches the recorded release. |
| 1 | The kit drifted: a file was edited (`modified`), is missing, is not the template of the recorded release (`outdated`), or is new in the kit's groups (`untracked`). |
| 2 | The check could not run: no `.squire.json` in `working_dir`, no released `x.y.z` version recorded, or no such release on Packagist. |

The job checks the version the kit records, not the newest Squire, so a new Squire release never turns a green main red
by itself. Renovate moves the version: the [Renovate](renovate.md) preset opens a merge request for each new Squire, and
on a runner that allows it, that merge request already carries the refreshed kit.

## Include the component

Add the include to the app's `.gitlab-ci.yml`, pinned to a full commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/squire-kit@<full commit SHA> # 0.2.0
    inputs:
      working_dir: deploy
```

> [!NOTE]
> The squire-kit component ships in Preflight 0.2.0; 0.1.4 does not include it. Pin that tag's full commit SHA, or the
> full commit SHA of a commit at or after it.

Run `vendor/bin/squire init --check --path=deploy` on your desk first. Include the component once it passes, or turn on
`allow_failure` while you clean up (below).

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `squire-kit` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. It needs PHP 8.3 or later and Composer. |
| `working_dir` | string | `.` | The kit folder: the one holding `.squire.json`, relative to the project root. |
| `squire_version` | string | `""` | Squire release to check against. Empty reads the version recorded in `.squire.json`. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline, for a repository cleaning up its first findings. |

`job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$`,
and `squire_version` must be empty or match `^[0-9]+\.[0-9]+\.[0-9]+$`. GitLab refuses the pipeline at creation when a
value does not match.

## When the job is red

The log lists every kit file with its state; the last lines name what to do.

- **`outdated` or `missing`.** The kit records a version whose templates it does not carry. Run
  `vendor/bin/squire update --path=deploy`, then `vendor/bin/squire init --path=deploy` (a release that adds a kit file
  needs `init` to write it), review the diff and commit it.
- **`modified`.** Someone, or a bot, edited a file Squire owns. Put Squire's file back with
  `vendor/bin/squire init --force --path=deploy` and send the change to Squire instead, so every app gets it.
- **`untracked`.** A file sits in one of the kit's groups but not in `.squire.json`. Remove it, or run `squire init` so
  Squire records it.

> [!CAUTION]
> Renovate's digest and tag bumps were what made the stack's kits drift: a bump to a base image inside `.squire/` or to
> `docker-compose.squire.yml` is an edit to a file Squire owns. Preflight's preset now leaves those files alone; update
> the image in Squire's templates and let the next Squire release carry it.

## Adopt it with findings

To include the component before the kit is clean, let the job fail without failing the pipeline:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/squire-kit@<full commit SHA> # 0.2.0
    inputs:
      working_dir: deploy
      allow_failure: true # until 2026-12-01: kit cleanup
```

While `allow_failure` is `true`, a red job shows as a warning. Remove the input once the job is green, and leave a date
in a comment so the warning does not become the new normal.

## Verify

Push the change. The `squire-kit` job lands in the `test` stage by default and its last line reads
`RESULT: pass (0 of N files need attention)` when the kit matches. Preflight's own pipeline runs it on
`tests/squire-kit-fixture`, a kit written by `squire init --target=raw`.

> [!NOTE]
> The job needs Packagist (to install the recorded Squire release). It needs no token and no Docker socket.

## Related

- [Renovate](renovate.md): the preset's Squire rule, which opens the merge request that moves the kit to a new release.
- [The renovate component](component-renovate.md): the `squire_kit_tasks` input, which lets that merge request carry
  the refreshed kit.
- [Include a component twice](include-twice.md): check two kits in one project with `job_name`.
- [Troubleshooting](../troubleshooting.md): the squire-kit job's error messages.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
