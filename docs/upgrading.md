---
title: Upgrading
description: How to move an app from one Preflight pin to the next.
---

# Upgrading

This page is the checklist for moving an app from one Preflight pin to the next, one released version at a time, newest first; every section follows `CHANGELOG.md`. Read the section for the version you are moving to, apply its steps, and verify on the next pipeline. Like a real preflight, the walk takes a few minutes and earns its keep: move the pin only after you have read the version notes.

## Unreleased

### Changed

The `portability` component's `buildah_image` default moved from the plain version tag to the immutable tag `quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb`: Red Hat re-pushed the plain version tag and garbage-collected the old digest, so a pipeline pinned to it broke. If your app overrides `buildah_image`, point it at an `-immutable` tag pinned by digest too.
The `composer-audit` component gains an `abandoned` input (`fail`, `report` or `ignore`) for how `composer audit` treats abandoned packages. No action needed: the default is `fail`, which is what the component already did, so existing pipelines behave exactly as before.
A new `a11y` component checks a site's pages with axe-core in Playwright (WCAG 2.1 AA by default; add `wcag22aa` for 2.2 AA). It is opt-in: add its include to start the gate, with `allow_failure: true` while the site fixes its first findings. See [The a11y component](guides/component-a11y.md). Preflight's own local gate (`scripts/a11y.sh`, `scripts/a11y.ps1`) now runs the component's checker, at 320 px instead of 360 px, with the reflow check; `tools/a11y/` is gone.
This release needs GitLab 18.7 or later: every component now declares `spec: component:` and prints a `Preflight component` line as its first command, and GitLab accepts that spec key only from 18.7 on. On an older instance, pipeline creation fails on the unknown key, so upgrade GitLab or pin an older Preflight tag.

## 0.1.4

Released 2026-11-03. The new pieces are opt-in: the `portability` component, a `job_name` input on every component except `portability`, and a stricter Renovate preset.

### Breaking

0.1.4 has no breaking changes: the version adds a component, an input and preset rules, and removes nothing.

### Deprecated

Nothing was deprecated in 0.1.4.

### Steps

Point each component include at the `0.1.4` tag, pinned to the tag's full commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
```

A mirrored package pins the same SHA in its GitHub workflow:

```yaml
jobs:
  ci:
    uses: waynestate/preflight/.github/workflows/php-package.yml@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
```

Adopt the new pieces when you want them:

- **`portability`**: it ships in 0.1.4 and later (0.1.3 does not include it), so pin the `0.1.4` tag, or the full commit SHA of a commit at or after it. The build job needs a runner that permits user namespaces (Buildah uses unshare for its storage); the run job needs only the project's container registry and an app image that carries curl, sha256sum and tar.
- **`job_name`**: it ships in 0.1.4, so pin 0.1.4 or a SHA at or after that release. Set it when one project includes the same component more than once, for example in a monorepo with two apps; without it the two jobs would share a name and merge into one.
- **Renovate preset**: component version bumps now really wait for review instead of auto-merging (the component-rule manager name is `gitlabci`, matching repository deps), and a bump of the recorded Squire kit version carries the `squire-kit` label and never auto-merges; a person runs `squire update` to refresh the kit files.

> [!NOTE]
> Pins change only through a reviewed merge request. A tag or branch can move; a SHA cannot.

### How to verify

Push the change and run the app's pipeline. The components are ordinary jobs, so they run whenever the app's pipeline runs; expect the same jobs as before, green. PROCTOR's `preflight-pinned` check warns when an include is not pinned to a commit SHA. If you added `portability`, the `portability-run` job passes only when the image boots the strict way and the goss checks hold.

## 0.1.3

Released 2026-11-03. Two consumer-facing changes: the `proctor` component installs the app with `--no-plugins --no-scripts`, and the shared Renovate preset stopped auto-merging the pins that every pipeline runs.

### Breaking

0.1.3 has no breaking changes, but the `proctor` job now installs the app's dependencies with `composer install --no-plugins --no-scripts`, so the app's plugins and scripts never run inside the job.

### Deprecated

Nothing was deprecated in 0.1.3.

### Steps

Bump each component include to the `0.1.3` tag's full commit SHA, with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@<full commit SHA> # 0.1.3
```

