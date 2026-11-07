---
title: Troubleshooting
description: What to do when a Preflight job fails or a gate behaves unexpectedly.
---

# Troubleshooting

What to do when a Preflight job fails or a gate behaves unexpectedly. Each entry names the cause, the fix, and how to check it. Most failures are a pin that moved or a setting that is missing. The checklist catches the rest.

> [!TIP]
> Start with the job log. The message usually names the input that is wrong, and every input is listed on the [Components](reference/components.md) page.

## The pipeline

### The include fails on another GitLab instance

Components work only inside the GitLab instance that hosts this project, and they cannot be used across instances except by mirroring.

- **Cause:** the app lives on a different instance than the one that hosts Preflight.
- **Fix:** host the app on the same instance. For a package that is also mirrored to GitHub, use the reusable workflow at `.github/workflows/php-package.yml` in this repo instead of the components.
- **Check:** the include path starts with `$CI_SERVER_FQDN/enterprise-apps/preflight/`, and the app's project is on that same instance.

### The components do not run on merge requests

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

### A gate was skipped or weakened

An included component is a set of ordinary jobs. The app's own `.gitlab-ci.yml` is merged over them, so an app can override a job's keys, skip it with `rules`, or delete the `include:` line. Preflight makes the safe pipeline the easy one. It does not lock it.

- **Cause:** a change in the app's own `.gitlab-ci.yml` overrides, skips or removes a component job.
- **Fix:** review the diff of the app's `.gitlab-ci.yml` against the last known-good pipeline, and restore the job or the `include:` line.
- **Check:** Rollcall is where skipped or weakened gates show up.

### Two includes of the same component became one job

Every component except `portability` takes a `job_name` input, whose default is the job's usual name. Without it, two includes of the same component share a job name and merge into one.

- **Cause:** one project includes the same component more than once (for example in a monorepo with two apps) without setting `job_name`.
- **Fix:** set `job_name` on each include, for example `pint-app` and `pint-admin`. `job_name` ships in 0.1.4, so pin 0.1.4 or a SHA at or after that release.
- **Check:** the pipeline lists one job per include, with the names you set.

### Pipeline creation fails on the unknown `spec: component:` key

Every Preflight component declares `spec: component:`, and GitLab only accepts that key from 18.7 on. On an older instance the pipeline never starts: creation fails with "header:spec config contains unknown keys".

- **Cause:** the GitLab instance is older than 18.7.
- **Fix:** upgrade GitLab to 18.7 or later, or pin an older Preflight tag that does not declare `spec: component:`.
- **Check:** the instance banner shows 18.7 or later, and the pipeline creates and runs the component jobs.

### A fork merge request ran with protected variables

A fork's merge request pipeline runs the fork's configuration.

- **Cause:** the project lets fork pipelines see protected variables.
- **Fix:** review a fork's `.gitlab-ci.yml` before running its pipeline, and never give it protected variables.
- **Check:** the fork pipeline's variable list does not include any protected variable.

## Job failures

### A job misbehaves: which Preflight release ran?

Every Preflight job prints a `Preflight component <name> <version> (ref <reference>, sha <sha>)` line before any other command. When a job fails or behaves unexpectedly, read that first line to see which Preflight release produced it: `<name>` is the component, `<version>` the pinned release tag, `<reference>` the ref the include points at, and `<sha>` the commit SHA of the template that ran. Compare it with the pin in the app's `.gitlab-ci.yml`; a mismatch means the include moved or the pipeline ran on an older pin.

- **Cause:** the job log does not say which Preflight release ran, so the failure cannot be tied to a pin.
- **Fix:** read the `Preflight component` line at the top of the job log. If the line is missing, the include is pinned to a Preflight release from before the line shipped; pin the current tag.
- **Check:** the first line of the job log names the component, its version, reference and SHA, and they match the pin in the app's `.gitlab-ci.yml`.

### PROCTOR's preflight-pinned check warns

A tag or branch can move. A SHA cannot. PROCTOR's `preflight-pinned` check warns when an include is not pinned to a commit SHA.

- **Cause:** the include is pinned to a tag or a branch instead of a full commit SHA.
- **Fix:** pin the full commit SHA and keep the tag in a trailing comment, as in the examples on the [Components](reference/components.md) page.
- **Check:** PROCTOR's report no longer carries the `preflight-pinned` finding.

### composer-audit is green, then an advisory lands

New advisories are published after code is merged, so a green pipeline today can be stale tomorrow.

- **Cause:** no pipeline has run since the advisory was published.
- **Fix:** create a weekly pipeline schedule on the default branch: project settings, Build, Pipeline schedules. The component needs nothing extra. It carries no `rules:` block, so it runs in scheduled pipelines like any other. Someone with Maintainer rights on the app creates the schedule.
- **Check:** the schedule appears under project settings, Build, Pipeline schedules, and its latest pipeline is green.

