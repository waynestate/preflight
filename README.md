# PREFLIGHT

PREFLIGHT is a set of GitLab CI/CD components that give every WSU app the
same checks: PROCTOR, PHP tests on each supported version, and Composer
audit.

Components are GA on the Free tier since GitLab 17.0. They work only within
the same GitLab instance that hosts this project.

## Components

### proctor

Runs `vendor/bin/proctor check --format=codequality` and publishes the
result as a GitLab Code Quality report.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@0.1.0
    inputs:
      proctor_command: vendor/bin/proctor check --format=codequality
```

`@0.1.0` is the first tag and is not cut yet. Until it is, pin a full commit SHA instead.

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `image` | string | `php:8.4-cli@sha256:debadc2e36b857657846e2e952cbaf52702e55482dd3c2c43806f68d8c534a70` | Docker image for the job. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline. |
| `proctor_command` | string | `vendor/bin/proctor check --format=codequality` | The proctor command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |

### php-test

Runs the test command on each supported PHP version through `parallel:matrix`.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@0.1.0
    inputs:
      php_versions: ["8.2", "8.3", "8.4", "8.5"]
      test_command: vendor/bin/phpunit
```

`@0.1.0` is the first tag and is not cut yet. Until it is, pin a full commit SHA instead.

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the jobs. |
| `php_versions` | array | full image references, one per PHP version (see below) | PHP image references (tag plus digest) to test against, one job per entry. |
| `test_command` | string | `vendor/bin/phpunit` | The test command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |

The default `php_versions` is:

```yaml
- php:8.2-cli@sha256:f7c6b9fc4b410e6fa01160cf72b1c19bce7d5e35fd065c9290fceb15097a480b
- php:8.3-cli@sha256:98d555ff97b3865140ad31032508c3ca089fa97a8944b14ca9dc03ea05d788cd
- php:8.4-cli@sha256:debadc2e36b857657846e2e952cbaf52702e55482dd3c2c43806f68d8c534a70
- php:8.5-cli@sha256:635a4b998025ab269194639a5549c6fdcd9b4f88ec8cd761b092de8653d40663
```

### composer-audit

Runs `composer audit --locked` and fails on advisories.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@0.1.0
    inputs:
      working_dir: .
```

`@0.1.0` is the first tag and is not cut yet. Until it is, pin a full commit SHA instead.

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `image` | string | `composer:2@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. |
| `working_dir` | string | `.` | Directory to run composer audit in, relative to the project root. |

## Same instance only

Components work only inside the GitLab instance that hosts this project.
Components cannot be used across instances except by mirroring.

## Strongly recommended: a git.wayne.edu instance runner.

Until git.wayne.edu has a runner, CI runs on GitLab, and PREFLIGHT and each
app must live on or be mirrored to GitLab. See
`design/instance-runner-case.md` in the stack coordination repo.

## Shared conventions

- Composer vendor: `waynestate/`
- Licence: MIT
- PHP floor: `^8.2`

## Updating image pins

Every image the components run is pinned by digest (`name:tag@sha256:...`),
so a repointed tag cannot quietly change what a pipeline executes. The tag
stays in front of the digest so a diff still reads like a version bump.

To look up the digest for an image:

```sh
docker buildx imagetools inspect <image>:<tag>
```

Use the top-level `Digest:` line (the multi-arch index digest), not a
per-platform one. Without `buildx`, `docker manifest inspect -v <image>:<tag>`
shows the same index digest.

Pins change only through a reviewed merge request.

## Local checks

Run the fixture tests with Docker:

```sh
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app composer:2 composer install
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app php:8.4-cli vendor/bin/phpunit
```
