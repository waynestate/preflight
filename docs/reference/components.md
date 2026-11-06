---
title: Components
description: Every component, with its include example, inputs and defaults.
---

# Components

Every GitLab CI component Preflight ships, with its include example, its inputs and their defaults, and the jobs and timeouts each template defines. Add one include to your app's `.gitlab-ci.yml`, then follow the per-component guide for setup. Like a real pre-flight check, the point is to find the fault on the ground, where it is cheap to fix.

> [!NOTE]
> Components are GA on the Free tier since GitLab 17.0. They work only within the same GitLab instance that hosts this project.

![Preflight's before-takeoff checklist card. 1 PROCTOR, checked; 2 PHP tests, 8.3, 8.4 and 8.5 pass; 3 Composer audit, no advisories; 4 SBOM, validated; 5 Pint, clean; 6 PHPStan, no errors; 7 ESLint and Prettier, clean; 8 clearance, cleared for takeoff. Beside it the annunciator panel lights a green lamp per check, with a11y, contract and freshness marked coming soon, and lists the seven checks, all in the 0.1.4 tag.](../readme/checklist.svg)

The checklist, item by item, with each item's job and timeout read from `templates/`:

| # | Item | Job | Timeout |
|---|------|-----|---------|
| 1 | PROCTOR | `proctor` | 30 minutes |
| 2 | PHP tests, 8.3, 8.4 and 8.5 | `php-test`, one job per version | 30 minutes |
| 3 | Composer audit | `composer-audit` | 30 minutes |
| 4 | SBOM | `sbom` | 30 minutes |
| 5 | Pint | `pint` | 10m |
| 6 | PHPStan | `phpstan` | 10m |
| 7 | ESLint and Prettier | `eslint` | 15m |

Every job the templates define is `interruptible: true`. Every component except `portability` takes a `job_name` input whose default is the job's usual name; set it when one project includes the same component more than once. `portability` keeps its two fixed job names, because `portability-run` waits on `portability-build`.

## proctor

Runs `vendor/bin/proctor check --format=codequality` and publishes the result as a GitLab Code Quality report. The job installs the app's dependencies with `composer install --no-plugins --no-scripts --ignore-platform-reqs`, so the app's plugins and scripts never run inside the job, and an app locked to an older PHP or needing an extension the image lacks still gets its report.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      proctor_command: vendor/bin/proctor check --format=codequality
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `proctor` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `php:8.4-cli-trixie@sha256:9cf851bc2c1b37c3e59dfd677a3c3e56d485af5a47c93f629424bb039eafcb69` | Docker image for the job. |
| `composer_version` | string | `2.10.3` | Composer version to install. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline. |
| `proctor_command` | string | `vendor/bin/proctor check --format=codequality` | The proctor command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |

From `templates/proctor/template.yml`: the single job (named by `job_name`) runs in the `test` stage by default, is `interruptible: true`, and has a timeout of 30 minutes. It installs Composer with the official getcomposer.org installer, verifies the installer's SHA-384 against composer.github.io/installer.sig, and pins the installed version to `composer_version`. It then runs `composer install --no-interaction --no-progress --no-plugins --no-scripts --ignore-platform-reqs`, so the app's plugins and scripts never run with the job's access and the app's PHP version and extensions are not required. The command's output goes through a plain redirect (not `tee`) to `gl-code-quality-report.json` at the project root, which keeps PROCTOR's exit code as the job result and gives the artifact the same path for every `working_dir`, including `.`. The report is published as a Code Quality report with `when: always`.

## php-test

Runs the test command on each supported PHP version through `parallel:matrix`.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      test_command: vendor/bin/phpunit
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the jobs. |
| `job_name` | string | `php-test` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `php:${PHP_VERSION}-cli-trixie` | Docker image for the jobs. The default carries the literal `${PHP_VERSION}`, which GitLab expands in the image at job time. |
| `php_versions` | array | `["8.3", "8.4", "8.5"]` | PHP versions to test against. |
| `composer_version` | string | `2.10.3` | Composer version to install. |
| `test_command` | string | `vendor/bin/phpunit` | The test command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |

From `templates/php-test/template.yml`: one job is created per entry in `php_versions` through `parallel:matrix`; `PHP_VERSION` becomes a CI/CD variable in each job, which the image input's default expands, and each job runs the newest patch release of its version. The default image is deliberately tag-pinned (the template points at the README section Updating image pins). Each job installs Composer the same way as proctor, runs `composer install --no-interaction --no-progress`, and then the test command. The jobs are `interruptible: true` with a timeout of 30 minutes.

### Caching

The jobs always cache Composer downloads in `.composer-cache/` so repeat runs do not re-download every package. The cache key depends on `composer.lock` and is prefixed with the PHP version, so a dependency change invalidates the cache and each PHP version gets its own cache. The template sets `COMPOSER_CACHE_DIR` to `$CI_PROJECT_DIR/.composer-cache`, keys the cache on `composer.lock` with the prefix `php-${PHP_VERSION}`, caches the path `.composer-cache/`, and uses the policy `pull-push`.

### Try the next PHP release without breaking the pipeline

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

## composer-audit

Runs `composer audit --locked` and fails on advisories.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      working_dir: .
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `composer-audit` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. |
| `working_dir` | string | `.` | Directory to run composer audit in, relative to the project root. |
| `abandoned` | string | `fail` | How composer audit treats abandoned packages: fail (default), report (list them, do not fail) or ignore. |

From `templates/composer-audit/template.yml`: the `composer:2` image already ships Composer, so there is no install step. The job runs `composer audit --locked` with `--abandoned` set to the `abandoned` input (`fail` by default, `report` or `ignore` to relax the abandoned check), which exits non-zero when it finds advisories, and fails the job. There is no `allow_failure` input: advisories must fail. The job is `interruptible: true` with a timeout of 30 minutes.

### Run it on a schedule

New advisories are published after code is merged, so a green pipeline today can be stale tomorrow. Create a weekly pipeline schedule on the default branch: project settings, Build, Pipeline schedules. The component needs nothing extra; it carries no `rules:` block, so it runs in scheduled pipelines like any other. Creating the schedule is a project setting, not a file in the app's repo, and someone with Maintainer rights on the app must do it. It is the one preflight check that books its own flight time.

## sbom

Generates a CycloneDX SBOM with `cyclonedx/cyclonedx-php-composer`, validates it, and publishes it as an artifact. The plugin is installed globally, so the app's `composer.json` is never touched.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      output: sbom.cdx.json
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `sbom` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. |
| `omit_dev` | boolean | `true` | Whether to omit dev dependencies from the SBOM. |
| `output` | string | `sbom.cdx.json` | Path of the SBOM file to publish, relative to the project root. |

From `templates/sbom/template.yml`: the job runs `composer install --no-interaction --no-progress --prefer-dist --no-scripts --ignore-platform-reqs` (the app's scripts never run, and its PHP version and extensions are not required), allows the plugin globally with `composer global config --no-plugins allow-plugins.cyclonedx/cyclonedx-php-composer true`, installs `cyclonedx/cyclonedx-php-composer:^6.2` globally, and then runs `composer CycloneDX:make-sbom --output-format=JSON --output-reproducible --validate` with `--omit=dev` added while `omit_dev` is true, writing to the `output` path. The `--validate` flag fails the job on an invalid SBOM. The SBOM file is published as an artifact with `expire_in: 30 days`. The job is `interruptible: true` with a timeout of 30 minutes.

## pint

Version 1 · Category: Testing/Validation · Tags: php,style,pint

Runs the app's own [Laravel Pint](https://laravel.com/docs/12.x/pint) in test mode and fails the pipeline on style errors. The app must require `laravel/pint` as a dev dependency and ship a `pint.json` (or point `config` at its own file).

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      config: pint.json
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `pint` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. |
| `config` | string | `pint.json` | Path to the app's Pint config file. |
| `working_dir` | string | `.` | Directory to run Pint in, relative to the project root. |

From `templates/pint/template.yml`: the component does not install Pint itself; it runs `composer install --no-interaction --no-progress --prefer-dist` and then the app's own Pint in test mode against the `config` file. The job is `interruptible: true` with a timeout of 10m.

## phpstan

Version 1 · Category: Testing/Validation · Tags: php,static-analysis,phpstan

Runs the app's own [PHPStan](https://phpstan.org/) and fails the pipeline on static analysis errors, writing a GitLab Code Quality report. The app must require `phpstan/phpstan` as a dev dependency and ship a `phpstan.neon` (or point `config` at its own file).

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      config: phpstan.neon
      memory_limit: 1G
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `phpstan` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. |
| `config` | string | `phpstan.neon` | Path to the app's PHPStan config file. |
| `memory_limit` | string | `1G` | Memory limit passed to PHPStan. |
| `working_dir` | string | `.` | Directory to run PHPStan in, relative to the project root. |

From `templates/phpstan/template.yml`: the component does not install PHPStan itself; it runs `composer install --no-interaction --no-progress --prefer-dist` and then the app's own PHPStan with `--no-progress --error-format=gitlab`, the `memory_limit` value and the `config` file, redirecting the output to `$CI_PROJECT_DIR/phpstan-report.json`. The report is published as a Code Quality report with `when: always`. The job is `interruptible: true` with a timeout of 10m.

## eslint

Version 1 · Category: Testing/Validation · Tags: javascript,style,eslint,prettier

Runs the app's own [ESLint](https://eslint.org/) (and [Prettier](https://prettier.io/)) and fails the pipeline on lint or format errors. The app must require `@waynestate/pinstripe`, `eslint` and `prettier` as dev dependencies and ship an `eslint.config.js` (or point `eslint_args` at its own files).

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      eslint_args: .
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `eslint` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da` | Docker image for the job. |
| `working_dir` | string | `.` | Directory to run the commands in, relative to the project root. |
| `eslint_args` | string | `.` | Arguments passed to eslint. |
| `prettier` | boolean | `true` | Whether to also run `prettier --check`. |

From `templates/eslint/template.yml`: the component does not install ESLint or Prettier itself; it runs `npm ci --ignore-scripts --cache .npm-cache` (the cache is keyed on `package-lock.json` and stores `.npm-cache/`), then `npx --no-install eslint` with the `eslint_args` value, and, while `prettier` is true, `npx --no-install prettier --check .`. The job is `interruptible: true` with a timeout of 15m.

## package-publish

Version 1 · Category: Release/Publishing · Tags: composer,publish,release

Publishes a semantic version tag to the GitLab group's built-in Composer registry. The job runs only on tags, reads the registry first, and refuses a moved version: a version already published from this commit passes quietly, and a version published from a different commit fails the pipeline, because GitLab would otherwise overwrite it without a word. The default image ships curl and PHP, which the job uses for the registry round trip.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/package-publish@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      group_id: "<your group id>"
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `deploy` | Pipeline stage for the job. |
| `job_name` | string | `package-publish` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. The default ships curl and PHP, which the job uses for the registry round trip. |
| `group_id` | string | none | Numeric id of the GitLab group whose built-in Composer registry hosts the package. Required. |
| `read_token_variable` | string | `PACKAGE_READ_TOKEN` | Name of the masked CI variable holding a token with the `read_package_registry` scope, used to read the registry before publishing. |

> [!WARNING]
> Protect your release tags.

From `templates/package-publish/template.yml`: the job runs only when `$CI_COMMIT_TAG` is set. The tag must be a semantic version, `1.2.3` or `v1.2.3` with an optional pre-release, or the job fails. The package name comes from `composer.json`, the file the registry serves. The job reads the masked CI variable named by `read_token_variable`, checks that `group_id` is numeric, reads the group's Composer registry index with the token, and follows the package metadata to the version already on the manifest. A version already published at this commit passes quietly (exit 0); a version published at a different commit fails (exit 1). Publishing posts the tag to the project's Composer packages endpoint with the job token. The job is `interruptible: true` with a timeout of 30 minutes.

## renovate

Runs [Renovate](https://docs.renovatebot.com/) as a scheduled or manual job that bumps image digests, GitHub action SHAs and package versions across the group's repositories, and merges the green ones itself. Bumps of `component:` include pins are covered by the preset and wait for review. Majors open a merge request and wait for a person. See [Renovate](../guides/renovate.md) for what auto-merges and what waits.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/renovate@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      git_author: "Preflight Bot <preflight-bot@example.com>"
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `job_name` | string | `renovate` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `renovate/renovate:44.192.2@sha256:37960a62ba1faa9079a7c4eead9b3f4470748a64ecd207e06c09fd8858673e17` | Docker image for the job. |
| `autodiscover_filter` | string | `$CI_PROJECT_NAMESPACE/*` | Glob limiting which projects Renovate discovers, relative to the runner project's namespace. |
| `dry_run` | string | `"null"` | Dry run mode: `null` (disabled), `lookup` or `full`. |
| `git_author` | string | none | Author of the commits and merge requests Renovate creates, in the form `Name <email>`. Required. |

From `templates/renovate/template.yml`: the job has no `stage` input and sets no stage. It runs only on scheduled and manual pipelines (`$CI_PIPELINE_SOURCE == "schedule"` or `"web"`). It writes its `config.js` at job time, so the `registryAliases` entry for the GitLab instance comes from the predefined `CI_SERVER_FQDN` variable; no hostname is stored in the repository, so the public mirror stays clean. It does not set `RENOVATE_TOKEN` or `GITHUB_COM_TOKEN` in the job `variables:` on purpose: a self-reference such as `X: $X` arrives as literal text on GitLab 19.5 and would shadow the masked project CI/CD variables, so the job reads both tokens straight from the project. The job is `interruptible: true` with a timeout of 1 hour.

## portability

Proves the app image meets the twelve-factor boot contract. It builds the image with Buildah (no Docker daemon, no elevated runner), boots it the strict way, and validates it with goss: the health path answers 200 for a foreign Host, the root filesystem and the app root are not writable, the app runs as the declared uid, and each declared writable path is writable. No takeoff without a clean pre-flight.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/portability@<full-commit-sha> # <tag, once one ships>
    inputs:
      dockerfile: Dockerfile
      context: .
      start_command: php -S 0.0.0.0:8080 -t public
```

Portability ships in 0.1.4 and later (0.1.3 does not include it), so pin the `0.1.4` tag, or the full commit SHA of a commit at or after it. The build job needs a runner that permits user namespaces (Buildah uses unshare for its storage); the run job needs only the project's container registry and an app image that carries curl, sha256sum and tar.

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the portability jobs. |
| `image` | string | `$CI_REGISTRY_IMAGE/portability:$CI_COMMIT_SHORT_SHA` | App image the portability-run job starts and validates. The default is what portability-build pushes; GitLab expands the CI variables at job time. |
| `buildah_image` | string | `quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb` | Buildah image for the portability-build job; it builds and pushes the app image. |
| `dockerfile` | string | `Dockerfile` | Dockerfile to build, relative to the context. |
| `context` | string | `.` | Build context, relative to the project root. |
| `app_root` | string | `/app` | Directory inside the image where the app lives. |
| `writable_paths` | array | `["storage", "bootstrap/cache"]` | Paths the app may write to, relative to app_root. Each must be writable by the app user. |
| `port` | number | `8080` | Port the app listens on inside the container. |
| `health_path` | string | `/up` | Path the app must answer 200 on for any Host. |
| `uid` | number | `100123` | Numeric uid the app runs as. The gid is always 0. |
| `start_command` | string | none | Command that starts the app inside the image. It is app-specific, so it is required and has no default. |
| `boot_timeout` | number | `60` | Seconds goss retries the health check while the app boots. |

The default is an immutable tag (`-immutable`) pinned by digest, because the plain version tag can be re-pushed and its old digest removed.

From `templates/portability/template.yml`: the component defines two jobs with fixed names. `portability-build` runs in the `buildah_image`, sets `STORAGE_DRIVER: vfs` (the vfs driver needs no special kernel support and runs in an ordinary container), builds the image with `buildah bud`, logs in to the project's container registry, and pushes `$CI_REGISTRY_IMAGE/portability:$CI_COMMIT_SHORT_SHA`. `portability-run` needs `portability-build`, generates a goss file from the inputs (the goss template is inlined in the job, because a component only ships its `template.yml` to the including project), downloads goss pinned by version and checksum, starts the app with `start_command`, and runs `goss validate` with `--retry-timeout` set to `boot_timeout` seconds. goss runs as the app user (the declared uid, gid 0), so its command checks see the same permissions the app has. Both jobs are `interruptible: true` with a timeout of 30 minutes.

## Related

- [The proctor component](../guides/component-proctor.md)
- [The php-test component](../guides/component-php-test.md)
- [The composer-audit component](../guides/component-composer-audit.md)
- [The sbom component](../guides/component-sbom.md)
- [The pint component](../guides/component-pint.md)
- [The phpstan component](../guides/component-phpstan.md)
- [The eslint component](../guides/component-eslint.md)
- [The package-publish component](../guides/component-package-publish.md)
- [The renovate component](../guides/component-renovate.md)
- [The portability component](../guides/component-portability.md)
- [Shared conventions](conventions.md)
- [Local checks](local-checks.md)
- [Troubleshooting](../troubleshooting.md)
