---
title: The package-publish component
description: Publishes a semantic version tag to the GitLab group's built-in Composer registry.
---

# The package-publish component

This page covers the `package-publish` component: what the job does, how to
include it, and every input it takes. Goal: tagging a release publishes the
package to the GitLab group's built-in Composer registry, and a version that
is already published never gets overwritten.

Version 1 · Category: Release/Publishing · Tags: composer,publish,release

## What the job does

The job publishes a semantic version tag to the GitLab group's built-in
Composer registry. It runs only on tags, reads the registry first, and
refuses a moved version: a version already published from this commit passes
quietly, and a version published from a different commit fails the pipeline,
because GitLab would otherwise overwrite it without a word. Once a version is
on the manifest, it stays on the manifest: no go-arounds.

The job, in order:

1. Runs only when the pipeline is for a tag, so `$CI_COMMIT_TAG` is set.
2. Accepts only semantic versions, `1.2.3` or `v1.2.3` with an optional
   pre-release; any other tag fails the job.
3. Reads the package name from the `name` field of `composer.json` in the
   project root, the file the registry serves.
4. Reads the group's registry index (`packages.json`) with the read token. A
   `404` means the group has no published Composer packages yet, and the job
   goes straight to publishing. Otherwise it follows the index's
   `metadata-url` (on GitLab, `/api/v4/group/<id>/-/packages/composer/p2/%package%.json`)
   to the package's own file; a `404` there means this package has no
   published versions yet.
5. Finds the version in that file (keyed by version on GitLab, or a list of
   versions in Composer 2's plain form) and compares the commit it was
   published from (`source.reference`, else `dist.reference`) with
   `$CI_COMMIT_SHA`: the same commit exits quietly, a different commit fails
   the job instead of overwriting the version. A version with no recorded
   commit fails too, since the job cannot prove it is the same one.
6. Publishes the tag to the group's registry with the job token
   (`CI_JOB_TOKEN`) and reports the version as published.

The default image ships curl and PHP, which the job uses for the registry
round trip. The job is interruptible and times out after 30 minutes.

> [!WARNING]
> Protect your release tags.

> [!NOTE]
> The read token lives in a masked CI variable named by
> `read_token_variable` (default `PACKAGE_READ_TOKEN`) and needs the
> `read_package_registry` scope. Publishing itself uses the predefined
> `CI_JOB_TOKEN`.

## Include the component

Add the include to the app's `.gitlab-ci.yml`, pinned to a full commit SHA
with the tag in a trailing comment, and set `group_id` to the numeric id of
the GitLab group whose built-in Composer registry hosts the package:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/package-publish@435665959434e5b5adca563c34762bd7061a6b8a # 0.7.0
    inputs:
      group_id: "<your group id>"
```

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `deploy` | Pipeline stage for the job. |
| `job_name` | string | `package-publish` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0` | Docker image for the job. The default ships curl and PHP, which the job uses for the registry round trip. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `group_id` | string | none | Numeric id of the GitLab group whose built-in Composer registry hosts the package. Required. |
| `read_token_variable` | string | `PACKAGE_READ_TOKEN` | Name of the masked CI variable holding a token with the `read_package_registry` scope, used to read the registry before publishing. |

## Verify

Define the masked CI variable the component reads, then push a semantic
version tag. Expected: the `package-publish` job runs in the `deploy` stage,
reads the registry, and ends with `Version <version> published.` Pushing the
same tag from the same commit again exits quietly; the same version from a
different commit fails the job.

Preflight proves both without a registry of its own. `tests/check-package-publish-fails.sh`
(run in CI by `must-fail-package-publish`, and by its `.ps1` twin on Windows)
runs the template's own script against a fake registry that answers with the
shapes GitLab's Composer API documents, and expects: a version published from
another commit fails with no publish request (in GitLab's keyed form and in
Composer 2's list form), the same commit exits 0 with none, a new version and
a package with no versions yet are each published once, and an index that
answers 500 fails. Through 0.7.0 the job looked for the version in the wrong
places, so on GitLab it never saw a published version and would have
overwritten a moved one; this check is how that was caught.

## Related

- [Quick start](quick-start.md): wire one component into an app and watch the pipeline run it.
- [Install](../install.md): the requirements, the include snippet, and how to verify.
- [When the components run](when-components-run.md): the `workflow:rules` block that belongs in the app's own file.
- [Include a component twice](include-twice.md): the `job_name` input in action.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
