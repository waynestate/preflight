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
  - component: $CI_SERVER_FQDN/$CI_PROJECT_PATH/proctor@1.0.0
    inputs:
      proctor_command: vendor/bin/proctor check --format=codequality
```

`@1.0.0` is the first tag and is not yet cut.

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `image` | string | `php:8.4-cli` | Docker image for the job. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline. |
| `proctor_command` | string | `vendor/bin/proctor check --format=codequality` | The proctor command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |

### php-test

Runs the test command on each supported PHP version through `parallel:matrix`.

```yaml
include:
  - component: $CI_SERVER_FQDN/$CI_PROJECT_PATH/php-test@1.0.0
    inputs:
      php_versions: ["8.2", "8.3", "8.4", "8.5"]
      test_command: vendor/bin/phpunit
```

`@1.0.0` is the first tag and is not yet cut.

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the jobs. |
| `php_versions` | array | `["8.2", "8.3", "8.4", "8.5"]` | PHP versions to test against. |
| `test_command` | string | `vendor/bin/phpunit` | The test command to run. |
| `working_dir` | string | `.` | Directory to run the command in, relative to the project root. |

### composer-audit

Runs `composer audit --locked` and fails on advisories.

```yaml
include:
  - component: $CI_SERVER_FQDN/$CI_PROJECT_PATH/composer-audit@1.0.0
    inputs:
      working_dir: .
```

`@1.0.0` is the first tag and is not yet cut.

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `image` | string | `composer:2` | Docker image for the job. |
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

## Local checks

Run the fixture tests with Docker:

```sh
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app composer:2 composer install
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app php:8.4-cli vendor/bin/phpunit
```
