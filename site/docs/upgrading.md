---
title: "Upgrading | Preflight docs"
description: "How to move an app from one Preflight pin to the next."
url: https://preflight.apps.wayne.edu/docs/upgrading.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Upgrading [#](https://preflight.apps.wayne.edu/docs/upgrading.html#upgrading)

This page is the checklist for moving an app from one Preflight pin to the next, one released version at a time, newest first; every section follows `CHANGELOG.md`. Read the section for the version you are moving to, apply its steps, and verify on the next pipeline. Like a real preflight, the walk takes a few minutes and earns its keep: move the pin only after you have read the version notes.

Every input and job name a component offers is recorded in `contract/inputs.json`, and Preflight's build fails when a template drifts from it, so the file is the exact list of what moved. Before you move a pin, diff it between your tag and the next one (for example `git diff 0.4.0 0.5.0 -- contract/inputs.json` in a clone of Preflight) and check each line against that version's Breaking and Steps below. [The inputs contract](https://preflight.apps.wayne.edu/docs/guides/inputs-contract.html) explains what each kind of change means for your include.

## 0.7.0 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-7-0)

Released 2026-11-10. One new input on the portability component, `setup_command`, for the step a platform runs before it scales an app out: migrating the database. No input or job was renamed or removed. A short hop: same aircraft, one more item on the checklist.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking)

- None. `setup_command` defaults to empty, and an empty value runs nothing.

### New: setup_command [#](https://preflight.apps.wayne.edu/docs/upgrading.html#new-setup-command)

The probe runs `setup_command` once, in a container of the built image named `portability-setup`, after any `services` are up and before replica A or B starts. A non-zero exit fails the job with `setup: FAIL` and the last 40 lines of its output. A pass shows as `setup` in the job's summary. The must-fail case `setup-fails` proves it.

Use it with `services` and `session-hop`: a database both replicas share is empty until the app migrates it, so the replicas' first session write fails without it. For a Laravel app:

```yaml
      services: [{ name: "mysql:8.4.7@sha256:<digest>", alias: db, variables: { MYSQL_ROOT_PASSWORD: "portability", MYSQL_DATABASE: "app" } }]
      setup_command: php artisan migrate --force
      checks: ["health", "env-only", "forwarded-headers", "logs", "sigterm", "healthcheck", "session-hop"]
```

Pin the service image by digest, as every Preflight default is, and point the app's `DB_HOST` at the alias. See [the portability guide](https://preflight.apps.wayne.edu/docs/guides/component-portability.html).

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps)

1. Move every Preflight include to the 0.7.0 tag's full commit SHA, with `# 0.7.0` in a trailing comment.
2. An app that runs `session-hop` against a `services` database adds `setup_command` with its migration command.
3. Nothing else changes.

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify)

- The portability job's summary lists `setup` as passed when `setup_command` is set, and has no `setup` line when it is empty.

## 0.6.0 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-6-0)

Released 2026-11-10. This release adds one component, `mysql56-migrate`, which proves an app's migrations on the MySQL Citadel really runs. The portability job also runs the image's own `HEALTHCHECK` and can start a shared database for `session-hop`. No input or job was renamed or removed. Cleared for takeoff, with one more gauge on the panel.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-1)

**The `healthcheck` check is in the default `checks`.** An include that leaves `checks` at its default now runs the image's own `HEALTHCHECK` command inside replica A, as the app's uid, and fails when it exits non-zero three times in a row. An image that declares no `HEALTHCHECK` still passes, with a note (set `require_healthcheck: true` to fail instead). If your image's health command only works as root, or calls a tool the image lacks, fix the command in the same change as the bump. An include that lists `checks` itself does not get the new check until you add `healthcheck` to its list.

### Changed [#](https://preflight.apps.wayne.edu/docs/upgrading.html#changed)

