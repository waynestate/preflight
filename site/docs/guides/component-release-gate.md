---
title: "The release-gate component | Preflight docs"
description: "Fails a tag pipeline unless the default branch already ran a successful pipeline on the tagged commit."
url: https://preflight.apps.wayne.edu/docs/guides/component-release-gate.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The release-gate component [#](https://preflight.apps.wayne.edu/docs/guides/component-release-gate.html#the-release-gate-component)

This page covers the `release-gate` component: what the job does, how to include it, and every input it takes. Goal: when a repo opts its test components into `tag_pipeline: release-only`, a tag pipeline skips the tests and runs only the release jobs, and this gate is the proof that skipping them is safe.

Version 1 · Category: Release/Publishing · Tags: release,gate,tag-pipeline

## What the job does [#](https://preflight.apps.wayne.edu/docs/guides/component-release-gate.html#what-the-job-does)

The job runs in the `.pre` stage, before every other stage, so a failure stops the whole tag pipeline before any release job starts. It runs only on tags, and it answers one question: did the default branch already run a successful pipeline on this exact commit? Skipping the tests is only safe if the answer is yes, and the job is how the pipeline finds out.

The job, in order:

1. Runs only when the pipeline is for a tag, so `$CI_COMMIT_TAG` is set.
2. Asks the GitLab API, with the job token (`CI_JOB_TOKEN`) and nothing else, for a successful pipeline of `$CI_COMMIT_SHA` on `$CI_DEFAULT_BRANCH`. A hit passes the gate: the default branch tested this very commit, so the tag pipeline can release what was already green. An empty list fails the job, because the commit was never tested on the default branch.
3. When the API cannot be read (the job token may not list pipelines on some GitLab installations, or the API is unreachable), the job falls back to git: it fetches the default branch and checks that the tagged commit is an ancestor of it.

The git fallback has an honest limit. It proves the commit is on the default branch, not that it passed there: git history records merges, not pipeline results. In fallback mode the gate's green-ness rests on the release procedure instead, which says to tag only after main is green. The job prints that in its log when it falls back.

A repo with no release jobs gets no tag pipeline at all. GitLab does not run a pipeline whose only jobs sit in `.pre`, and once the test components opt into `tag_pipeline: release-only` the gate is the only job left. Where release jobs do exist, the gate refuses a tag on a commit the default branch never tested.

The default image ships git and curl, which the job uses for the API check and the git fallback. The job is interruptible and times out after 5 minutes.

Note

The gate reads the API with the predefined `CI_JOB_TOKEN` only. It needs no extra CI variables, and it never asks for a project access token.

## Include the component [#](https://preflight.apps.wayne.edu/docs/guides/component-release-gate.html#include-the-component)

Opt in by setting `tag_pipeline: release-only` on the test components you want skipped on tag pipelines, and include this component. Pin the include to a full commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@44e683f6dc1a24913af50959827f1f50da2be23d # 0.10.0
    inputs:
      tag_pipeline: release-only
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/release-gate@44e683f6dc1a24913af50959827f1f50da2be23d # 0.10.0
```

## Inputs [#](https://preflight.apps.wayne.edu/docs/guides/component-release-gate.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `.pre` | Pipeline stage for the release-gate job. The default, .pre, runs before every other stage, so a failed gate stops the whole tag pipeline. |
| `job_name` | string | `release-gate` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0` | Docker image for the release-gate job. The default ships git and curl, which the job uses for the API check and the git fallback. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path put in front of the image input. The default is this group's GitLab Dependency Proxy, so Docker Hub images are pulled once and then served from GitLab's cache. On a GitLab or group without the proxy, set it to docker.io. No trailing slash. |

## Verify [#](https://preflight.apps.wayne.edu/docs/guides/component-release-gate.html#verify)

Push a semantic version tag at a commit the default branch already ran green. Expected: the `release-gate` job runs first, in the `.pre` stage, names the pipeline it found, and passes, and the release jobs run after it. Tag a commit the default branch never tested, and the gate fails the pipeline before anything else starts.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/component-release-gate.html#related)

- [Quick start](https://preflight.apps.wayne.edu/docs/guides/quick-start.html): wire one component into an app and watch the pipeline run it.
- [Install](https://preflight.apps.wayne.edu/docs/install.html): the requirements, the include snippet, and how to verify.
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html): the `workflow:rules` block that belongs in the app's own file.
- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html): the `job_name` input in action.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
