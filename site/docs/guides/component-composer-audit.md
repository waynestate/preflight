---
title: "The composer-audit component | Preflight docs"
description: "Runs `composer audit --locked` and fails on advisories."
url: https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The composer-audit component [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#the-composer-audit-component)

Fresh eyes on the manifest: this component runs `composer audit --locked` and fails the pipeline on advisories. This page shows how to add the `composer-audit` component to your app's `.gitlab-ci.yml`, then how to run it on a weekly schedule so the check keeps running after code is merged.

## Include the component [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#include-the-component)

Goal: your app's pipeline fails whenever a locked dependency has a known advisory. Add the include to your app's `.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@60314791565a264e97cb210813ef4f3e76512402 # 0.5.0
    inputs:
      working_dir: .
```

## Inputs [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `composer-audit` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0` | Docker image for the job. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `working_dir` | string | `.` | Directory to run composer audit in, relative to the project root. |
| `abandoned` | string | `fail` | How composer audit treats abandoned packages: fail (default), report (list them, do not fail) or ignore. |

Note

The template adds regexes to three inputs: `job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$` and `abandoned` must match `^(fail|report|ignore)$`.

## What the job does [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#what-the-job-does)

The Composer image (`composer:2.11.1`, pinned by digest) already ships Composer, so no install step is needed. The job is `interruptible: true` with a `timeout: 30 minutes`. Its script changes into `working_dir` and runs `composer audit --locked` with `--abandoned` set to the `abandoned` input (see Abandoned packages below). The command exits non-zero when it finds advisories, which fails the job.

Warning

The component carries no `allow_failure` input on purpose: a known advisory must fail the pipeline.

## What fails the job [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#what-fails-the-job)

`composer audit --locked` reads only the lock file (it installs nothing) and fails the job on any of three findings:

- **A security advisory** on a locked version. This fails in every mode.
- **A malware-flagged version.** Composer 2.10 also reads the filter lists a repository publishes; Packagist publishes one, `malware`, fed by Aikido. The job log names the package, the list, the source and a `PKFE-` ID. This fails in every mode too: the `abandoned` input does not touch it.
- **An abandoned package**, while `abandoned` is `fail` (see below).

Composer asks Packagist for advisories and filter lists on every run, so the job needs outbound HTTPS to packagist.org. When Packagist cannot be reached the job fails rather than passes: the component never adds `--ignore-unreachable`.

Preflight's own pipeline keeps these promises with the `must-fail-composer-audit` job: it runs this template's own lines on a clean app (must pass) and on three fixed locks, laravel/framework v9.0.0 (CVE-2024-52301), aikido/endpoint-test 0.0.1 (Aikido's harmless package, flagged on purpose so scanners can be tested) and an abandoned package, which must fail (the abandoned one only in `fail` mode). A flight check that has never seen a red light is just a light.

## Abandoned packages [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#abandoned-packages)

An abandoned package is one its author no longer maintains; Composer marks it in the lock file. By default an abandoned package in the lock fails the job, and the component keeps that default: `fail` is what the `abandoned` input holds when you set nothing.

The three modes:

- `fail` (default): the job fails when the lock holds an abandoned package.
- `report`: the job lists the abandoned packages but does not fail on them.
- `ignore`: the job does not look at abandoned packages at all.

`report` is the right choice for an old app that carries abandoned transitive packages it cannot upgrade yet: the pipeline stays green while the job log names every abandoned package, so the debt is visible instead of hidden. Advisories still fail the job in every mode: `abandoned` relaxes only the abandoned check, never the advisory check.

## Run it on a schedule [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#run-it-on-a-schedule)

New advisories are published after code is merged, so a green pipeline today can be stale tomorrow. Create a weekly pipeline schedule on the default branch: project settings, Build, Pipeline schedules. The component needs nothing extra; it carries no `rules:` block, so it runs in scheduled pipelines like any other. Creating the schedule is a project setting, not a file in the app's repo, and someone with Maintainer rights on the app must do it. It is the one Preflight check that books its own flight time.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#related)

- [The proctor component](https://preflight.apps.wayne.edu/docs/guides/component-proctor.html)
- [The php-test component](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html)
