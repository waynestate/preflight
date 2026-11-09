---
title: The proctor component
description: Runs `vendor/bin/proctor check --format=codequality` and publishes the result as a GitLab Code Quality report.
---

# The proctor component

A proctor keeps an eye on the exam hall; this one keeps an eye on your app. This page shows how to add the `proctor` component to your app's `.gitlab-ci.yml` and what the job does once it runs. Next, add the [php-test component](component-php-test.md) so the test suite runs on every supported PHP version.

## Include the component

Goal: your app's pipeline runs PROCTOR and publishes the result as a GitLab Code Quality report. Add the include to your app's `.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
    inputs:
      proctor_command: vendor/bin/proctor check --format=codequality
```

The job installs the app's dependencies with `composer install --no-plugins --no-scripts --ignore-platform-reqs`, so the app's plugins and scripts never run inside the job, and an app locked to an older PHP or needing an extension the image lacks (gd, oci8, ldap) still gets its report: the job reads the app and never runs it.

> [!NOTE]
> The install skips plugins and scripts on purpose: the job only inspects the app, so nothing in the app runs with the job's access.

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `proctor` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `php:8.4-cli-trixie@sha256:9cf851bc2c1b37c3e59dfd677a3c3e56d485af5a47c93f629424bb039eafcb69` | Docker image for the job. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `composer_version` | string | `2.11.1` | Composer version to install, 2.9.6 or later. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline. |
| `proctor_command` | string | `vendor/bin/proctor check --format=codequality` | The proctor command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |
| `git_depth` | string | `"0"` | How many commits the job clones (GitLab's `GIT_DEPTH`); the default `0` clones the full history, so PROCTOR's override-approver check can see who wrote each override. |

> [!NOTE]
> The template adds regexes to four inputs: `job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, `composer_version` must match `^2\.(9\.([6-9]|[1-9][0-9]+)|[1-9][0-9]+\.[0-9]+)$`, `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$`, and `git_depth` must match `^[0-9]+$`.

## What the job does

The job is `interruptible: true` with a `timeout: 30 minutes`. Its script:

1. Installs `unzip` and `git` with `apt-get`, because the `php:8.4-cli-trixie` image does not ship them (the image is Debian-based, so `apt` is used).
2. Copies the official Composer installer from `getcomposer.org` and verifies its SHA-384 against the signature fetched at runtime from `composer.github.io/installer.sig`. On a mismatch the check deletes the installer and exits 1. No `$` variables appear in the `php -r` code, so GitLab CI variable expansion cannot corrupt it.
3. Runs the installer quietly with `--install-dir=/usr/local/bin --filename=composer` and the pinned `composer_version`, so Composer lands on PATH, then removes `composer-setup.php`.
4. Changes into `working_dir` and runs `composer install --no-interaction --no-progress --no-plugins --no-scripts --ignore-platform-reqs`.
5. Runs `proctor_command` and redirects the output to `"$CI_PROJECT_DIR/gl-code-quality-report.json"`. A plain redirect (not `tee`) keeps proctor's exit code as the job result, and the report is written at the project root so the artifact path is the same for every `working_dir`, including `.`.

The job keeps Composer downloads in a cache under `.composer-cache/` with the fixed key `preflight-proctor` (D-072), so repeat runs skip downloads and a lock change fetches only what changed.

The job publishes the report with `artifacts: when: always` as a GitLab Code Quality report (`reports: codequality: gl-code-quality-report.json`).

> [!TIP]
> Set `allow_failure: true` if the job may fail without failing the pipeline; the default is `false`.

## Related

- [The php-test component](component-php-test.md)
- [The composer-audit component](component-composer-audit.md)