- The portability job builds with `buildah bud --format docker`, because Buildah's default OCI format drops `HEALTHCHECK`. The image the probe boots is otherwise the same.
- New portability inputs: `require_healthcheck` (boolean, default `false`) and `services` (array, default `[]`, the same shape as GitLab's `services:` keyword). See [the portability guide](https://preflight.apps.wayne.edu/docs/guides/component-portability.html).

### New: mysql56-migrate [#](https://preflight.apps.wayne.edu/docs/upgrading.html#new-mysql56-migrate)

CREED's database rule says an app MUST run its migrations in CI against a real MySQL 5.6, because SQLite accepts DDL that 5.6.51 rejects (a `JSON` column, a `utf8mb4` unique index longer than 767 bytes). The component starts `mysql:5.6.51` as a service, waits for it, installs `pdo_mysql` (and Composer 2.11.1, when the image has none), and runs `migrate_command` (default `php artisan migrate --force --no-interaction`).

- It carries the `amd64` runner tag by default, since the official MySQL 5.6 images are amd64 only. On a GitLab with no amd64-tagged runner, set `tags: []` on an amd64 or emulating default runner.
- It runs on the default branch and tags, is manual (and allowed to fail) on merge requests, and never runs from a schedule.
- A raw PHP app passes its own migration command; [the guide](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html) has both includes.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-1)

1. Move every Preflight include to the 0.6.0 tag's full commit SHA, with `# 0.6.0` in a trailing comment.
2. If the app has migrations, add the `mysql56-migrate` include.
3. If the portability job runs with the default `checks`, boot the image locally and run its `HEALTHCHECK` command as a uid with no name in group 0 before you push.
4. An app that keeps sessions in its database (WELD does) can now add `session-hop` back: give the portability include a `services` database and point `DB_HOST` at its alias.

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-1)

- The `mysql56-migrate` job is green on the default branch, and its log ends with the app's own migration output.
- The portability job's summary lists `healthcheck` as passed, or as passed with the "declares no HEALTHCHECK" note.

## 0.5.0 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-5-0)

Released 2026-11-09. A new component, `npm-audit`, the front-end half of `composer-audit`; a portability probe that starts each replica the way a container runtime does, so an Apache image needs no `start_command` shim; a proctor job that keeps PROCTOR's JSON report as `proctor.json` for Rollcall; and Composer 2.11.1 in every default. No input or job was renamed or removed.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-2)

**The portability launcher.** The `portability` job now starts each replica through a launcher that gives it stdout and stderr its uid owns and a session of its own (`setsid`), as a container runtime does. An include that still carries a `start_command` shim calling `setsid` (WELD's was `exec setsid bash -c '...'`) breaks on 0.5.0: inside the launcher the shim forks the app away from the replica's main process, and `health` fails. Delete the shim in the same change as the bump. With an empty `start_command` the job runs the image's own `ENTRYPOINT` and `CMD`, which is what an Apache image (Squire's portable image, a Sourdough or WELD app) needs. A `start_command` that only starts the app, with no `setsid` and no stdio redirect, keeps working.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated)

Nothing was deprecated in 0.5.0.

### Changed [#](https://preflight.apps.wayne.edu/docs/upgrading.html#changed-1)

- **Composer 2.11.1.** Every Composer default moves from 2.10.3 to 2.11.1: the `composer-audit`, `sbom`, `pint`, `phpstan`, `package-publish` and `squire-kit` images are `composer:2.11.1@sha256:8de2184c...` (the multi-arch list digest), and php-test's and proctor's `composer_version` default is `2.11.1`. 2.11.0 fixed GHSA-c968-33g3-wh7p and GHSA-fm2w-xgf2-f9fh, and 2.10 is no longer maintained. 2.11 drops the `source-fallback` setting; no component sets it. An include that sets `image` or `composer_version` keeps its own pin.
- **proctor keeps `proctor.json`.** The proctor job's artifact now keeps PROCTOR's JSON report as `proctor.json` for 30 days, next to the Code Quality report, whether the job passed or failed. That is the file Rollcall reads with `ROLLCALL_PROCTOR_SOURCE=gitlab`. The job adds `--record "$CI_PROJECT_DIR/proctor.json"` itself, and only when `proctor_command` is a plain `proctor check` line and the app's PROCTOR is 0.11.0 or later. On PROCTOR 0.10.0 or older the job runs exactly as before and the runner warns that `proctor.json` matched no files. The proctor line's exit code still decides the job.
- **renovate's `dry_run` pattern is on record.** `contract/inputs.json` now lists the `^(null|lookup|full)$` pattern the renovate template already enforced in 0.4.0, so the contract diff shows that line changed. No value that passed on 0.4.0 stops passing.

