---
title: "Troubleshooting | Preflight docs"
description: "What to do when a Preflight job fails or a gate behaves unexpectedly."
url: https://preflight.apps.wayne.edu/docs/troubleshooting.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Troubleshooting[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#troubleshooting)

What to do when a Preflight job fails or a gate behaves unexpectedly. Each entry names the cause, the fix, and how to check it. Most failures are a pin that moved or a setting that is missing. The checklist catches the rest.

Tip

Start with the job log. The message usually names the input that is wrong, and every input is listed on the [Components](https://preflight.apps.wayne.edu/docs/reference/components.html) page.

## The pipeline[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#the-pipeline)

### The include fails on another GitLab instance[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#the-include-fails-on-another-gitlab-instance)

Components work only inside the GitLab instance that hosts this project, and they cannot be used across instances except by mirroring.

- **Cause:** the app lives on a different instance than the one that hosts Preflight.
- **Fix:** host the app on the same instance. For a package that is also mirrored to GitHub, use the reusable workflow at `.github/workflows/php-package.yml` in this repo instead of the components.
- **Check:** the include path starts with `$CI_SERVER_FQDN/enterprise-apps/preflight/`, and the app's project is on that same instance.

### The components do not run on merge requests[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#the-components-do-not-run-on-merge-requests)

The components are ordinary jobs, so they run whenever the app's pipeline runs. Whether the pipeline runs on a merge request is decided by a `workflow:rules` block, and a component cannot set it for the project that includes it.

- **Cause:** the app's own `.gitlab-ci.yml` has no `workflow:rules` block with a `merge_request_event` rule.
- **Fix:** add the block to the app's own file:

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

- **Check:** a merge request pipeline runs, and so does a push to the default branch.

### A gate was skipped or weakened[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#a-gate-was-skipped-or-weakened)

An included component is a set of ordinary jobs. The app's own `.gitlab-ci.yml` is merged over them, so an app can override a job's keys, skip it with `rules`, or delete the `include:` line. Preflight makes the safe pipeline the easy one. It does not lock it.

- **Cause:** a change in the app's own `.gitlab-ci.yml` overrides, skips or removes a component job.
- **Fix:** review the diff of the app's `.gitlab-ci.yml` against the last known-good pipeline, and restore the job or the `include:` line.
- **Check:** Rollcall is where skipped or weakened gates show up.

### Two includes of the same component became one job[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#two-includes-of-the-same-component-became-one-job)

Every component except `portability` takes a `job_name` input, whose default is the job's usual name. Without it, two includes of the same component share a job name and merge into one.

- **Cause:** one project includes the same component more than once (for example in a monorepo with two apps) without setting `job_name`.
- **Fix:** set `job_name` on each include, for example `pint-app` and `pint-admin`. `job_name` ships in 0.1.4, so pin 0.1.4 or a SHA at or after that release.
- **Check:** the pipeline lists one job per include, with the names you set.

### A fork merge request ran with protected variables[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#a-fork-merge-request-ran-with-protected-variables)

A fork's merge request pipeline runs the fork's configuration.

- **Cause:** the project lets fork pipelines see protected variables.
- **Fix:** review a fork's `.gitlab-ci.yml` before running its pipeline, and never give it protected variables.
- **Check:** the fork pipeline's variable list does not include any protected variable.

## Job failures[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#job-failures)

### PROCTOR's preflight-pinned check warns[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#proctor-s-preflight-pinned-check-warns)

A tag or branch can move. A SHA cannot. PROCTOR's `preflight-pinned` check warns when an include is not pinned to a commit SHA.

- **Cause:** the include is pinned to a tag or a branch instead of a full commit SHA.
- **Fix:** pin the full commit SHA and keep the tag in a trailing comment, as in the examples on the [Components](https://preflight.apps.wayne.edu/docs/reference/components.html) page.
- **Check:** PROCTOR's report no longer carries the `preflight-pinned` finding.

### composer-audit is green, then an advisory lands[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#composer-audit-is-green-then-an-advisory-lands)

New advisories are published after code is merged, so a green pipeline today can be stale tomorrow.

- **Cause:** no pipeline has run since the advisory was published.
- **Fix:** create a weekly pipeline schedule on the default branch: project settings, Build, Pipeline schedules. The component needs nothing extra. It carries no `rules:` block, so it runs in scheduled pipelines like any other. Someone with Maintainer rights on the app creates the schedule.
- **Check:** the schedule appears under project settings, Build, Pipeline schedules, and its latest pipeline is green.

### php-test-next is red[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#php-test-next-is-red)

A red `php-test-next` job is an early warning, not a stop. It is the second `php-test` include that tries the PHP release that is not supported yet, with `allow_failure: true` in the app's own file.

- **Cause:** the next PHP release still fails the app's tests, or only has release candidate images.
- **Fix:** leave `allow_failure: true` in place while the release is unsupported. Once the release is supported (the supported versions follow `policy.json`), drop the `allow_failure` and move the version into the main `php_versions` list.
- **Check:** the main `php-test` matrix is green. Only the named `php-test-next` job is red.

### package-publish refuses the tag[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#package-publish-refuses-the-tag)

The job reads the registry before publishing. Republishing a version from the same commit is a no-op, and republishing it from a different commit fails instead of overwriting the version, because GitLab would otherwise overwrite it without a word.

- **Cause:** the tag's version already exists in the group's Composer registry, published from a different commit.
- **Fix:** publish a new version tag instead of moving the old one. Protect the release tags so only maintainers can create or move a tag.
- **Check:** the job log shows the version already on the manifest and the commit it was published from.

### portability is not in the pinned ref[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#portability-is-not-in-the-pinned-ref)

Portability ships in 0.1.4 and later. 0.1.3 does not include it.

- **Cause:** the include is pinned to a tag or SHA at or before 0.1.3.
- **Fix:** pin the `0.1.4` tag, or the full commit SHA of a commit at or after it.
- **Check:** the pipeline lists `portability-build` and `portability-run`.

### portability-build fails on the runner[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#portability-build-fails-on-the-runner)

The build job runs Buildah, which uses unshare for its storage.

- **Cause:** the runner does not permit user namespaces.
- **Fix:** run the build job on a runner that permits user namespaces. The job sets `STORAGE_DRIVER: vfs`, so it needs no special kernel support beyond that.
- **Check:** the job log shows an unshare failure before the fix, and a successful `buildah bud` after it.

### portability-run's health check ends in EOF[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#portability-run-s-health-check-ends-in-eof)

goss sends the HTTP method as written, and a lower-case one makes the server close the connection, so the health check failed with EOF. The check now uses `method: GET`, fixed in 0.1.4.

- **Cause:** the include is pinned to a ref before 0.1.4, where the goss health check used a lower-case method.
- **Fix:** pin 0.1.4 or a SHA at or after it.
- **Check:** `goss validate` passes the health check instead of ending in EOF.

## Renovate[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#renovate)

### Renovate sees literal text instead of a token[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#renovate-sees-literal-text-instead-of-a-token)

On GitLab 19.5 a self-reference such as `RENOVATE_TOKEN: $RENOVATE_TOKEN` in the job `variables:` arrives as literal text and shadows the masked project CI/CD variables. The component does not map either token on purpose. The job reads both straight from the project.

- **Cause:** the runner project, or the app's file, adds `RENOVATE_TOKEN: $RENOVATE_TOKEN` or `GITHUB_COM_TOKEN: $GITHUB_COM_TOKEN` to `variables:`.
- **Fix:** delete the self-reference. Keep `RENOVATE_TOKEN` (and optionally `GITHUB_COM_TOKEN`) as masked CI variables in the private runner project.
- **Check:** the job log no longer shows the literal text `$RENOVATE_TOKEN`, and Renovate authenticates.

### Renovate auto-merged a component pin bump[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#renovate-auto-merged-a-component-pin-bump)

In refs before 0.1.4 the component-rule manager name in `renovate/default.json` did not match repository deps, so a bump of a `component:` include version auto-merged instead of waiting for review.

- **Cause:** the shared preset comes from a ref before the 0.1.4 fix.
- **Fix:** point the repositories' `renovate.json` at the shared preset from 0.1.4 or later. Component version bumps now carry the `needs-review` label and never auto-merge.
- **Check:** the merge request carries the `needs-review` label.

## Local checks[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#local-checks)

### The portability fixtures fail on permissions[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#the-portability-fixtures-fail-on-permissions)

The app user is not the host user that owns the fixtures' temp dir, and goss is downloaded into it. As of 0.1.4 the fixtures make their temp dir mode 0777 and the goss files in it mode 0644.

- **Cause:** the checkout is from a ref before 0.1.4.
- **Fix:** update to 0.1.4 or later, then rerun `sh tests/check-portability.sh` (or the `.ps1` twin).
- **Check:** the script exits 0: `good` passes and both `bad-*` fixtures fail.

### composer ci fails on a stale docs site[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#composer-ci-fails-on-a-stale-docs-site)

`composer ci` runs `docs:check`, which fails when the built docs site is stale or the generated command or environment reference has drifted from the CLI or source.

- **Cause:** a page under `docs/` (or a generated reference) changed without rebuilding `site/docs/`.
- **Fix:** run `composer docs` to rebuild `site/docs/` from `docs/`, and commit the rebuilt site with the page.
- **Check:** `composer docs:check` passes.

## Related[#](https://preflight.apps.wayne.edu/docs/troubleshooting.html#related)

- [Components](https://preflight.apps.wayne.edu/docs/reference/components.html)
- [Local checks](https://preflight.apps.wayne.edu/docs/reference/local-checks.html)
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html)
- [What the components cannot force](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html)
- [Same instance only](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html)
- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html)
- [Renovate](https://preflight.apps.wayne.edu/docs/guides/renovate.html)
- [Updating image pins](https://preflight.apps.wayne.edu/docs/guides/image-pins.html)
- [Changelog](https://preflight.apps.wayne.edu/docs/changelog.html)
- [Upgrading](https://preflight.apps.wayne.edu/docs/upgrading.html)
