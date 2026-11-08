---
title: The eslint component
description: Runs the app's own ESLint and Prettier and fails the pipeline on lint or format errors.
---

# The eslint component

This page covers the `eslint` component: what the job does, how to include
it, and every input it takes. Goal: the app's pipeline fails on any lint or
format error, judged by the app's own config. Start with the include block,
then check the inputs against your app. Preflight is named for the pre-flight
check, and this component is the row that keeps the JavaScript airworthy.

Version 1 · Category: Testing/Validation · Tags: javascript,style,eslint,prettier

## What the job does

The component runs the app's own [ESLint](https://eslint.org/) (and
[Prettier](https://prettier.io/)) and fails the pipeline on lint or format
errors. It does not install ESLint or Prettier itself: the app must require
`@waynestate/pinstripe`, `eslint` and `prettier` as dev dependencies and
ship an `eslint.config.js` (or point `eslint_args` at its own files).

The job, in order:

1. Moves into `working_dir` (default `.`).
2. Installs the app's dependencies with `npm ci --ignore-scripts --cache .npm-cache`.
3. Runs `npx --no-install eslint` with `eslint_args` (default `.`).
4. When `prettier` is `true` (the default), runs `npx --no-install prettier --check .`.

The job caches npm downloads in `.npm-cache/`, with the cache key based on
`package-lock.json`. It is interruptible and times out after 15m.

## Include the component

Add the include to the app's `.gitlab-ci.yml`, pinned to a full commit SHA
with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@<full commit SHA> # 0.3.0
    inputs:
      eslint_args: .
```

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `eslint` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da` | Docker image for the job. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `working_dir` | string | `.` | Directory to run the commands in, relative to the project root. |
| `eslint_args` | string | `.` | Arguments passed to eslint. |
| `prettier` | boolean | `true` | Whether to also run `prettier --check`. |

## Verify

Push the change. The `eslint` job lands in the `test` stage by default, and
a green job means ESLint and Prettier found nothing to fix.

> [!NOTE]
> The `eslint` job has no `allow_failure` input: a lint or format error
> fails the pipeline.

## Related

- [Quick start](quick-start.md): wire one component into an app and watch the pipeline run it.
- [Install](../install.md): the requirements, the include snippet, and how to verify.
- [The phpstan component](component-phpstan.md): the static analysis check for the PHP side.
- [Include a component twice](include-twice.md): the `job_name` input in action.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
