---
title: The renovate component
description: Runs Renovate as a scheduled or manual job that bumps versions across the group's repositories and merges the green ones itself.
---

# The renovate component

This page covers the `renovate` component: what the job does, how to include
it, and every input it takes. Goal: one scheduled job keeps image digests,
GitHub action SHAs and package versions current across the group's
repositories, and merges the updates whose pipeline is green. The component
flies on autopilot; majors keep a human in the seat.

## What the job does

The component runs [Renovate](https://docs.renovatebot.com/) as a scheduled
or manual job that bumps image digests, GitHub action SHAs and package
versions across the group's repositories, and merges the green ones itself.
Bumps of `component:` include pins are covered by the preset and wait for
review. Majors open a merge request and wait for a person. See
[Renovate](renovate.md) for what auto-merges and what waits.

Under the hood, the job:

- Runs only in scheduled pipelines (`$CI_PIPELINE_SOURCE == "schedule"`) and
  manual pipelines started from the web (`$CI_PIPELINE_SOURCE == "web"`).
- Points Renovate at the instance: `RENOVATE_PLATFORM` is `gitlab` and
  `RENOVATE_ENDPOINT` is `$CI_API_V4_URL`.
- Turns on autodiscovery (`RENOVATE_AUTODISCOVER: "true"`), limited to the
  `autodiscover_filter` glob, default `$CI_PROJECT_NAMESPACE/*`, relative to
  the runner project's namespace.
- Writes its `config.js` at job time. The `registryAliases` entry for the
  GitLab instance comes from the predefined `CI_SERVER_FQDN` variable:
  GitLab expands the key before the shell runs, and Node resolves the value
  when Renovate loads `config.js`. No hostname is stored in the template, so
  the public mirror stays clean.
- Adds the Squire kit commands to the `config.js` `allowedCommands` list when
  `squire_kit_tasks` is `true`, so the preset's Squire rule can refresh a kit in
  its merge request (see [Squire kits](renovate.md#squire-kits)). The list is
  empty otherwise.
- Passes `git_author` through as `RENOVATE_GIT_AUTHOR` and `dry_run` through
  as `RENOVATE_DRY_RUN`.
- Is interruptible and times out after 1 hour.

> [!WARNING]
> `RENOVATE_TOKEN` and `GITHUB_COM_TOKEN` are not set in the job's
> `variables:` on purpose. A self-reference such as `RENOVATE_TOKEN:
> $RENOVATE_TOKEN` arrives as literal text on GitLab 19.5 and shadows the
> masked project CI/CD variable, so the component leaves both tokens to the
> project and the masked values reach the job unchanged.

## Include the component

Add the include to the runner project's `.gitlab-ci.yml`, pinned to a full
commit SHA with the tag in a trailing comment, and set `git_author`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/renovate@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      git_author: "Preflight Bot <preflight-bot@example.com>"
```

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `job_name` | string | `renovate` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `renovate/renovate:44.192.2@sha256:37960a62ba1faa9079a7c4eead9b3f4470748a64ecd207e06c09fd8858673e17` | Docker image for the job. |
| `autodiscover_filter` | string | `$CI_PROJECT_NAMESPACE/*` | Glob limiting which projects Renovate discovers, relative to the runner project's namespace. |
| `dry_run` | string | `"null"` | Dry run mode: `null` (disabled), `lookup` or `full`. |
| `git_author` | string | none | Author of the commits and merge requests Renovate creates, in the form `Name <email>`. Required. |
| `squire_kit_tasks` | boolean | `false` | Allow the Squire kit commands of Preflight's preset (install the new `waynestate/squire` from Packagist, then `squire update` on the kit folder), so a Squire kit merge request arrives with its files refreshed. Off, the merge request bumps the version only and shows an artifact error. |

## Verify

Start the job manually from the web, or wait for the schedule. Expected: the
job bumps the versions it finds and merges the ones whose pipeline is green.
To try it without changes, set `dry_run` to `lookup` or `full`; `null`
(disabled) is the default.

## Related

- [Renovate](renovate.md): the shared preset, and what auto-merges, what waits and what waits for review.
- [The squire-kit component](component-squire-kit.md): the pipeline check that a kit matches the Squire release it records.
- [Include a component twice](include-twice.md): the `job_name` input in action.
- [Quick start](quick-start.md): wire one component into an app and watch the pipeline run it.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