### New: npm-audit [#](https://preflight.apps.wayne.edu/docs/upgrading.html#new-npm-audit)

The `npm-audit` component runs `npm audit` on the app's `package-lock.json` in the `eslint` component's Node image and fails on an advisory at or above `audit_level` in a runtime dependency, then prints a full report that never fails. It is opt-in. Its inputs and defaults:

- `audit_level`: `high` by default; `low`, `moderate`, `high` or `critical`. CREED's and Composer's word `medium` is accepted too and maps to npm's `moderate`.
- `omit_dev`: `true` by default, so the failing audit leaves dev dependencies out; the full report still lists them.
- `working_dir`: `.` by default; the directory that holds `package-lock.json`, relative to the project root.
- `stage`, `job_name`, `image` and `image_prefix`, as on the other components.

An app with no lock file (no `package-lock.json` or `npm-shrinkwrap.json`) passes with a note, `npm-audit: no lock file ... nothing to audit.`, so a PHP-only app never goes red. An unreachable registry fails the job. See [The npm-audit component](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html).

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-2)

1. If an include of `portability` sets a `start_command` shim that calls `setsid`, delete the shim (or the whole `start_command` line) in the same change as step 2.
2. Point each component include at the `0.5.0` tag, pinned to the tag's full commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@60314791565a264e97cb210813ef4f3e76512402 # 0.5.0
```

3. Optional: add `npm-audit` for an app with a front end:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/npm-audit@60314791565a264e97cb210813ef4f3e76512402 # 0.5.0
    inputs:
      audit_level: high
```

4. Optional: to feed Rollcall, move the app to PROCTOR 0.11.0 or later (`composer require --dev waynestate/proctor:^0.11`).

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-2)

The pipeline is green. The `portability` job passes all its checks with no shim, the composer-based jobs' `Pulling docker image` line names `composer:2.11.1`, and on PROCTOR 0.11.0 or later the proctor job's artifact holds `proctor.json`. With `npm-audit` included, its log ends with `npm audit`'s summary, or with the no-lock-file note. Checklist done, doors armed: cleared for takeoff.

## 0.4.0 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-4-0)

Released 2026-11-08. Two new inputs and a Composer floor. The proctor component's `git_depth` (default `"0"`) clones the full history, so PROCTOR's override-approver check can read git blame on every override line instead of reporting could-not-run past GitLab's 20-commit default. php-test's `php_advisory_version` runs one more PHP version, such as a release candidate, in a separate job that may fail. php-test and proctor refuse a `composer_version` older than 2.9.6, the floor with the 2026 security fixes.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-3)

An include that sets `composer_version` on php-test or proctor to a version older than 2.9.6 no longer starts: GitLab rejects the input before the pipeline runs. The default (2.10.3) is unaffected, and no other input, default or job name changed.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated-1)

Nothing was deprecated in 0.4.0.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-3)

1. If an include sets `composer_version` below 2.9.6, remove the input (the default is 2.10.3) or set 2.9.6 or later.
2. Point each component include at the `0.4.0` tag, pinned to the tag's full commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
```

3. Optional: on a very large repository, set the proctor component's `git_depth` to a number such as `50`; override lines older than that then report could-not-run. To hear about the next PHP early, set php-test's `php_advisory_version`, for example `8.6.0RC2`.

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-3)

The pipeline is green, the proctor job log's fetch line no longer says `git depth set to 20` (unless you set `git_depth`), and with `php_advisory_version` set a `php-test-advisory` job runs and may fail without failing the pipeline.

## 0.3.1 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-3-1)

Released 2026-11-08. Every component that installs packages caches under a fixed key per component (such as `preflight-pint`, or `preflight-php-8.4` for one PHP version of `php-test`) instead of a lock-file hash, and saves its cache even when the job fails. A lock change, or a retry after a dropped download, fetches only what is missing.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-4)

0.3.1 has no breaking changes: inputs, defaults and job names are the same as in 0.3.0.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated-2)

Nothing was deprecated in 0.3.1.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-4)

Point each component include at the `0.3.1` tag, pinned to the tag's full commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@b90323b5823287a7840095d0d5f0682aaeedf327 # 0.3.1
```

