---
title: "The package-publish component | Preflight docs"
description: "Publishes a semantic version tag to the GitLab group's built-in Composer registry."
url: https://preflight.apps.wayne.edu/docs/guides/component-package-publish.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The package-publish component [#](https://preflight.apps.wayne.edu/docs/guides/component-package-publish.html#the-package-publish-component)

This page covers the `package-publish` component: what the job does, how to include it, and every input it takes. Goal: tagging a release publishes the package to the GitLab group's built-in Composer registry, and a version that is already published never gets overwritten.

Version 1 · Category: Release/Publishing · Tags: composer,publish,release

## What the job does [#](https://preflight.apps.wayne.edu/docs/guides/component-package-publish.html#what-the-job-does)

The job publishes a semantic version tag to the GitLab group's built-in Composer registry. It runs only on tags, reads the registry first, and refuses a moved version: a version already published from this commit passes quietly, and a version published from a different commit fails the pipeline, because GitLab would otherwise overwrite it without a word. Once a version is on the manifest, it stays on the manifest: no go-arounds.

The job, in order:

1. Runs only when the pipeline is for a tag, so `$CI_COMMIT_TAG` is set.
2. Accepts only semantic versions, `1.2.3` or `v1.2.3` with an optional pre-release; any other tag fails the job.
3. Reads the package name from the `name` field of `composer.json` in the project root, the file the registry serves.
4. Reads the registry index with the read token. A `404` means the group has no published Composer packages yet, and the job goes straight to publishing.
5. Compares the commit recorded for the version, if any, with `$CI_COMMIT_SHA`: the same commit exits quietly, a different commit fails the job instead of overwriting the version.
6. Publishes the tag to the group's registry with the job token (`CI_JOB_TOKEN`) and reports the version as published.

The default image ships curl and PHP, which the job uses for the registry round trip. The job is interruptible and times out after 30 minutes.

Warning

Protect your release tags.

Note

The read token lives in a masked CI variable named by `read_token_variable` (default `PACKAGE_READ_TOKEN`) and needs the `read_package_registry` scope. Publishing itself uses the predefined `CI_JOB_TOKEN`.

## Include the component [#](https://preflight.apps.wayne.edu/docs/guides/component-package-publish.html#include-the-component)

Add the include to the app's `.gitlab-ci.yml`, pinned to a full commit SHA with the tag in a trailing comment, and set `group_id` to the numeric id of the GitLab group whose built-in Composer registry hosts the package:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/package-publish@60314791565a264e97cb210813ef4f3e76512402 # 0.5.0
    inputs:
      group_id: "<your group id>"
```

## Inputs [#](https://preflight.apps.wayne.edu/docs/guides/component-package-publish.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `deploy` | Pipeline stage for the job. |
| `job_name` | string | `package-publish` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0` | Docker image for the job. The default ships curl and PHP, which the job uses for the registry round trip. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `group_id` | string | none | Numeric id of the GitLab group whose built-in Composer registry hosts the package. Required. |
| `read_token_variable` | string | `PACKAGE_READ_TOKEN` | Name of the masked CI variable holding a token with the `read_package_registry` scope, used to read the registry before publishing. |

## Verify [#](https://preflight.apps.wayne.edu/docs/guides/component-package-publish.html#verify)

Define the masked CI variable the component reads, then push a semantic version tag. Expected: the `package-publish` job runs in the `deploy` stage, reads the registry, and ends with `Version <version> published.` Pushing the same tag from the same commit again exits quietly; the same version from a different commit fails the job.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/component-package-publish.html#related)

- [Quick start](https://preflight.apps.wayne.edu/docs/guides/quick-start.html): wire one component into an app and watch the pipeline run it.
- [Install](https://preflight.apps.wayne.edu/docs/install.html): the requirements, the include snippet, and how to verify.
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html): the `workflow:rules` block that belongs in the app's own file.
- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html): the `job_name` input in action.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
