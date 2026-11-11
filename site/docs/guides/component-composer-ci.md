---
title: "The composer-ci component | Preflight docs"
description: "Runs `composer install` and then `composer ci`, and fails the job when either fails."
url: https://preflight.apps.wayne.edu/docs/guides/component-composer-ci.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The composer-ci component [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-ci.html#the-composer-ci-component)

The lock file is the contract: this component runs `composer install` and then `composer ci`, and fails the pipeline when either fails, for example on a lock file that is missing a package `composer.json` requires. Nine stack repos hand-write this same job today; this page shows how to replace that copy with one include.

## Include the component [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-ci.html#include-the-component)

Goal: your app's pipeline fails whenever `composer ci` fails, from one include instead of a hand-written job. Add the include to your app's `.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-ci@<full commit SHA> # <tag>
    inputs:
      working_dir: .
```

## Inputs [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-ci.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `composer-ci` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0` | Docker image for the job. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `working_dir` | string | `.` | Directory to run Composer in, relative to the project root. |

Note

The template adds regexes to two inputs: `job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$` and `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$`.

## What the job does [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-ci.html#what-the-job-does)

The Composer image (`composer:2.11.1`, pinned by digest) already ships Composer, so no install step for the tool is needed. The job is `interruptible: true` with a `timeout: 30 minutes`. Its script changes into `working_dir`, runs `composer install --no-interaction --no-progress --prefer-dist`, and then `composer ci`, the project's own ci script. That command's exit code decides the job: a lock that is missing a required package fails the pipeline (a lock whose hash is merely stale only warns, unless the project's `composer ci` runs `composer validate`).

The job caches Composer downloads in `.composer-cache/` under the fixed key `preflight-composer-ci` (policy `pull-push`, saved with `when: always`), and sets `COMPOSER_CACHE_DIR` to `$CI_PROJECT_DIR/.composer-cache`, so repeat runs do not re-download every package and a retry after a dropped download fetches only what is missing.

Warning

The component carries no `allow_failure` input on purpose: a failing `composer ci` must fail the pipeline.

## What it replaces [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-ci.html#what-it-replaces)

The hand-written install-and-ci job that nine stack repos carry, line for line: the Composer image by digest, the shared Composer cache, `composer install`, then `composer ci`. Drop the copy and keep the include; the job name, the cache and the failure behaviour stay the same.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/component-composer-ci.html#related)

- [The composer-audit component](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html)
- [The proctor component](https://preflight.apps.wayne.edu/docs/guides/component-proctor.html)