### composer-audit fails on an abandoned package

The job log names an abandoned package in the lock. An abandoned package is one its author no longer maintains, and `composer audit` fails the job on one by default.

- **Cause:** the lock holds a package marked abandoned, and the `abandoned` input is at its default, `fail`.
- **Fix:** upgrade the package or move to its successor where the log names one. While that is not possible, set the `abandoned` input on the include: `report` lists the abandoned packages without failing the job (right for an old app with abandoned transitive packages), `ignore` does not look at them at all. Advisories still fail the job in every mode.
- **Check:** with `report`, the job is green and its log lists the abandoned packages; with `fail`, the job fails until the lock no longer holds one.

### composer install stops: the lock needs another PHP or an extension

The job log stops at `composer install` with `your php version (8.4.x) does not satisfy that requirement`, or with `requires ext-gd * -> it is missing from your system` (gd, oci8 and ldap are the usual ones). The `php-test`, `pint` and `phpstan` jobs install the app to run it, so they need what the app needs.

- **Cause:** the lock was built for an older PHP, or the app needs a PHP extension that the default image does not have. The default `php:*-cli` and `composer` images carry only the extensions PHP builds in.
- **Fix:** for an old PHP, upgrade the app: that red job is the finding, not a fault in Preflight. For an extension, set the job's `image` input to an image that has the same extensions as the app's Citadel image, for example one built `FROM php:8.4-cli-trixie` with `docker-php-ext-install gd`. The `proctor` and `sbom` jobs never run the app, so they install with `--ignore-platform-reqs` and need neither.
- **Check:** the `composer install` step of the job passes, and the job fails, if at all, on its own check.

### composer install cannot clone a private package

The job log shows `Failed to execute git clone --mirror` for a repository on the app's own GitLab instance, or `Could not connect to server`.

- **Cause:** the lock installs a package straight from a private Git repository, and the job has no credential for it. A local `auth.json` never reaches CI.
- **Fix:** give Composer a credential in the pipeline, for example a masked CI/CD variable `COMPOSER_AUTH` holding an `http-basic` entry for the instance with a deploy token that can read the package's project. Prefer publishing the package to the GitLab package registry and listing only that project in the job token allowlist; see [Keep the job token allowlist short](guides/job-token-allowlist.md).
- **Check:** the `composer install` step passes in a pipeline on a branch.

### eslint stops at npm ci

The `eslint` job stops at `npm ci` with the usage text, before ESLint runs.

- **Cause:** `npm ci` needs a `package-lock.json`, and the app keeps only a `yarn.lock` or a `pnpm-lock.yaml`.
- **Fix:** commit a `package-lock.json` (run `npm install` once), or leave the `eslint` component out until the app moves to npm.
- **Check:** `npm ci --ignore-scripts` passes locally from a clean checkout.

### php-test-next is red

A red `php-test-next` job is an early warning, not a stop. It is the second `php-test` include that tries the PHP release that is not supported yet, with `allow_failure: true` in the app's own file.

- **Cause:** the next PHP release still fails the app's tests, or only has release candidate images.
- **Fix:** leave `allow_failure: true` in place while the release is unsupported. Once the release is supported (the supported versions follow `policy.json`), drop the `allow_failure` and move the version into the main `php_versions` list.
- **Check:** the main `php-test` matrix is green. Only the named `php-test-next` job is red.

### package-publish refuses the tag

The job reads the registry before publishing. Republishing a version from the same commit is a no-op, and republishing it from a different commit fails instead of overwriting the version, because GitLab would otherwise overwrite it without a word.

- **Cause:** the tag's version already exists in the group's Composer registry, published from a different commit.
- **Fix:** publish a new version tag instead of moving the old one. Protect the release tags so only maintainers can create or move a tag.
- **Check:** the job log shows the version already on the manifest and the commit it was published from.

### portability is not in the pinned ref

Portability ships in 0.1.4 and later. 0.1.3 does not include it.

- **Cause:** the include is pinned to a tag or SHA at or before 0.1.3.
- **Fix:** pin the `0.1.4` tag, or the full commit SHA of a commit at or after it.
- **Check:** the pipeline lists `portability-build` and `portability-run`.

### portability-build fails on the runner

The build job runs Buildah, which uses unshare for its storage.

- **Cause:** the runner does not permit user namespaces.
- **Fix:** run the build job on a runner that permits user namespaces. The job sets `STORAGE_DRIVER: vfs`, so it needs no special kernel support beyond that.
- **Check:** the job log shows an unshare failure before the fix, and a successful `buildah bud` after it.

### portability-run's health check ends in EOF

goss sends the HTTP method as written, and a lower-case one makes the server close the connection, so the health check failed with EOF. The check now uses `method: GET`, fixed in 0.1.4.

