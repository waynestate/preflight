---
title: "Proof"
description: "Preflight's components run against 82 Wayne State applications on 2026-11-05: what ran, what held, what it caught in Preflight itself, what it does not prove, and how to run the same on your app."
---

# Proof

This page says how Preflight's components were proven on real Wayne State applications: what ran, what held, what the run caught in Preflight itself, and what it does not prove yet. Next, see [Components](components.md) for every input and [Troubleshooting](../troubleshooting.md) for the fixes the run added.

A preflight check is only worth something on the aircraft you are about to fly. So on 2026-11-05 every component that can run without a registry or a token was flown against every PHP application in the stack's shared proof corpus, the same set PROCTOR and Squire are measured on.

## What ran

Preflight from `main` (0.1.4 plus the Unreleased changes), with the install-line change described below. The 82 applications are 64 raw PHP apps (33 with a `composer.json`, 31 without one), 17 Laravel apps from 5.8 to 13, and 1 Slim 2 app.

No GitLab pipeline ran. Instead, each component's `template.yml` was read, its default inputs applied, and its own `script:` lines written out as a shell script, exactly what a runner would execute. Each job then ran in the component's own default image, one container per job, on a throwaway copy of the app's default branch, checked out with Linux line endings, with `.env` files, `auth.json` and `config.files/` removed. Packagist, Debian and npm were reachable; every Wayne State host was mapped to `127.0.0.1`, and no job had a token or a Composer credential.

A job ran on an app when the app has what the component works on:

| Component | Runs when the app has | Apps |
|---|---|---|
| composer-audit | `composer.lock` | 51 |
| proctor | `composer.json` | 51 |
| sbom | `composer.json` | 51 |
| php-test (8.3, 8.4, 8.5) | `tests/` or `phpunit.xml` | 17 |
| pint | `laravel/pint` in require-dev | 9 |
| phpstan | PHPStan or Larastan in require-dev | 1 |
| eslint | `eslint` in `package.json` | 2 |

The proctor job ran the stack's PROCTOR in place of `vendor/bin/proctor`, because none of the apps requires PROCTOR yet; the rest of that job is the template's. portability, renovate and package-publish did not run: they need a registry, a token or a release tag.

A job **passes** when it exits 0. It is **flagged** when it reached its own check and that check reported findings, or when the app's own `composer install` or `npm ci` stopped, with the reason in the log. A **tool error** is Preflight breaking: a step the component owns failing, a timeout, or a report that is not valid.

## Results

| Component | Jobs | Pass | Flagged at its check | Stopped at the app's install | Tool error |
|---|---|---|---|---|---|
| composer-audit | 51 | 27 | 24 | 0 | 0 |
| proctor | 51 | 0 | 15 | 36 | 0 |
| sbom | 51 | 15 | 0 | 36 | 0 |
| php-test 8.3 | 17 | 0 | 1 | 16 | 0 |
| php-test 8.4 | 17 | 0 | 2 | 15 | 0 |
| php-test 8.5 | 17 | 0 | 1 | 16 | 0 |
| pint | 9 | 1 | 0 | 8 | 0 |
| phpstan | 1 | 1 | 0 | 0 | 0 |
| eslint | 2 | 0 | 1 | 1 | 0 |

- **No tool errors** in 216 jobs. Every PROCTOR report was valid Code Quality JSON, and every SBOM passed CycloneDX's own validation.
- composer-audit read every lock, including the oldest, in about a second.
- An app's install stopped for one of these reasons (an app can meet more than one): a package installed straight from a private Git repository on the app's own GitLab instance (35 apps), a lock built for another PHP (15), an extension the default image lacks (oci8 7, gd 4, ldap 1), a package from Subversion (1), and only a `yarn.lock` for `npm ci` (1). Each job stopped at that step with Composer's or npm's own message.
- Where php-test reached the tests, the failures were the apps' own setups: a test suite that needs built front-end assets, and one that needs a database.
- The median job took 1 to 7 seconds; most of that is installing.

## What it caught in Preflight

A run that only finds praise was not looking hard enough. This one found these, and every finding is about Preflight, not the apps:

- **Fixed: proctor and sbom asked for the app's PHP.** Both jobs only read the app, yet their `composer install` refused a lock built for PHP 7 or one that needs gd or oci8. So the proctor job could not report on the old apps PROCTOR exists to flag. Both now install with `--ignore-platform-reqs`. On the same apps, PROCTOR reports went from 13 to 15 and SBOMs from 12 to 15, and no app went from passing to failing; the other platform-blocked apps then met a private package, which only a credential fixes.
- **Fixed: the sbom job ran the app's Composer scripts.** Its install had no `--no-scripts`, so a Laravel app's `artisan package:discover` ran inside the job. Listing packages never needs them, and the job now skips them.
- **Documented: what stops an install.** [Troubleshooting](../troubleshooting.md) now covers a lock for another PHP or a missing extension (set the `image` input), a private package (give Composer a credential), and `npm ci` without a `package-lock.json`.
- **Open: an app without `composer.json` gets nothing.** 31 of the 82 apps have no `composer.json`, and every PHP component starts from one, PROCTOR's included. Committing a `composer.json` and a lock, which Squire's `init` now asks for, is the way in today.
- **Open: Yarn.** The eslint component installs with `npm ci` only.
- **Not Preflight:** the first pass failed `apt-get update` in two PHP images. The proof machine's local copies were stale; fresh pulls of the same tags worked, and the jobs were run again on them.

## What this does not prove

- No GitLab pipeline ran, so include resolution, `spec:` inputs, `rules`, caches, artifacts and the Code Quality widget were not exercised. The scripts are the templates' own lines with default inputs.
- No job had a credential, so the 35 apps that install a private package were measured only up to that point.
- portability, renovate and package-publish did not run.
- The per-app record names the applications and stays in the stack's internal notes.

## Run it on your app

Include the components in your app's `.gitlab-ci.yml` as the [Quick start](../guides/quick-start.md) shows, push a branch, and read each job's log. To try the PROCTOR job's steps on your machine first, from the app's root (the first line adds PROCTOR to require-dev, which the proctor component expects):

```sh tab="Linux / macOS"
docker run --rm -v "$(pwd):/app" -v stack-composer-cache:/tmp/cache -w /app composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 composer require --dev waynestate/proctor --no-scripts --ignore-platform-reqs
docker run --rm -v "$(pwd):/app" -v stack-composer-cache:/tmp/cache -w /app composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 composer install --no-plugins --no-scripts --ignore-platform-reqs
docker run --rm -v "$(pwd):/app" -v stack-composer-cache:/tmp/cache -w /app composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 vendor/bin/proctor check
```

```powershell tab="Windows"
docker run --rm -v "${PWD}:/app" -v stack-composer-cache:/tmp/cache -w /app composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 composer require --dev waynestate/proctor --no-scripts --ignore-platform-reqs
docker run --rm -v "${PWD}:/app" -v stack-composer-cache:/tmp/cache -w /app composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 composer install --no-plugins --no-scripts --ignore-platform-reqs
docker run --rm -v "${PWD}:/app" -v stack-composer-cache:/tmp/cache -w /app composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 vendor/bin/proctor check
```

The `stack-composer-cache` volume keeps Composer's downloads between runs; Docker creates it the first time.

## Related

- [Components](components.md)
- [Local checks](local-checks.md)
- [Troubleshooting](../troubleshooting.md)