The first pipeline on the new pin fills the new cache keys, so expect it to download everything once.

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-4)

The pipeline is green, and a component's job log shows `Creating cache preflight-` followed by the component's key, and, after a failed job, `Saving cache for failed job`.

## 0.3.0 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-3-0)

Released 2026-11-08. Docker Hub images now come through the group's Dependency Proxy by default (a new `image_prefix` input), and more components cache their Composer and npm downloads.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-5)

Every component whose image comes from Docker Hub (`proctor`, `php-test`, `composer-audit`, `sbom`, `pint`, `phpstan`, `eslint`, `secret-detection`, `package-publish`, `renovate`, `squire-kit`) now pulls `image_prefix/image`, and `image_prefix` defaults to your group's Dependency Proxy (`${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}`). `image` keeps its default and is the path after the prefix. Only an app that overrides `image`, or runs where the proxy is off, needs to act:

1. If the override was `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/<image>` only to reach the proxy, delete the `image:` input; the default does the same. Keeping it puts the prefix in twice, and the pull fails.
2. If it names a different Docker Hub image, drop the `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/` part and keep the rest.
3. If it names another registry, move the host and path into `image_prefix` and keep the rest in `image`.
4. On a GitLab or group without the proxy, set `image_prefix: docker.io`.

`a11y` (mcr.microsoft.com) and `portability` (quay.io) have no `image_prefix` and are unchanged: the proxy serves Docker Hub only.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated-3)

Nothing was deprecated in 0.3.0.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-5)

1. Move every Preflight include to the `0.3.0` tag in one change, pinned to the tag's full commit SHA with the tag in a trailing comment, and remove any proxied `image:` input in the same change (step 1 above):
   ```yaml
   include:
     - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@23038dfe767f6ef60e3b2efca1128f53d9acdff7 # 0.3.0
   ```
   Before:
   ```yaml
     - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@<old SHA> # 0.2.0
       inputs:
         image: ${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/php:8.4-cli-trixie@sha256:<digest>
   ```
   After:
   ```yaml
     - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@23038dfe767f6ef60e3b2efca1128f53d9acdff7 # 0.3.0
       inputs:
         image: php:8.4-cli-trixie@sha256:<digest>
   ```
2. On a GitLab or group without the Dependency Proxy, add `image_prefix: docker.io` to each Docker Hub include's `inputs`.
3. A mirrored package moves the SHA in its GitHub workflow (`.github/workflows/ci.yml`) to the same commit.

Verify: the job log's `Pulling docker image` line shows the prefix once, and each job's first line (`Preflight component <name> ...`) shows the new ref and sha. See [Dependency caching](https://preflight.apps.wayne.edu/docs/guides/dependency-caching.html).

## 0.2.0 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-2-0)

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-6)

The `portability` component is now one job, `portability` (named by a new `job_name` input), instead of `portability-build` and `portability-run`, and it checks what ADR-0010 asks for instead of the goss list. It builds the image with Buildah and runs it in the same job, so nothing is pushed to the container registry and no app image is pulled. Only an app that already includes `portability` from 0.1.4 needs to act:

- `buildah_image` is renamed `image` (same default, the Buildah image pinned by digest); the old `image` input (the app image) is gone.
- `start_command` is optional: empty runs the image's own `ENTRYPOINT` and `CMD`, the way the platforms do. Keep it only if your image needs a different start.
- New inputs with defaults: `job_name`, `build_args`, `runtime_paths`, `port_env`, `env`, `stop_timeout`, `probe_path`, `identity_header`, `session_login_path`, `session_check_path`, `logs_path` and `checks`. Set `env` to what the app needs to boot (secrets from CI/CD variables), and either add a test sign-in route for `session-hop` or leave it out of `checks`.
- Anything that waited on `portability-run` with `needs:` now names `portability`.
- The app image needs no curl, sha256sum or tar any more; the probe runs outside it.