- **Cause:** the include is pinned to a ref before 0.1.4, where the goss health check used a lower-case method.
- **Fix:** pin 0.1.4 or a SHA at or after it.
- **Check:** `goss validate` passes the health check instead of ending in EOF.

### a11y fails on a page that looked fine

The job checks each page in light and dark mode at 320 px and 1280 px, with reduced motion, so it sees layouts and palettes a quick look in one browser misses.

- **Cause:** a fault that shows in one mode only, and the failing test case names that mode, for example `docs/index.html dark 320px`: a dark palette with weak contrast, a label hidden at phone width, or a fixed-width element that makes the page scroll sideways at 320 px (`preflight-reflow`, which names the element where the overflow starts).
- **Fix:** open the page in that mode (dark color scheme, a 320 px window) and fix the element the report names; each axe-core rule links its help page. While a site works through its first findings, set `allow_failure: true` on the include and remove it once the job is green.
- **Check:** the job's last line reads `a11y: clean`, and the merge request's test summary shows every case passing.

### a11y stops with a configuration error (exit 2)

Exit 2 means the job never judged a page: an input or a tool is wrong.

- **Cause:** one of the messages below.
  - `no file under site matches the page pattern ...`: a glob in `pages` matched nothing, often because the docs folder moved. A literal page that is missing fails its check with HTTP 404 instead.
  - `site folder not found`: `site_dir` does not exist in the job, for example because the site is built in another job and not passed as an artifact.
  - `cannot read the Playwright version from the image tag`: `image` was overridden with an image whose tag does not carry `vX.Y.Z`.
  - `Chromium did not start`: the playwright npm version does not match the browsers in the image.
  - `axe-core X ran, but axe_core_version is Y`: `axe_playwright_version` names a bridge whose axe-core range does not include `axe_core_version`.
- **Fix:** correct the input the message names: fix the glob or `site_dir`, set `playwright_version` to the Playwright release in the image, or move `axe_core_version` and `axe_playwright_version` together (Renovate bumps them as one group).
- **Check:** the job log's second line names the site or URL and the Playwright version, and the summary line names the axe-core version that ran.
## Renovate

### Renovate sees literal text instead of a token

On GitLab 19.5 a self-reference such as `RENOVATE_TOKEN: $RENOVATE_TOKEN` in the job `variables:` arrives as literal text and shadows the masked project CI/CD variables. The component does not map either token on purpose. The job reads both straight from the project.

- **Cause:** the runner project, or the app's file, adds `RENOVATE_TOKEN: $RENOVATE_TOKEN` or `GITHUB_COM_TOKEN: $GITHUB_COM_TOKEN` to `variables:`.
- **Fix:** delete the self-reference. Keep `RENOVATE_TOKEN` (and optionally `GITHUB_COM_TOKEN`) as masked CI variables in the private runner project.
- **Check:** the job log no longer shows the literal text `$RENOVATE_TOKEN`, and Renovate authenticates.

### Renovate auto-merged a component pin bump

In refs before 0.1.4 the component-rule manager name in `renovate/default.json` did not match repository deps, so a bump of a `component:` include version auto-merged instead of waiting for review.

- **Cause:** the shared preset comes from a ref before the 0.1.4 fix.
- **Fix:** point the repositories' `renovate.json` at the shared preset from 0.1.4 or later. Component version bumps now carry the `needs-review` label and never auto-merge.
- **Check:** the merge request carries the `needs-review` label.

## Local checks

### The portability fixtures fail on permissions

The app user is not the host user that owns the fixtures' temp dir, and goss is downloaded into it. As of 0.1.4 the fixtures make their temp dir mode 0777 and the goss files in it mode 0644.

- **Cause:** the checkout is from a ref before 0.1.4.
- **Fix:** update to 0.1.4 or later, then rerun `sh tests/check-portability.sh` (or the `.ps1` twin).
- **Check:** the script exits 0: `good` passes and both `bad-*` fixtures fail.

### composer ci fails on a stale docs site

`composer ci` runs `docs:check`, which fails when the built docs site is stale or the generated command or environment reference has drifted from the CLI or source.

- **Cause:** a page under `docs/` (or a generated reference) changed without rebuilding `site/docs/`.
- **Fix:** run `composer docs` to rebuild `site/docs/` from `docs/`, and commit the rebuilt site with the page.
- **Check:** `composer docs:check` passes.

## Related

- [Components](reference/components.md)
- [Local checks](reference/local-checks.md)
- [When the components run](guides/when-components-run.md)
- [What the components cannot force](guides/what-components-cannot-force.md)
- [Same instance only](guides/same-instance-only.md)
- [Include a component twice](guides/include-twice.md)
- [Renovate](guides/renovate.md)
- [Updating image pins](guides/image-pins.md)
- [Changelog](changelog.md)
- [Upgrading](upgrading.md)
