<div align="center">
  <a href="site/index.html"><img src="docs/readme/hero.jpg" width="100%" alt="Preflight's front page: the headline Preflight, 'Every push is cleared for takeoff.', the include block for the php-test component, and the runway mark set in a heading-indicator instrument."></a>
</div>

# Preflight

<div align="center">
  <img src="docs/readme/badges/php.svg" alt="php ^8.3">
  <img src="docs/readme/badges/license.svg" alt="license MIT">
  <img src="docs/readme/badges/components.svg" alt="gitlab ci components: 9">
</div>

**Every push is cleared for takeoff.**

Preflight is a set of GitLab CI/CD components that give every WSU app the
same checks: PROCTOR, PHP tests on each supported version, Composer audit,
an SBOM, Pint, PHPStan, ESLint, secret detection and an accessibility gate.

**Not to be confused with:** Preflight is the CI pipeline; it runs Pinstripe's style checks and PROCTOR but sets neither.

Front page: [`site/index.html`](site/index.html), a static page; see [`site/README.md`](site/README.md).
On Citadel it is served by the raw-PHP deploy layer in [`deploy/`](deploy/): a Squire kit whose front controller serves `site/` behind HELMET's security headers. For local development, keep serving `site/` directly.
Documentation: the full manual lives at [preflight.apps.wayne.edu/docs/](https://preflight.apps.wayne.edu/docs/).

## Where the code lives

The canonical repository is on nougat: [enterprise-apps/preflight](https://nougat.snu.gs/enterprise-apps/preflight). git.wayne.edu and GitHub ([waynestate/preflight](https://github.com/waynestate/preflight)) are read-only mirrors of it.
Open issues and merge requests on nougat, not on the mirrors.
This moves to git.wayne.edu once it has CI runners. Cleared for takeoff from nougat; the mirrors are just other gates.

<details>
<summary><b>Walk round the aircraft</b>: the placards, the flight plan and the flight manual from the front page</summary>
<br>
<div align="center"><img src="docs/readme/gallery.jpg" width="100%" alt="Three crops of the front page on a phone: the cockpit placards ('Seven components, one include each', with the proctor placard), the flight plan ('File a flight plan', the workflow rules and include block), and the flight manual ('Read before flight', a warning that a component is not a lock and a caution that it works on the same instance only)."></div>
</details>

Components are GA on the Free tier since GitLab 17.0. They work only within
the same GitLab instance that hosts this project.

## Components

<div align="center">
  <img src="docs/readme/checklist.svg" width="100%" alt="Preflight's before-takeoff checklist card. 1 PROCTOR, checked; 2 PHP tests, 8.3, 8.4 and 8.5 pass; 3 Composer audit, no advisories; 4 SBOM, validated; 5 Pint, clean; 6 PHPStan, no errors; 7 ESLint and Prettier, clean; 8 clearance, cleared for takeoff. Beside it the annunciator panel lights a green lamp per check, with a11y, contract and freshness marked coming soon, and lists the seven checks, all in the 0.1.4 tag.">
</div>

<div align="center"><sub>The checklist, item by item, with each item's job and timeout read from <code>templates/</code>.</sub></div>

### proctor

Runs `vendor/bin/proctor check --format=codequality` and publishes the
result as a GitLab Code Quality report. The job installs the app's
dependencies with `composer install --no-plugins --no-scripts --ignore-platform-reqs`, so the
app's plugins and scripts never run inside the job, and an app locked to an
older PHP or needing an extension the image lacks still gets its report.

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

### php-test

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

#### Caching

The jobs always cache Composer downloads in `.composer-cache/` so repeat runs
do not re-download every package. The cache key depends on `composer.lock`
and is prefixed with the PHP version, so a dependency change invalidates the
cache and each PHP version gets its own cache.

#### Try the next PHP release without breaking the pipeline

Include `php-test` a second time for the release that is not supported yet, name that job, and let it fail. The name
is what lets your own `.gitlab-ci.yml` loosen only that job:

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

A red `php-test-next` job is an early warning, not a stop. Drop the `allow_failure` and move the version into the main
`php_versions` list once the release is supported (the supported versions follow `policy.json`).

### composer-audit

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

#### Run it on a schedule

New advisories are published after code is merged, so a green pipeline today
can be stale tomorrow. Create a weekly pipeline schedule on the default
branch: project settings, Build, Pipeline schedules. The component needs
nothing extra; it carries no `rules:` block, so it runs in scheduled
pipelines like any other. Creating the schedule is a project setting, not a
file in the app's repo, and someone with Maintainer rights on the app must
do it. It is the one preflight check that books its own flight time.

### sbom

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
| `output` | string | `sbom.cdx.json` | Path of the SBOM file to publish, relative to the project root. It must be a relative path; GitLab refuses the pipeline at creation if it is not. |

### pint

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
| `config` | string | `pint.json` | Path to the app's Pint config file. It must be a relative path; GitLab refuses the pipeline at creation if it is not. |
| `working_dir` | string | `.` | Directory to run Pint in, relative to the project root. |

### phpstan

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
| `config` | string | `phpstan.neon` | Path to the app's PHPStan config file. It must be a relative path; GitLab refuses the pipeline at creation if it is not. |
| `memory_limit` | string | `1G` | Memory limit passed to PHPStan. A PHP size such as `1G`, `512M` or `-1`; GitLab refuses the pipeline at creation if it is not. |
| `working_dir` | string | `.` | Directory to run PHPStan in, relative to the project root. |

### eslint

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

### secret-detection

Version 1 · Category: Security/Secrets · Tags: security,secrets,gitleaks

Runs [Gitleaks](https://github.com/gitleaks/gitleaks) over the checked-out tree and fails the pipeline when a rule matches, with every match redacted in the job log and the `gitleaks.json` report artifact. By default it runs the built-in rules plus a path allowlist for `vendor/` and `node_modules/`, which a CI cache can restore into the checkout; point `config_path` at your own `.gitleaks.toml` to replace the default, and add the same `vendor` and `node_modules` path allowlist to your file. Allowlist a false positive in a `.gitleaksignore` at the project root.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/secret-detection@<full commit SHA> # 0.2.0
```

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `secret-detection` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f` | Docker image for the job. |
| `config_path` | string | (empty) | Path to a `.gitleaks.toml` config file, relative to the project root. Empty uses the built-in rules plus a path allowlist for `vendor/` and `node_modules/`. When set, your file replaces the default, so add the same `vendor` and `node_modules` path allowlist to it. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline. |

### package-publish

Version 1 · Category: Release/Publishing · Tags: composer,publish,release

Publishes a semantic version tag to the GitLab group's built-in Composer
registry. The job runs only on tags, reads the registry first, and refuses a
moved version: a version already published from this commit passes quietly,
and a version published from a different commit fails the pipeline, because
GitLab would otherwise overwrite it without a word. The default image ships
curl and PHP, which the job uses for the registry round trip.

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

Protect your release tags.

### renovate

Runs [Renovate](https://docs.renovatebot.com/) as a scheduled or manual job
that bumps image digests, GitHub action SHAs and package versions across the
group's repositories, and merges the green ones itself. Bumps of `component:`
include pins are covered by the preset and wait for review. Majors open a
merge request and wait for a person. See [Renovate](#renovate) for what
auto-merges and what waits.

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

### portability

Proves the app image meets the twelve-factor boot contract. It builds the
image with Buildah (no Docker daemon, no elevated runner), boots it the
strict way, and validates it with goss: the health path answers 200 for a
foreign Host, the root filesystem and the app root are not writable, the app
runs as the declared uid, and each declared writable path is writable. No
takeoff without a clean pre-flight.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/portability@<full-commit-sha> # <tag, once one ships>
    inputs:
      dockerfile: Dockerfile
      context: .
      start_command: php -S 0.0.0.0:8080 -t public
```

Portability ships in 0.1.4 and later (0.1.3 does not include it), so pin the
`0.1.4` tag, or the full commit SHA of a commit at or after it. The build job needs a runner that permits
user namespaces (Buildah uses unshare for its storage); the run job needs only
the project's container registry and an app image that carries curl, sha256sum
and tar.

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

### a11y

Version 1 · Category: Testing/Validation · Tags: accessibility,a11y,wcag,axe-core,playwright

Opens the app's pages in a real Chromium browser with [Playwright](https://playwright.dev/) and runs
[axe-core](https://github.com/dequelabs/axe-core) through `@axe-core/playwright`, in light and dark mode at 320 px and
1280 px, and fails the pipeline on any violation. The default tags are WCAG 2.1 Level AA, the level the ADA Title II
rule names; add `wcag22aa` for WCAG 2.2 AA, the floor WayneUI's gate and the stack's sites use. At 320 px it also checks
WCAG 1.4.10 Reflow, which axe-core cannot. It serves `site/` on a local port (or checks a running site at `base_url`),
and writes a JUnit report for the merge request's test summary and a JSON report with every finding. An automated
check finds only some failures: a green job is not proof of conformance, and the report counts what axe-core left for a
person to review. Every page gets a walk-round, in daylight and at night.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/a11y@<full commit SHA> # 0.2.0
    inputs:
      pages: ["index.html", "docs/**/*.html"]
      wcag_tags: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]
```

a11y ships in 0.2.0 (0.1.4 does not include it). While a site fixes its first findings, set
`allow_failure: true`; the reports are written either way.

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `a11y` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `mcr.microsoft.com/playwright:v1.65.0-noble@sha256:6e3fb709361521eb27161606e6da6d2674e5e89fa16516cb37d6fdd91372273d` | Playwright image the job runs in (amd64 and arm64). Its `vX.Y.Z` tag sets the playwright npm version. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline, for a site fixing its first findings. |
| `site_dir` | string | `site` | Static folder to serve, relative to the project root. Page globs expand in it. |
| `pages` | array | `["**/*.html"]` | Pages to check, relative to the site root: paths (`index.html`, `docs/`) or globs (`docs/**/*.html`). A glob must match at least one file. |
| `base_url` | string | `""` | Check a running site at this URL instead of serving `site_dir`, for example `$CI_ENVIRONMENT_URL`. |
| `wcag_tags` | array | `["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]` | axe-core tags to run. Add `wcag22aa` for WCAG 2.2 AA. |
| `color_schemes` | array | `["light", "dark"]` | Color schemes each page is checked in: `light`, `dark` or `no-preference`. |
| `widths` | array | `[320, 1280]` | Viewport widths in CSS pixels. At 320 or less the job also checks reflow. |
| `playwright_version` | string | `""` | playwright npm version. Empty reads it from the image tag. |
| `axe_core_version` | string | `4.14.0` | axe-core version, the rules engine. The job fails if a different axe-core ran. |
| `axe_playwright_version` | string | `4.14.0` | @axe-core/playwright version. Its axe-core range must include `axe_core_version`. |

The job installs the three npm packages at exact versions with `--ignore-scripts` into a temporary folder, never into
the app. The checker is `templates/a11y/check.mjs`, inlined in the template because a component ships only its
`template.yml`; `tests/check-a11y-inline` keeps the two byte for byte. Renovate bumps the image and the two axe-core
packages (as one group), and the bumps wait for review like every template pin.

## Same instance only

Components work only inside the GitLab instance that hosts this project.
Components cannot be used across instances except by mirroring.

## GitHub mirrors

Components work only inside one GitLab instance, so a package that is also
mirrored to `github.com/waynestate` cannot include them there. For those
mirrors, Preflight ships a reusable GitHub Actions workflow that runs the same
checks: the package's `composer ci` script on each supported PHP version, plus
a Composer audit.

Each package keeps its checks in a `ci` script in its `composer.json`; the
workflow just calls `composer ci`, so the mirror runs whatever the package
already runs on GitLab.

The workflow lives at `.github/workflows/php-package.yml` in this repo. A
mirrored package calls it from its own `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: ['**']
    tags: ['v*', '*.*.*']

jobs:
  ci:
    uses: waynestate/preflight/.github/workflows/php-package.yml@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
```

This workflow ships in the `0.1.1` tag, so pin the full commit SHA of the
release tag and keep the tag in a trailing comment. A tag or branch can move;
a SHA cannot. PROCTOR's `preflight-pinned` check warns when an include is not
pinned to a commit SHA. The Renovate preset (see the Renovate section)
proposes the bumps, and they wait for review (the `needs-review` label).

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `php-versions` | string (JSON array) | `'["8.3","8.4","8.5"]'` | PHP versions to test, lowest first. The audit job runs on the first entry. |
| `ci-command` | string | `composer ci` | The command to run in each PHP version job. |
| `working-directory` | string | `.` | Directory to run the command in, relative to the repository root. |

The workflow is committed to this repo (and so to GitLab) but only runs on the
GitHub mirror; GitLab ignores `.github/workflows`. A release tag is not done
until it is green on both sides. Two cockpits, one checklist.

## Renovate

Preflight owns the stack's version automation (ADR-0015): the shared preset
[`renovate/default.json`](renovate/default.json) and the
[`renovate` component](#renovate) that runs it. A private runner project
includes the component on a schedule; Renovate discovers every repository in
the filter, opens merge requests for outdated versions, and GitLab's native
auto-merge takes in the ones whose pipeline is green.

Every stack repository carries a `renovate.json` that extends the shared
preset, so the rules change in one place:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["local>enterprise-apps/preflight//renovate/default"]
}
```

### What auto-merges

Digest updates, pin and pinDigest updates, and patch and minor version bumps
auto-merge when the pipeline is green. Lock file maintenance runs weekly and
auto-merges the same way. Every merge request carries the `auto-deps` label.
The exception is Preflight's own pins: an update that touches the templates,
the contract or this repository's own pipeline, a bump of a component include
version, and a bump of the recorded Squire kit version, never auto-merge (see
What waits for review). One image gets a narrower rule: `quay.io/buildah/stable`
only ever matches `-immutable` tags, because Red Hat re-pushed a mutable tag
and garbage-collected the old digest, which broke an image job.

### What waits

Major version bumps never auto-merge. The merge request carries the `major`
label and waits for a person.

### What waits for review

Updates that change an image digest inside the templates, the contract, or
this repository's own pipeline, bumps of a Preflight component version in an
app's `component:` include, and bumps of the recorded Squire kit version
(labeled `squire-kit`) carry the `needs-review` label and never auto-merge.
They wait for a person because those pins are what every app pipeline runs:
a changed digest here changes what every consuming pipeline executes, so it
earns a human eye even when its own pipeline is green. The Squire kit version
bump is refreshed by a person who runs `squire update` (with the right path
for the repo), reviews the diff and commits it to the branch; the runner runs
no commands, so the merge request carries no postUpgradeTasks.

### Why MySQL and HA-Proxy get digests only

The `mysql` and `haproxy` images mirror the versions Citadel actually runs,
not the newest releases in the world. Bumping their tags would drift the apps
away from production, so only digest updates are enabled for them: the same
tag, the exact image. `citadel/php-apache` is disabled entirely, because
Squire's own data owns that image.

### Set up (the user does this)

This repository ships the preset and the component, and creates nothing else.
A person must set up:

- A private runner project that includes the `renovate` component on a
  schedule (see The runner project).
- The `RENOVATE_TOKEN` masked CI variable in that project, and optionally
  `GITHUB_COM_TOKEN`.
- A pipeline schedule on that project so the job runs regularly; weekly on
  Monday is a sensible default.

### The runner project

The runner project must stay private. It holds `RENOVATE_TOKEN`, a token that
can open and merge merge requests across the group, and this repository is
mirrored to public GitHub. Use a group bot account for the token, not a
person's: the bot outlives any one maintainer, and the commits keep one
stable author.

| Variable | Required | What it does |
|----------|----------|--------------|
| `RENOVATE_TOKEN` | yes | Masked CI variable in the runner project; the job reads it straight from the project, the component does not map it. A project access token with Developer, or Maintainer where only Maintainers may merge. |
| `GITHUB_COM_TOKEN` | no | Masked CI variable in the runner project; the job reads it straight from the project, the component does not map it. Lookups against github.com do not hit anonymous rate limits. |

Do not add `RENOVATE_TOKEN: $RENOVATE_TOKEN` to your own `variables:`; that self-reference arrives as literal text.

The component writes its `config.js` at job time, so the `registryAliases`
entry for the GitLab instance comes from the predefined `CI_SERVER_FQDN`
variable. No hostname is stored in this repository.

## Keep the job token allowlist short

An app that installs private packages from GitLab's package registry should
list only the projects it really needs in its CI/CD job token allowlist
(project settings, Settings, CI/CD, Job token permissions), use the
fine-grained permissions where they fit, and review the list when a
dependency is dropped. A leaked job token acts with the triggering user's
access. This is a project setting, not a file Preflight can create or check.

## When the components run

The components are ordinary jobs, so they run whenever the app's pipeline
runs. To run them on every merge request and on pushes to the default
branch, put a `workflow:rules` block in the app's own `.gitlab-ci.yml`:

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
```

The `workflow:rules` block must live in the app's own file. A component
cannot set the pipeline's `workflow:rules` for the project that includes it,
so the `merge_request_event` rule goes in the app's `.gitlab-ci.yml`.

## Which release ran

Every Preflight job prints a `Preflight component <name> <version> (ref <reference>, sha <sha>)` line before any other command, so when a job misbehaves, its log says which Preflight release produced it. The line needs GitLab 18.7 or later, where `spec: component:` is generally available; an include pinned by commit SHA shows that SHA in the line.

## What the components cannot force

An included component is a set of ordinary jobs. The app's own `.gitlab-ci.yml` is merged over them, so an app can
override a job's keys, skip it with `rules`, or delete the `include:` line. Preflight makes the safe pipeline the easy
one; it does not lock it. Rollcall is where skipped or weakened gates will show up. A preflight checklist only works
if the pilot reads it.

### Which jobs may be allowed to fail

Three components take an `allow_failure` input, all defaulting to `false`: `proctor`, `secret-detection` and `a11y`. A
policy finding is a warning while an app adopts PROCTOR's rules, a secret finding while a repo allowlists its first false
positives, and an accessibility finding while a site fixes what the gate found on its first run, so each job may fail
without failing the pipeline during adoption; all three still write their reports. `composer-audit` has no such input on purpose: a known advisory must fail the pipeline. The other jobs have no
`allow_failure` input either.

No template adds a global key such as `default:`, `variables:`, `workflow:` or `stages:`. `tests/check-contract.sh`
(and its `.ps1` twin) fails on any top-level key in a template that is not a job named in `contract/inputs.json`, so a
global key fails `composer ci`.

### Protection checklist

A pilot signs each line of the checklist; the plane does not sign for you. Five project settings make the gates
harder to skip, and every one of them works on GitLab Community Edition:

- [ ] **Protect the default branch** and require a merge request to change it. Every change to `.gitlab-ci.yml` then
  gets a reviewer. (Code owner approval needs Premium, so on Community Edition the reviewer is whoever merges.)
- [ ] **Protect the release tags.** Protect `*` or the release tag pattern so only maintainers can create or move a
  tag. A component ref is a tag, so whoever can move it controls every pipeline that pins it.
- [ ] **Set merge request approvals to at least one** for changes to the default branch. Approvals are available on
  every tier, but code owner rules within them need Premium, so on Community Edition the approval rests with whoever
  has merge rights: rely on the merger as the reviewer.
- [ ] **Set "Minimum role to use pipeline variables" to `no_one_allowed`** unless the project needs pipeline variables.
  The components take inputs, which are fixed and type checked for the whole run. Self-managed GitLab defaults this
  setting to `maintainer`.
- [ ] **Keep secrets away from fork merge requests.** A fork's merge request pipeline runs the fork's configuration.
  Review a fork's `.gitlab-ci.yml` before running its pipeline, and never give it protected variables.

These are project settings Preflight cannot create or check, and a read-only token drift report was considered and
left out on purpose: it would trade a token for a warning, and the checklist costs nothing to keep.


## Strongly recommended: a git.wayne.edu instance runner.

Until git.wayne.edu has a runner, CI runs on the GitLab instance that has one, and Preflight and each
app must live on or be mirrored to it. A git.wayne.edu instance runner is strongly recommended. Ask
for a non-privileged Docker executor (no privileged mode, no Docker socket mount), a fresh ephemeral
environment for every job, and no shell executor shared between projects; capacity and maintenance
stay with ops. A job that needs the host's Docker socket to take off has skipped its own preflight.

## Include a component twice

Every component except `portability` takes a `job_name` input, whose default is the job's usual name. Set it when one
project includes the same component more than once, for example in a monorepo with two apps; without it the two jobs
would share a name and merge into one.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@<full commit SHA> # <tag>
    inputs:
      working_dir: app
      job_name: pint-app
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@<full commit SHA> # <tag>
    inputs:
      working_dir: admin
      job_name: pint-admin
```

`job_name` ships in 0.1.4, so pin 0.1.4 or a SHA at or after that release. `portability` keeps its two fixed
job names, because `portability-run` waits on `portability-build`.

## Shared conventions

- Composer vendor: `waynestate/`
- License: MIT
- PHP floor: `^8.3`
- JavaScript components install with `npm ci --ignore-scripts`. The job carries no token beyond `CI_JOB_TOKEN` (BEST_PRACTICES.md 4.12).
- Path-like inputs (`config` on phpstan and pint, `output` on sbom) must be relative paths, and `memory_limit` (phpstan) takes a PHP size such as `1G`, `512M` or `-1`. Each carries an input `regex`, so GitLab refuses the pipeline at creation when a value does not match.

## Updating image pins

Every image the components run is pinned by digest (`name:tag@sha256:...`),
so a repointed tag cannot quietly change what a pipeline executes. The tag
stays in front of the digest so a diff still reads like a version bump.

The php-test matrix is the one exception. Its PHP images are tag-pinned on
purpose, so those jobs run on the newest PHP patch release; every other
component image is digest-pinned.

To look up the digest for an image:

```sh
docker buildx imagetools inspect <image>:<tag>
```

Use the top-level `Digest:` line (the multi-arch index digest), not a
per-platform one. Without `buildx`, `docker manifest inspect -v <image>:<tag>`
shows the same index digest.

Pins change only through a reviewed merge request.

## Template lint

`composer ci` runs `bin/lint-templates` before the fixture tests. The lint scans
`templates/**/*.yml` and `.github/workflows/*.yml` for unsafe CI patterns:

- `privileged`: `privileged: true`
- `dind-service`: Docker-in-Docker services
- `docker-sock`: references to `docker.sock`
- `kaniko-image`: Kaniko images
- `unpinned-action`: GitHub `uses:` entries that are not pinned to a 40-character SHA
- `image-no-tag` and `image-latest`: image references with no tag or with `latest`
- `image-no-digest`: a warning for a tagged image that is not pinned by digest

The container-build rules (`privileged`, `dind-service`, `docker-sock` and `kaniko-image`) are explained in
BEST_PRACTICES.md 4.17.

Known warnings can be allowlisted in `lint-allow.yml`. Each entry needs `file`,
`rule` and `reason`; the reason is required so an allowlist entry is a reviewed
decision, not a silence. The preflight checklist checks the checklist.

## Proof

Proof runs against real Wayne State applications are on a private site, [proof.apps.wayne.edu/preflight](https://proof.apps.wayne.edu/preflight/), behind a Wayne State employee sign-in. What was run on 82 apps on 2026-11-05, what held and what it caught in Preflight itself is on the public [Proof](https://preflight.apps.wayne.edu/docs/reference/proof.html) page.

## Docs

The full documentation lives at [preflight.apps.wayne.edu/docs/](https://preflight.apps.wayne.edu/docs/) on the project site, built from `docs/` by Squire's docs builder. It starts with the overview page; the rest of the manual follows as the pages are written.

- `composer docs` rebuilds `site/docs/` from `docs/`; run it after editing a page.
- `composer docs:check` fails when the built site is stale; `composer ci` runs it.

The pages are committed because the deploy server serves `site/` without building. Every page links back to its Markdown, and the footer stamps the version the docs describe. Cleared for takeoff: the flight manual flies with the aircraft.

The pages wear the front page's flight deck: `docs/_header.html` is the front page's top bar and `docs/theme/preflight.css` maps its palette and B612 type onto the docs kit, with a dark mode taken from the instrument panel. `docs/docs.json` names both under `theme`. Restyle the docs in those two files, never in `site/assets/docs.css` or `bin/docs-site.php`: those are Squire's bytes.

## Local checks

Maintainers: how to build, test and release this project, and where its data comes from, is in [MAINTAINING.md](MAINTAINING.md).

Run the template lint and the fixture tests with Docker:

```sh
docker run --rm -v "$(pwd):/app" -w /app composer:2 composer install
docker run --rm -v "$(pwd):/app" -w /app composer:2 composer ci
```

In PowerShell, use `${PWD}` instead of `$(pwd)`:

```powershell
docker run --rm -v "${PWD}:/app" -w /app composer:2 composer install
docker run --rm -v "${PWD}:/app" -w /app composer:2 composer ci
```

Run the PHP fixture app separately:

```sh
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app composer:2 composer install
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app php:8.4-cli vendor/bin/phpunit
```

Run the portability fixtures with Docker; they build and boot the three
fixtures under `tests/portability` the strict way and exit 0 only when `good`
passes and both `bad-*` fixtures fail:

```sh
sh tests/check-portability.sh
```

```powershell
pwsh -File tests/check-portability.ps1
```

The site's pages have an accessibility gate: the `a11y` component's own checker, run in Docker with the image and versions pinned in its template, so no host browser is needed and a local run checks the same way as the pipeline. `sh scripts/a11y.sh` on Linux and macOS, `scripts/a11y.ps1` in PowerShell on Windows. It checks the front page and every docs page at WCAG 2.2 AA in light and dark mode at 320 px and 1280 px, with the reflow check, and fails on any violation. `tests/check-a11y.sh` (and `.ps1`) prove the checker passes a clean fixture site and fails a known-bad one.

Run the must-fail fixtures with Docker; each proves its component (`php-test`, `phpstan`, `pint`) still fails a bad app and passes a clean one, running the component's own commands from its template in the component's own image. The `must-fail-php-test` and `must-fail-phpstan-pint` jobs run the same checks in CI, in the components' own images, so they need no Docker there. Locally, run them with Docker:

```sh
docker run --rm -v "$(pwd):/app" -w /app php:8.3-cli-trixie sh tests/check-php-test-fails.sh
docker run --rm -v "$(pwd):/app" -w /app composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc sh tests/check-phpstan-fails.sh
docker run --rm -v "$(pwd):/app" -w /app composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc sh tests/check-pint-fails.sh
```

```powershell
pwsh -File tests/check-php-test-fails.ps1
pwsh -File tests/check-phpstan-fails.ps1
pwsh -File tests/check-pint-fails.ps1
```

<details>
<summary><b>The brand board</b>: the runway mark, lockups, palette and type</summary>
<br>
<div align="center"><img src="docs/readme/board.jpg" width="100%" alt="Preflight's brand board: the runway mark on a green tile, the app icon, horizontal and stacked lockups, the mark on light and dark, the palette of Wayne State green, gold, cream and deep blue, Lato type, favicon sizes, clear space, do and don't, and a product usage example."></div>
</details>

## The cast

<div align="center">
  <a href="https://github.com/waynestate/wayne-ui" title="WayneUI"><img src="docs/readme/cast/wayneui.png" width="48" alt="WayneUI"></a>
  <a href="https://github.com/waynestate/creed" title="CREED"><img src="docs/readme/cast/creed.png" width="48" alt="CREED"></a>
  <a href="https://github.com/waynestate/proctor" title="PROCTOR"><img src="docs/readme/cast/proctor.png" width="48" alt="PROCTOR"></a>
  <a href="https://github.com/waynestate/sesame" title="SESAME"><img src="docs/readme/cast/sesame.png" width="48" alt="SESAME"></a>
  <a href="https://github.com/waynestate/helmet" title="HELMET"><img src="docs/readme/cast/helmet.png" width="48" alt="HELMET"></a>
  <a href="https://github.com/waynestate/sourdough" title="Sourdough"><img src="docs/readme/cast/sourdough.png" width="48" alt="Sourdough"></a>
  <a href="https://github.com/waynestate/squire" title="Squire"><img src="docs/readme/cast/squire.png" width="48" alt="Squire"></a>
  <a href="https://github.com/waynestate/preflight" title="Preflight"><img src="docs/readme/cast/preflight.png" width="48" alt="Preflight"></a>
  <a href="https://github.com/waynestate/pinstripe" title="Pinstripe"><img src="docs/readme/cast/pinstripe.png" width="48" alt="Pinstripe"></a>
  <a href="https://github.com/waynestate/booster" title="Booster"><img src="docs/readme/cast/booster.png" width="48" alt="Booster"></a>
  <a href="https://github.com/waynestate/rollcall" title="Rollcall"><img src="docs/readme/cast/rollcall.png" width="48" alt="Rollcall"></a>
  <a href="https://nougat.snu.gs/enterprise-apps/drawbridge" title="Drawbridge"><img src="docs/readme/cast/drawbridge.png" width="48" alt="Drawbridge"></a>
  <a href="https://github.com/waynestate/advisor" title="ADVISOR"><img src="docs/readme/cast/advisor.png" width="48" alt="ADVISOR"></a>
  <a href="https://github.com/waynestate/weld" title="WELD"><img src="docs/readme/cast/weld.png" width="48" alt="WELD"></a>
</div>

<div align="center"><sub>Fourteen on the manifest, every one checked in. The README art is cut from the front page by
<a href="scripts/readme-art/README.md"><code>scripts/readme-art</code></a>; no runways were painted in its making.</sub></div>