See [The portability component](https://preflight.apps.wayne.edu/docs/guides/component-portability.html) for the six checks and how to fix each failure.

### Changed [#](https://preflight.apps.wayne.edu/docs/upgrading.html#changed-2)

The Buildah image default (now the `portability` component's `image` input) moved from the plain version tag to the immutable tag `quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb`: Red Hat re-pushed the plain version tag and garbage-collected the old digest, so a pipeline pinned to it broke. If your app overrides it, point it at an `-immutable` tag pinned by digest too. The `composer-audit` component gains an `abandoned` input (`fail`, `report` or `ignore`) for how `composer audit` treats abandoned packages. No action needed: the default is `fail`, which is what the component already did, so existing pipelines behave exactly as before. A new `a11y` component checks a site's pages with axe-core in Playwright (WCAG 2.1 AA by default; add `wcag22aa` for 2.2 AA). It is opt-in: add its include to start the gate, with `allow_failure: true` while the site fixes its first findings. See [The a11y component](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html). Preflight's own local gate (`scripts/a11y.sh`, `scripts/a11y.ps1`) now runs the component's checker, at 320 px instead of 360 px, with the reflow check; `tools/a11y/` is gone. A new `squire-kit` component fails the pipeline when a Squire deploy kit drifts from the Squire release its `.squire.json` records (`squire init --check`). It is opt-in: run `vendor/bin/squire init --check --path=deploy` first, clean up what it reports, then add the include with `working_dir: deploy`. See [The squire-kit component](https://preflight.apps.wayne.edu/docs/guides/component-squire-kit.html). The Renovate preset no longer updates files inside a Squire kit (`docker-compose.squire.yml` and `.squire/**`, outside Squire's own `templates/`): those bumps made every kit drift. Its Squire rule now runs `squire update` on the kit in the merge request it opens for a new Squire. The runner must allow those commands: set `squire_kit_tasks: true` on the runner project's `renovate` include. Until it does, each Squire merge request shows an artifact error and needs `vendor/bin/squire update --path=deploy` run by hand, as before. See [Squire kits](https://preflight.apps.wayne.edu/docs/guides/renovate.html#squire-kits). This release needs GitLab 18.7 or later: every component now declares `spec: component:` and prints a `Preflight component` line as its first command, and GitLab accepts that spec key only from 18.7 on. On an older instance, pipeline creation fails on the unknown key, so upgrade GitLab or pin an older Preflight tag.

## 0.1.4 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-1-4)

Released 2026-11-03. The new pieces are opt-in: the `portability` component, a `job_name` input on every component except `portability`, and a stricter Renovate preset.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-7)

0.1.4 has no breaking changes: the version adds a component, an input and preset rules, and removes nothing.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated-4)

Nothing was deprecated in 0.1.4.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-6)

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

Note

Pins change only through a reviewed merge request. A tag or branch can move; a SHA cannot.

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-5)

Push the change and run the app's pipeline. The components are ordinary jobs, so they run whenever the app's pipeline runs; expect the same jobs as before, green. PROCTOR's `preflight-pinned` check warns when an include is not pinned to a commit SHA. If you added `portability`, the `portability-run` job passes only when the image boots the strict way and the goss checks hold.

## 0.1.3 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-1-3)

Released 2026-11-03. Two consumer-facing changes: the `proctor` component installs the app with `--no-plugins --no-scripts`, and the shared Renovate preset stopped auto-merging the pins that every pipeline runs.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-8)

0.1.3 has no breaking changes, but the `proctor` job now installs the app's dependencies with `composer install --no-plugins --no-scripts`, so the app's plugins and scripts never run inside the job.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated-5)

Nothing was deprecated in 0.1.3.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-7)

