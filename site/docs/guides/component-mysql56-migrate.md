---
title: "The mysql56-migrate component | Preflight docs"
description: "Runs the app's migrations against MySQL 5.6.51, the version of the shared server on Citadel."
url: https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The mysql56-migrate component [#](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html#the-mysql56-migrate-component)

The mysql56-migrate component makes CREED's database rule runnable: an app MUST run its migrations in CI against a real MySQL 5.6, because Citadel's shared server is MySQL 5.6.51. A test suite on SQLite can pass DDL that 5.6 rejects, most famously a `JSON` column and a utf8mb4 index longer than 767 bytes. This component starts the exact Squire pin, `mysql:5.6.51`, as a GitLab service, waits for it, and runs the app's migration command. If the migration would fail on the shared server, the pipeline says so before release.

## Add the include [#](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html#add-the-include)

A Laravel app needs only the include: the default `migrate_command` is `php artisan migrate --force --no-interaction`, and the job sets the `DB_*` variables Laravel reads.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/mysql56-migrate@<full commit SHA> # <tag>
```

Pin the full commit SHA of the release tag you use.

Note

The official MySQL 5.6 images are amd64 only, so the job defaults to `tags: ["amd64"]`. On a GitLab without an amd64-tagged runner, set `tags: []` on an amd64 or emulating runner.

## Inputs [#](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the mysql56-migrate job. |
| `job_name` | string | `mysql56-migrate` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `php:8.3-cli-trixie@sha256:628102249d93494233b54490b785f12db9cd60f4dc89416dfca15973f2125f10` | Container image for the job. It needs PHP 8.3 or later; the job installs any missing `php_extensions` itself. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path put in front of the image and service_image values. The default is this group's GitLab Dependency Proxy, so Docker Hub images are pulled once and then served from GitLab's cache. On a GitLab or group without the proxy, set it to `docker.io`. No trailing slash. |
| `service_image` | string | `mysql:5.6.51@sha256:20575ecebe6216036d25dab5903808211f1e9ba63dc7825ac20cb975e34cfcae` | MySQL 5.6.51 service image, the same pin Squire runs locally. |
| `db_name` | string | `app` | Database name created by the service. |
| `db_user` | string | `app` | Database user created by the service. |
| `db_password` | string | `preflight-mysql56-ci` | Throwaway password for the ephemeral service; nothing outside the job connects to it. |
| `migrate_command` | string | `php artisan migrate --force --no-interaction` | Command that runs the app's migrations. |
| `tags` | array | `["amd64"]` | Runner tags for the job. The official MySQL 5.6 images are amd64 only; set an empty list on an amd64 or emulating default runner. |
| `php_extensions` | array | `["pdo_mysql"]` | PHP extensions installed with `docker-php-ext-install` unless `php -m` already lists them. |

## How the job works [#](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html#how-the-job-works)

The job is named by `job_name` (default `mysql56-migrate`). It runs in the `test` stage by default, is `interruptible: true`, and has a timeout of 30 minutes. In order, it:

1. Installs every extension in `php_extensions` that `php -m` does not already list. The official `php:*-cli` images ship `PDO` and `mysqlnd` but not `pdo_mysql`.
2. Runs `composer install --no-interaction --no-progress` when a `composer.json` exists, using the fixed Composer cache key `preflight-mysql56-migrate` and the path `.composer-cache/`.
3. Waits for the MySQL service with a bounded loop: up to 60 tries, 2 seconds apart. Each try is a PDO connect through `php -r`. On timeout it prints one clear line and exits 1.
4. Runs `migrate_command` with the job's `DB_*` variables: `DB_CONNECTION=mysql`, `DB_HOST=mysql`, `DB_PORT=3306`, and the `db_name`, `db_user` and `db_password` values.

The service is `mysql:5.6.51`, pinned by digest and reached through `image_prefix`, with `alias: mysql`. The service creates the database and user from the same inputs, so the job never points at a database outside the pipeline.

### A raw PHP app [#](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html#a-raw-php-app)

An app without Laravel points `migrate_command` at the script that applies its migrations:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/mysql56-migrate@<full commit SHA> # <tag>
    inputs:
      migrate_command: php database/migrate.php
```

The script reads the same `DB_*` environment variables. It does not need a framework, a queue worker or a running web server.

## Gating [#](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html#gating)

The rules are baked into the component, like WELD's portability job:

- never on `schedule` pipelines;
- run on tags and on the default branch;
- `when: manual` with `allow_failure: true` on merge requests;
- nothing else.

That keeps a real 5.6 container off scheduled runs and off the small shared amd64 host except where a migration actually changed.

## Verify locally [#](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html#verify-locally)

Preflight's own pipeline includes the component on a clean fixture (`tests/mysql56-migrate/clean`) and runs `tests/check-mysql56-migrate.sh` as `must-fail-mysql56-migrate`. The check drops and recreates the database before each case, proves the clean fixture exits 0, and proves the two flawed fixtures fail with the server errors 5.6 reports: a `JSON` column (error 1064) and a too-long utf8mb4 index (error 1071). See [Local checks](https://preflight.apps.wayne.edu/docs/reference/local-checks.html) for the commands.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/component-mysql56-migrate.html#related)

- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html): the `job_name` input.
- [Same instance only](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html): components run only inside the GitLab instance that hosts this project.
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html): the `workflow:rules` block that belongs in the app's own file.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