If your group runs the shared Renovate preset, read the two behavior changes before you merge the bump:

- Updates inside `templates/**`, `contract/**` and `.gitlab-ci.yml`, and bumps of a Preflight component version in an app's `component:` include, no longer auto-merge: they carry the `needs-review` label and wait for a person.
- The `renovate` component no longer sets `RENOVATE_TOKEN` and `GITHUB_COM_TOKEN` from themselves in the job `variables:`; on GitLab 19.5 that self-reference arrived as literal text and shadowed the masked project CI/CD variables, so the job now reads both tokens straight from the project.

> [!WARNING]
> Do not add `RENOVATE_TOKEN: $RENOVATE_TOKEN` to your own `variables:`; that self-reference arrives as literal text.

### How to verify

Run the pipeline and confirm the jobs run on the new pin. In the runner project, confirm the job reads `RENOVATE_TOKEN` straight from the project as a masked CI variable, and that a bump touching the templates, the contract or a component include pin opens a merge request labeled `needs-review` instead of auto-merging.

## 0.1.2

Released 2026-10-29. The site gained the agent-ready kit (prompt blocks, Markdown twins, llms.txt) from Squire, and the proof page moved to a private site that needs a Wayne State sign-in.

### Breaking

0.1.2 has no breaking changes: the version touches the site, the README and the proof page, not the components.

### Deprecated

Nothing was deprecated in 0.1.2.

### Steps

Bump each component include to the `0.1.2` tag's full commit SHA, with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@<full commit SHA> # 0.1.2
```

### How to verify

Run the pipeline and confirm the component jobs run on the new pin. PROCTOR's `preflight-pinned` check warns when an include is not pinned to a commit SHA.

## 0.1.1

Released 2026-10-29. Two new components: `package-publish`, which publishes a semantic version tag to the GitLab group's built-in Composer registry, and `renovate`, with the shared preset `renovate/default.json`. The reusable GitHub Actions workflow for mirrors ships in this tag too.

### Breaking

0.1.1 has no breaking changes: the version adds components and changes only the repository's own PHPStan config.

### Deprecated

Nothing was deprecated in 0.1.1.

### Steps

Bump the existing includes to the `0.1.1` tag's full commit SHA, and add the new components where you want them:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/package-publish@<full commit SHA> # 0.1.1
    inputs:
      group_id: "<your group id>"
```

`group_id` is required: the numeric id of the GitLab group whose built-in Composer registry hosts the package.

> [!WARNING]
> Protect your release tags. A component ref is a tag, so whoever can move it controls every pipeline that pins it.

A package mirrored to GitHub calls the reusable workflow from its own `.github/workflows/ci.yml`; the workflow ships in the `0.1.1` tag, so pin the full commit SHA of the release tag and keep the tag in a trailing comment:

```yaml
name: CI

on:
  push:
    branches: ['**']
    tags: ['v*', '*.*.*']

jobs:
  ci:
    uses: waynestate/preflight/.github/workflows/php-package.yml@<full commit SHA> # 0.1.1
```

### How to verify

Run the pipeline. For `package-publish`, the job runs only on tags and reads the registry first: a version already published from this commit passes quietly, and a version published from a different commit fails the pipeline. For a mirrored package, a release tag is not done until it is green on both sides.

## 0.1.0

Released 2026-10-27. First tagged release.

### Breaking

0.1.0 is the first tagged release, so there is nothing to break: it is the baseline every later pin moves from.

### Deprecated

Nothing was deprecated in 0.1.0.

### Steps

Include the components pinned to the `0.1.0` tag's full commit SHA:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@<full commit SHA> # 0.1.0
```

### How to verify

Run the pipeline and confirm the component jobs run on the pin.

## Related

- [Changelog](changelog.md): the raw entries this page is built from.
- [Install](install.md): the requirements, the include snippet, and how to verify the pipeline picked the component up.
- [Updating image pins](guides/image-pins.md): why the pins are digests and how to look one up.
- [Renovate](guides/renovate.md): what auto-merges, what waits, and what the runner project owes.
- [Troubleshooting](troubleshooting.md): symptoms, causes and fixes.
- [Overview](index.md): what Preflight is and where the manual starts.
