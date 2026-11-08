---
title: "The php-test component | Preflight docs"
description: "Runs the test command on each supported PHP version through `parallel:matrix`."
url: https://preflight.apps.wayne.edu/docs/guides/component-php-test.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The php-test component[#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#the-php-test-component)

Every engine gets its own check: this component runs your test command once per supported PHP version. This page shows how to add the `php-test` component to your app's `.gitlab-ci.yml`, how the matrix and the cache work, and how to trial the next PHP release. Next, add the [composer-audit component](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html).

## Include the component[#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#include-the-component)

Goal: your app's test suite runs on each supported PHP version. The component runs the test command on each supported PHP version through `parallel:matrix`. Add the include to your app's `.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@b90323b5823287a7840095d0d5f0682aaeedf327 # 0.3.1
    inputs:
      test_command: vendor/bin/phpunit
```

## Inputs[#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the jobs. |
| `job_name` | string | `php-test` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `php:${PHP_VERSION}-cli-trixie` | Docker image for the jobs. The default carries the literal `${PHP_VERSION}`, which GitLab expands in the image at job time. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `php_versions` | array | `["8.3", "8.4", "8.5"]` | PHP versions to test against. |
| `composer_version` | string | `2.10.3` | Composer version to install. |
| `test_command` | string | `vendor/bin/phpunit` | The test command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |

Note

The template adds regexes to three inputs: `job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, `composer_version` must match `^2\.\d+\.\d+$`, and `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$`.

## What the jobs do[#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#what-the-jobs-do)

The array input feeds `parallel:matrix` directly, so one job is created per PHP version. `PHP_VERSION` becomes a CI/CD variable in each job, which the `image` input's default expands at job time. The default image is deliberately tag-pinned, so each job runs the newest patch release of its PHP version. Each job is `interruptible: true` with a `timeout: 30 minutes`, and its script:

1. Installs `unzip` and `git` with `apt-get`, because the `php:*-cli` images do not ship them (the images are Debian-based, so `apt` is used).
2. Copies the official Composer installer from `getcomposer.org` and verifies its SHA-384 against the signature fetched at runtime from `composer.github.io/installer.sig`. On a mismatch the check deletes the installer and exits 1. No `$` variables appear in the `php -r` code, so GitLab CI variable expansion cannot corrupt it.
3. Runs the installer quietly with `--install-dir=/usr/local/bin --filename=composer` and the pinned `composer_version`, so Composer lands on PATH, then removes `composer-setup.php`.
4. Changes into `working_dir` and runs `composer install --no-interaction --no-progress`.
5. Runs `test_command`.

## Caching[#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#caching)

The jobs always cache Composer downloads in `.composer-cache/` so repeat runs do not re-download every package. The cache key is fixed per PHP version, not a `composer.lock` hash (D-072), so a lock change downloads only the packages that changed and each PHP version gets its own cache:

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

## Try the next PHP release without breaking the pipeline[#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#try-the-next-php-release-without-breaking-the-pipeline)

Include `php-test` a second time for the release that is not supported yet, name that job, and let it fail. The name is what lets your own `.gitlab-ci.yml` loosen only that job:

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

## Related[#](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html#related)

- [The proctor component](https://preflight.apps.wayne.edu/docs/guides/component-proctor.html)
- [The composer-audit component](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html)
