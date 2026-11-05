---
title: Renovate
description: Preflight owns the stack's version automation: the shared preset and the component that runs it.
---

# Renovate: what merges and what waits

This page covers what Preflight's version automation auto-merges, what waits
for a person, and how the private runner project is set up. For the
component's inputs, go to [the `renovate` component](./component-renovate.md).

## How it works

Preflight owns the stack's version automation (ADR-0015): the shared preset
`renovate/default.json` and the
[`renovate` component](./component-renovate.md) that runs it. A private runner project
includes the component on a schedule; Renovate discovers every repository in
the filter, opens merge requests for outdated versions, and GitLab's native
auto-merge takes in the ones whose pipeline is green.

Every stack repository carries a `renovate.json` that extends the shared
preset, so the rules change in one place:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["local>enterprise-apps/preflight//renovate/default"]
}
```

## What auto-merges

Digest updates, pin and pinDigest updates, and patch and minor version bumps
auto-merge when the pipeline is green. Lock file maintenance runs weekly and
auto-merges the same way. Every merge request carries the `auto-deps` label.

The exception is Preflight's own pins: an update that touches the templates,
the contract or this repository's own pipeline, a bump of a component include
version, and a bump of the recorded Squire kit version, never auto-merge (see
[What waits for review](#what-waits-for-review)).

## What waits

Major version bumps never auto-merge. The merge request carries the `major`
label and waits for a person.

## What waits for review

Updates that change an image digest inside the templates, the contract, or
this repository's own pipeline, bumps of a Preflight component version in an
app's `component:` include, and bumps of the recorded Squire kit version
(labeled `squire-kit`) carry the `needs-review` label and never auto-merge.
They wait for a person because those pins are what every app pipeline runs:
a changed digest here changes what every consuming pipeline executes, so it
earns a human eye even when its own pipeline is green. The Squire kit version
bump is refreshed by a person who runs `squire update` (with the right path
for the repo), reviews the diff and commits it to the branch; the runner runs
no commands, so the merge request carries no postUpgradeTasks.

## Why MySQL and HA-Proxy get digests only

The `mysql` and `haproxy` images mirror the versions Citadel actually runs,
not the newest releases in the world. Bumping their tags would drift the apps
away from production, so only digest updates are enabled for them: the same
tag, the exact image. `citadel/php-apache` is disabled entirely, because
Squire's own data owns that image.

## Pinned to immutable tags

The `quay.io/buildah/stable` image (the `buildah_image` default of the
portability component) is matched to `-immutable` tags only. Red Hat re-pushed
v1.43.5 under the mutable tag and garbage-collected the old digest, which broke
an image job, so DRAWBRIDGE and SQUIRE now pin the immutable form,
`v1.43.5-immutable@sha256:...`. The preset carries a packageRule for
`quay.io/buildah/stable` with a regex versioning that only matches
`vX.Y.Z-immutable` tags, so Renovate proposes updates within the immutable tags
and never moves a pin back to a mutable one. Digests stay pinned as before
(`docker:pinDigests`).

## Set up (the user does this)

This repository ships the preset and the component, and creates nothing else.
A person must set up:

- A private runner project that includes the `renovate` component on a
  schedule (see [The runner project](#the-runner-project)).
- The `RENOVATE_TOKEN` masked CI variable in that project, and optionally
  `GITHUB_COM_TOKEN`.
- A pipeline schedule on that project so the job runs regularly; weekly on
  Monday is a sensible default.

## The runner project

> [!WARNING]
> The runner project must stay private. It holds `RENOVATE_TOKEN`, a token
> that can open and merge merge requests across the group, and this
> repository is mirrored to public GitHub. Use a group bot account for the
> token, not a person's: the bot outlives any one maintainer, and the commits
> keep one stable author.

| Variable | Required | What it does |
|----------|----------|--------------|
| `RENOVATE_TOKEN` | yes | Masked CI variable in the runner project; the job reads it straight from the project, the component does not map it. A project access token with Developer, or Maintainer where only Maintainers may merge. |
| `GITHUB_COM_TOKEN` | no | Masked CI variable in the runner project; the job reads it straight from the project, the component does not map it. Lookups against github.com do not hit anonymous rate limits. |

> [!WARNING]
> Do not add `RENOVATE_TOKEN: $RENOVATE_TOKEN` to your own `variables:`; that
> self-reference arrives as literal text.

The component writes its `config.js` at job time, so the `registryAliases`
entry for the GitLab instance comes from the predefined `CI_SERVER_FQDN`
variable. No hostname is stored in this repository.

## Related

- [The `renovate` component](./component-renovate.md)
- [GitHub mirrors](./github-mirrors.md)
- [Image pins](./image-pins.md)
- [Quick start](./quick-start.md)

