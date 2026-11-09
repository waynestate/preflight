---
title: "The phpstan component | Preflight docs"
description: "Runs the app's own PHPStan and fails the pipeline on static analysis errors, writing a GitLab Code Quality report."
url: https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The phpstan component[#](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html#the-phpstan-component)

This page shows how to add the `phpstan` component to an app's `.gitlab-ci.yml`: it runs the app's own [PHPStan](https://phpstan.org/) and fails the pipeline on static analysis errors, writing a GitLab Code Quality report. It finds the loose bolts before the flight does; check the requirements first, then add the include.

Version 1, category Testing/Validation, tags `php`, `static-analysis`, `phpstan`.

## Before you start[#](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html#before-you-start)

The component does not install PHPStan itself. The app must:

- Require `phpstan/phpstan` as a dev dependency.
- Ship a `phpstan.neon`, or point the `config` input at its own file.

## Include the component[#](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html#include-the-component)

Add the include to the app's `.gitlab-ci.yml`, pinned to a commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
    inputs:
      config: phpstan.neon
      memory_limit: 1G
```

A tag or branch can move; a SHA cannot.

## What the job does[#](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html#what-the-job-does)

The job lands in the `test` stage by default, is `interruptible: true`, and has a `timeout: 10m`. It runs three steps:

1. Move to the directory given by `working_dir` (default `.`).
2. Install the app's dependencies:
   ```sh
   composer install --no-interaction --no-progress --prefer-dist
   ```
3. Run PHPStan against the app's own config:
   ```sh
   vendor/bin/phpstan analyse --no-progress --error-format=gitlab --memory-limit=1G -c phpstan.neon > "$CI_PROJECT_DIR/phpstan-report.json"
   ```
   - `--memory-limit` takes the `memory_limit` input (default `1G`).
   - `-c` takes the `config` input (default `phpstan.neon`).
   - `--error-format=gitlab` writes the findings as a GitLab Code Quality report to `$CI_PROJECT_DIR/phpstan-report.json`.

## Report[#](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html#report)

The job publishes the report as a Code Quality report:

```yaml
artifacts:
  when: always
  reports:
    codequality: phpstan-report.json
```

## Inputs[#](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `phpstan` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0` | Docker image for the job. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `config` | string | `phpstan.neon` | Path to the app's PHPStan config file. It must be a relative path; GitLab refuses the pipeline at creation if it is not. |
| `memory_limit` | string | `1G` | Memory limit passed to PHPStan. A PHP size such as `1G`, `512M` or `-1`; GitLab refuses the pipeline at creation if it is not. |
| `working_dir` | string | `.` | Directory to run PHPStan in, relative to the project root. |

`job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, and `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$`.

Note

`config` must be a relative path, and `memory_limit` takes a PHP size such as `1G`, `512M` or `-1`. Each carries an input `regex`, so GitLab refuses the pipeline at creation when a value does not match.

## Verify[#](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html#verify)

Push the change. The components are ordinary jobs, so the `phpstan` job runs whenever the app's pipeline runs, in the `test` stage by default. A green job means no static analysis errors, and the Code Quality report carries the findings.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/component-phpstan.html#related)

- [The pint component](https://preflight.apps.wayne.edu/docs/guides/component-pint.html): the style check that pairs with it.
- [The proctor component](https://preflight.apps.wayne.edu/docs/guides/component-proctor.html): another check that publishes a Code Quality report.
- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html): the `job_name` input when one project includes the same component more than once.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
