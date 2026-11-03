---
title: The composer-audit component
description: Runs `composer audit --locked` and fails on advisories.
---

# The composer-audit component

Fresh eyes on the manifest: this component runs `composer audit --locked` and fails the pipeline on advisories. This page shows how to add the `composer-audit` component to your app's `.gitlab-ci.yml`, then how to run it on a weekly schedule so the check keeps running after code is merged.

## Include the component

Goal: your app's pipeline fails whenever a locked dependency has a known advisory. Add the include to your app's `.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      working_dir: .
```

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `composer-audit` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. |
| `working_dir` | string | `.` | Directory to run composer audit in, relative to the project root. |

> [!NOTE]
> The template adds regexes to two inputs: `job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$` and `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$`.

## What the job does

The `composer:2` image already ships Composer, so no install step is needed. The job is `interruptible: true` with a `timeout: 30 minutes`. Its script changes into `working_dir` and runs `composer audit --locked`. The command exits non-zero when it finds advisories, which fails the job.

> [!WARNING]
> The component carries no `allow_failure` input on purpose: a known advisory must fail the pipeline.

## Run it on a schedule

New advisories are published after code is merged, so a green pipeline today can be stale tomorrow. Create a weekly pipeline schedule on the default branch: project settings, Build, Pipeline schedules. The component needs nothing extra; it carries no `rules:` block, so it runs in scheduled pipelines like any other. Creating the schedule is a project setting, not a file in the app's repo, and someone with Maintainer rights on the app must do it. It is the one Preflight check that books its own flight time.

## Related

- [The proctor component](component-proctor.md)
- [The php-test component](component-php-test.md)
