---
title: "The php-test component | Preflight docs"
description: "Runs the test command on each supported PHP version through `parallel:matrix`."
url: https://preflight.apps.wayne.edu/docs/guides/component-php-test.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The php-test component [#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#the-php-test-component)

Every engine gets its own check: this component runs your test command once per supported PHP version. PHP 8.6 runs as an advisory job that may fail; the required matrix is 8.3, 8.4, 8.5. This page shows how to add the `php-test` component to your app's `.gitlab-ci.yml`, how the matrix and the cache work, and how to trial the next PHP release. Next, add the [composer-audit component](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html).

## Include the component [#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#include-the-component)

Goal: your app's test suite runs on each supported PHP version. The component runs the test command on each supported PHP version through `parallel:matrix`. Add the include to your app's `.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@44e683f6dc1a24913af50959827f1f50da2be23d # 0.10.0
    inputs:
      test_command: vendor/bin/phpunit
```

## Inputs [#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the jobs. |
| `job_name` | string | `php-test` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `php:${PHP_VERSION}-cli-trixie` | Docker image for the jobs. The default carries the literal `${PHP_VERSION}`, which GitLab expands in the image at job time. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `php_versions` | array | `["8.3", "8.4", "8.5"]` | PHP versions to test against. |
| `php_advisory_version` | string | `"8.6"` | One more PHP version tested in a separate `<job_name>-advisory` job that may fail (`allow_failure: true`). Default `8.6` (the newest line, not yet required); set it to `""` for no advisory job. A release candidate still works (for example `8.7-rc`). Never add a release candidate to `php_versions`. |
| `composer_version` | string | `2.11.1` | Composer version to install, 2.9.6 or later. |
| `test_command` | string | `vendor/bin/phpunit` | The test command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |

Note

The template adds regexes to three inputs: `job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, `composer_version` must match `^2\.(9\.([6-9]|[1-9][0-9]+)|[1-9][0-9]+\.[0-9]+)$`, and `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$`.

## What the jobs do [#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#what-the-jobs-do)

The array input feeds `parallel:matrix` directly, so one job is created per PHP version. `PHP_VERSION` becomes a CI/CD variable in each job, which the `image` input's default expands at job time. The default image is deliberately tag-pinned, so each job runs the newest patch release of its PHP version. The `<job_name>-advisory` job runs the same script on `php_advisory_version` (default `8.6`) with `allow_failure: true`, and is skipped while that input is empty. Each job is `interruptible: true` with a `timeout: 30 minutes`, and its script:

1. Installs `unzip` and `git` with `apt-get`, because the `php:*-cli` images do not ship them (the images are Debian-based, so `apt` is used).
2. Installs `mbstring` only when `php -m` does not list it (with `libonig-dev` and `docker-php-ext-install`), because the official 8.6 image ships without it and PHPUnit needs it; a no-op on 8.3 to 8.5.
3. Copies the official Composer installer from `getcomposer.org` and verifies its SHA-384 against the signature fetched at runtime from `composer.github.io/installer.sig`. On a mismatch the check deletes the installer and exits 1. No `$` variables appear in the `php -r` code, so GitLab CI variable expansion cannot corrupt it.
4. Runs the installer quietly with `--install-dir=/usr/local/bin --filename=composer` and the pinned `composer_version`, so Composer lands on PATH, then removes `composer-setup.php`.
5. Changes into `working_dir` and runs `composer install --no-interaction --no-progress`.
6. Runs `test_command`.

## Caching [#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#caching)

The jobs always cache Composer downloads in `.composer-cache/` so repeat runs do not re-download every package. The cache key is fixed per PHP version, not a `composer.lock` hash, so a lock change downloads only the packages that changed and each PHP version gets its own cache:

```yaml
cache:
  key: preflight-php-${PHP_VERSION}
  paths:
    - .composer-cache/
  policy: pull-push
variables:
  COMPOSER_CACHE_DIR: "$CI_PROJECT_DIR/.composer-cache"
```

`COMPOSER_CACHE_DIR` points Composer at a path inside the project so GitLab can cache it.

## Try the next PHP release without breaking the pipeline [#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#try-the-next-php-release-without-breaking-the-pipeline)

By default the component already runs 8.6 in the `<job_name>-advisory` job that may fail, so this second include is only needed when you want to pin a release candidate tag or run the trial under your own job name. Include `php-test` a second time for the release that is not supported yet, name that job, and let it fail. The name is what lets your own `.gitlab-ci.yml` loosen only that job:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@<full commit SHA> # <tag>
    inputs:
      php_versions: ["8.6"]
      job_name: php-test-next
      # While 8.6 only has release candidate images, name the tag: php:${PHP_VERSION}-rc-cli-trixie
      # image: "php:${PHP_VERSION}-rc-cli-trixie"

php-test-next:
  allow_failure: true
```

A red `php-test-next` job is an early warning, not a stop. Drop the `allow_failure` and move the version into the main `php_versions` list once the release is supported (the supported versions follow `policy.json`).

## Testing the next PHP release [#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#testing-the-next-php-release)

By default the component already adds the `<job_name>-advisory` job, running your tests on 8.6 (the newest line, not yet required). Set `php_advisory_version` to a release candidate tag to trial that instead:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@44e683f6dc1a24913af50959827f1f50da2be23d # 0.10.0
    inputs:
      test_command: vendor/bin/phpunit
      php_advisory_version: "8.7-rc"
```

The value goes into the image tag, `php:<version>-cli-trixie`, so any tag the official `php` image publishes works: `8.7-rc` follows the newest release candidate, and an exact one such as `8.7.0RC5` stays put. Set the input to an empty string for no advisory job. The job warns, it never blocks; move the version into `php_versions` only once it is a final, supported release.

Preflight's own pipeline leaves the input at its default, so its advisory job runs the fixture app on PHP 8.6 and proves the input in a real pipeline (BEST_PRACTICES 6.4). When the 8.6 image shipped without the `mbstring` extension, which PHPUnit needs, the job stopped before the first test; the template now installs `mbstring` when the image lacks it, so PHPUnit starts. That is the point of the job: you hear about it from a yellow warning, well before it could turn a required job red.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#related)

- [The proctor component](https://preflight.apps.wayne.edu/docs/guides/component-proctor.html)
- [The composer-audit component](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html)