Bump each component include to the `0.1.3` tag's full commit SHA, with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@<full commit SHA> # 0.1.3
```

If your group runs the shared Renovate preset, read the two behavior changes before you merge the bump:

- Updates inside `templates/**`, `contract/**` and `.gitlab-ci.yml`, and bumps of a Preflight component version in an app's `component:` include, no longer auto-merge: they carry the `needs-review` label and wait for a person.
- The `renovate` component no longer sets `RENOVATE_TOKEN` and `GITHUB_COM_TOKEN` from themselves in the job `variables:`; on GitLab 19.5 that self-reference arrived as literal text and shadowed the masked project CI/CD variables, so the job now reads both tokens straight from the project.

Warning

Do not add `RENOVATE_TOKEN: $RENOVATE_TOKEN` to your own `variables:`; that self-reference arrives as literal text.

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-6)

Run the pipeline and confirm the jobs run on the new pin. In the runner project, confirm the job reads `RENOVATE_TOKEN` straight from the project as a masked CI variable, and that a bump touching the templates, the contract or a component include pin opens a merge request labeled `needs-review` instead of auto-merging.

## 0.1.2 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-1-2)

Released 2026-10-29. The site gained the agent-ready kit (prompt blocks, Markdown twins, llms.txt) from Squire, and the proof page moved to a private site that needs a Wayne State sign-in.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-9)

0.1.2 has no breaking changes: the version touches the site, the README and the proof page, not the components.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated-6)

Nothing was deprecated in 0.1.2.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-8)

Bump each component include to the `0.1.2` tag's full commit SHA, with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@<full commit SHA> # 0.1.2
```

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-7)

Run the pipeline and confirm the component jobs run on the new pin. PROCTOR's `preflight-pinned` check warns when an include is not pinned to a commit SHA.

## 0.1.1 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-1-1)

Released 2026-10-29. Two new components: `package-publish`, which publishes a semantic version tag to the GitLab group's built-in Composer registry, and `renovate`, with the shared preset `renovate/default.json`. The reusable GitHub Actions workflow for mirrors ships in this tag too.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-10)

0.1.1 has no breaking changes: the version adds components and changes only the repository's own PHPStan config.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated-7)

Nothing was deprecated in 0.1.1.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-9)

Bump the existing includes to the `0.1.1` tag's full commit SHA, and add the new components where you want them:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/package-publish@<full commit SHA> # 0.1.1
    inputs:
      group_id: "<your group id>"
```

`group_id` is required: the numeric id of the GitLab group whose built-in Composer registry hosts the package.

Warning

Protect your release tags. A component ref is a tag, so whoever can move it controls every pipeline that pins it.

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

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-8)

Run the pipeline. For `package-publish`, the job runs only on tags and reads the registry first: a version already published from this commit passes quietly, and a version published from a different commit fails the pipeline. For a mirrored package, a release tag is not done until it is green on both sides.

## 0.1.0 [#](https://preflight.apps.wayne.edu/docs/upgrading.html#0-1-0)

Released 2026-10-27. First tagged release.

### Breaking [#](https://preflight.apps.wayne.edu/docs/upgrading.html#breaking-11)

0.1.0 is the first tagged release, so there is nothing to break: it is the baseline every later pin moves from.

### Deprecated [#](https://preflight.apps.wayne.edu/docs/upgrading.html#deprecated-8)

Nothing was deprecated in 0.1.0.

### Steps [#](https://preflight.apps.wayne.edu/docs/upgrading.html#steps-10)

Include the components pinned to the `0.1.0` tag's full commit SHA:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@<full commit SHA> # 0.1.0
```

### How to verify [#](https://preflight.apps.wayne.edu/docs/upgrading.html#how-to-verify-9)

Run the pipeline and confirm the component jobs run on the pin.

## Related [#](https://preflight.apps.wayne.edu/docs/upgrading.html#related)

- [Changelog](https://preflight.apps.wayne.edu/docs/changelog.html): the raw entries this page is built from.
- [Install](https://preflight.apps.wayne.edu/docs/install.html): the requirements, the include snippet, and how to verify the pipeline picked the component up.
- [Updating image pins](https://preflight.apps.wayne.edu/docs/guides/image-pins.html): why the pins are digests and how to look one up.
- [Renovate](https://preflight.apps.wayne.edu/docs/guides/renovate.html): what auto-merges, what waits, and what the runner project owes.
- [Troubleshooting](https://preflight.apps.wayne.edu/docs/troubleshooting.html): symptoms, causes and fixes.
- [Overview](https://preflight.apps.wayne.edu/docs/index.html): what Preflight is and where the manual starts.
