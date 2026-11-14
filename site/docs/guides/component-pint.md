---
title: "The pint component | Preflight docs"
description: "Runs the app's own Laravel Pint in test mode and fails the pipeline on style errors."
url: https://preflight.apps.wayne.edu/docs/guides/component-pint.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The pint component [#](https://preflight.apps.wayne.edu/docs/guides/component-pint.html#the-pint-component)

This page shows how to add the `pint` component to an app's `.gitlab-ci.yml`: it runs the app's own [Laravel Pint](https://laravel.com/docs/12.x/pint) in test mode and fails the pipeline on style errors. It is the cockpit polish (every line tidied before takeoff); check the requirements first, then add the include.

Version 1, category Testing/Validation, tags `php`, `style`, `pint`.

## Before you start [#](https://preflight.apps.wayne.edu/docs/guides/component-pint.html#before-you-start)

The component does not install Pint itself. The app must:

- Require `laravel/pint` as a dev dependency.
- Ship a `pint.json`, or point the `config` input at its own file.

## Include the component [#](https://preflight.apps.wayne.edu/docs/guides/component-pint.html#include-the-component)

Add the include to the app's `.gitlab-ci.yml`, pinned to a commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@fb73b538f3980292119b5b306ff64383d760a214 # 0.9.0
    inputs:
      config: pint.json
```

A tag or branch can move; a SHA cannot.

## What the job does [#](https://preflight.apps.wayne.edu/docs/guides/component-pint.html#what-the-job-does)

The job lands in the `test` stage by default, is `interruptible: true`, and has a `timeout: 10m`. It runs three steps:

1. Move to the directory given by `working_dir` (default `.`).
2. Install the app's dependencies:
   ```sh
   composer install --no-interaction --no-progress --prefer-dist
   ```
3. Run Pint in test mode against the app's own config:
   ```sh
   vendor/bin/pint --test --config=pint.json
   ```
   `--config` takes the `config` input (default `pint.json`). A style error fails the job, and with it the pipeline.

## Inputs [#](https://preflight.apps.wayne.edu/docs/guides/component-pint.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `pint` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0` | Docker image for the job. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `config` | string | `pint.json` | Path to the app's Pint config file. It must be a relative path; GitLab refuses the pipeline at creation if it is not. |
| `working_dir` | string | `.` | Directory to run Pint in, relative to the project root. |

`job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, and `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$`.

Note

`config` must be a relative path. The input carries a `regex`, so GitLab refuses the pipeline at creation when a value does not match.

## Verify [#](https://preflight.apps.wayne.edu/docs/guides/component-pint.html#verify)

Push the change. The components are ordinary jobs, so the `pint` job runs whenever the app's pipeline runs, in the `test` stage by default. A green job means the app's code is clean under its own Pint config.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/component-pint.html#related)

- [The phpstan component](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html): the static analysis check that pairs with it.
- [The eslint component](https://preflight.apps.wayne.edu/docs/guides/component-eslint.html): the JavaScript style check.
- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html): the `job_name` input when one project includes the same component more than once.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
