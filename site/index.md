---
title: "Preflight: Every push is cleared for takeoff."
description: "Preflight is the Wayne State app stack's CI: GitLab CI/CD components that run PROCTOR, PHP tests on each supported version, a Composer audit, an SBOM, Pint, PHPStan and ESLint on every push."
url: https://preflight.apps.wayne.edu/
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

Wayne State app stack · CI templates

# Preflight

Every push is cleared for takeoff.

pre·flight noun The checklist a pilot runs before takeoff. Every push runs this one before Citadel.

GitLab CI/CD components that every stack project and starter includes: PROCTOR, PHP tests on each supported version, a Composer audit, an SBOM, Pint, PHPStan and ESLint. One `include:` block, the same checks on every app.

.gitlab-ci.yml

```
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@0.1.1
```

Already included in [WELD](https://weld.apps.wayne.edu/) and in every [Sourdough](https://sourdough.apps.wayne.edu/) app. Use Preflight on its own to give a GitLab project you already have the stack's CI checks.

[Run the checklist](https://preflight.apps.wayne.edu/#checklist) [File a flight plan](https://preflight.apps.wayne.edu/#flight-plan)

![Preflight mark: a runway in perspective with a gold centreline](https://preflight.apps.wayne.edu/brand/preflight-avatar-512.png)

Normal procedures

## Before takeoff

Every push runs the same list, in the app's own pipeline, before anything reaches Citadel. Scroll, and it runs itself.

WSU app stack · normal checklist

Before takeoff · every push

1. PROCTOR Checked
   Checks the app against the stack's standards and publishes the result as a GitLab Code Quality report.
   `vendor/bin/proctor check --format=codequality`
2. PHP tests 8.3 · 8.4 · 8.5 pass
   One job per supported PHP version, through `parallel:matrix`. End-of-life PHP is not on the list.
   `vendor/bin/phpunit`
3. Composer audit No advisories
   Audits the lock file, not a fresh resolve, and fails the pipeline on a known advisory.
   `composer audit --locked`
4. SBOM Validated
   A CycloneDX bill of materials, validated and kept as a job artifact. The app's `composer.json` is never touched.
   `composer CycloneDX:make-sbom --output-format=JSON --validate`
5. Pint Clean
   The app's own Laravel Pint, in test mode, with the app's own `pint.json`.
   `vendor/bin/pint --test --config=pint.json`
6. PHPStan No errors
   The app's own PHPStan, writing its findings as a Code Quality report.
   `vendor/bin/phpstan analyse --error-format=gitlab`
7. ESLint · Prettier Clean
   The app's own ESLint and `prettier --check`, installed from the lock with scripts off.
   `npx --no-install eslint .`
8. Clearance Cleared for takeoff
   Every gate green. The release is free to leave for Citadel.

Checklist complete. Tray tables up, tests green.

- PROCTOR
- PHP 8.3
- PHP 8.4
- PHP 8.5
- AUDIT
- SBOM
- PINT
- PHPSTAN
- ESLINT
- A11Ycoming soon
- CONTRACTcoming soon
- FRESHNESScoming soon
- CLEARED FOR TAKEOFF

Makes the Composer audit fail, to show the pipeline holding short.

Cockpit placards

## Seven checks, one include each

Each one is an ordinary GitLab job with typed inputs and a sensible default. Every one is in the 0.1.1 tag, so pin it there. Two more components, `package-publish` and `renovate`, ship in the same tag; the README documents them.

in 0.1.1

### proctor

Watches the cabin.

Runs PROCTOR's checks and publishes them as a Code Quality report.

```
- component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@0.1.1
```

**6 inputs**

- **stage**: `test`
- **image**: `php:8.4-cli@sha256:…`
- **composer_version**: `2.10.3`
- **allow_failure**: `false`
- **proctor_command**: `vendor/bin/proctor check --format=codequality`
- **working_dir**: `.`

in 0.1.1

### php-test

Three engines, all running.

The test command on each supported PHP version, one job per version.

```
- component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@0.1.1
```

**5 inputs**

- **stage**: `test`
- **php_versions**: `["8.3", "8.4", "8.5"]`
- **composer_version**: `2.10.3`
- **test_command**: `vendor/bin/phpunit`
- **working_dir**: `.`

in 0.1.1

### composer-audit

Checks the passenger list.

`composer audit --locked`, failing on any advisory.

```
- component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@0.1.1
```

**3 inputs**

- **stage**: `test`
- **image**: `composer:2@sha256:…`
- **working_dir**: `.`

in 0.1.1

### sbom

The cargo manifest.

A validated CycloneDX SBOM, published as an artifact. The plugin installs globally, so the app's files stay as they are.

```
- component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@0.1.1
```

**4 inputs**

- **stage**: `test`
- **image**: `composer:2.10.3@sha256:…`
- **omit_dev**: `true`
- **output**: `sbom.cdx.json`

in 0.1.1

### pint

Uniform pressed.

The app's own Laravel Pint in test mode. The app requires `laravel/pint` and ships a `pint.json`.

```
- component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@0.1.1
```

**4 inputs**

- **stage**: `test`
- **image**: `composer:2.10.3@sha256:…`
- **config**: `pint.json`
- **working_dir**: `.`

in 0.1.1

### phpstan

Instruments cross-checked.

The app's own PHPStan, with a Code Quality report. The app requires `phpstan/phpstan` and ships a `phpstan.neon`.

```
- component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@0.1.1
```

**5 inputs**

- **stage**: `test`
- **image**: `composer:2.10.3@sha256:…`
- **config**: `phpstan.neon`
- **memory_limit**: `1G`
- **working_dir**: `.`

in 0.1.1

### eslint

The front cabin, too.

The app's own ESLint and Prettier. The app requires `@waynestate/pinstripe`, `eslint` and `prettier`.

```
- component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@0.1.1
```

**5 inputs**

- **stage**: `test`
- **image**: `node:22.13-alpine@sha256:…`
- **working_dir**: `.`
- **eslint_args**: `.`
- **prettier**: `true`

in 0.1.1

### php-package.yml

Two cockpits, one checklist.

Components stay inside one GitLab instance, so GitHub mirrors call this reusable workflow instead: `composer ci` on each PHP version, then a Composer audit.

```
uses: waynestate/preflight/.github/workflows/php-package.yml@0.1.1
```

**3 inputs**

- **php-versions**: `'["8.3","8.4","8.5"]'`
- **ci-command**: `composer ci`
- **working-directory**: `.`

### Deferred items

On the list, not yet on board. Nothing to include until they land.

- Coming soonAccessibility suiteAimed at WCAG 2.2 Level AA, the floor WayneUI's own gate uses, with a manual review step kept.
- Coming soonContract suiteNamed in the best practices as coming later. Not built yet.
- Coming soonSite freshnessPlanned. Not in this repo yet.

Quick start

## File a flight plan

Four boxes. Fill them in once, and every merge request and every push to the default branch runs the checklist.

1 Route · `.gitlab-ci.yml`

### Include the components

The `workflow:rules` block has to live in the app's own file: a component cannot set when the pipeline runs.

```
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@0.1.1
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@0.1.1
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@0.1.1
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@0.1.1
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@0.1.1
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@0.1.1
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@0.1.1
```

2 Switches · project settings

### Three settings that make gates harder to skip

All three work on GitLab Community Edition. Flip each one as you set it.

0 of 3 set

3 Alternate · GitHub mirror

### Mirrored to GitHub? Same checks there

A package mirrored to `github.com/waynestate` keeps its checks in a `ci` script in `composer.json` and calls the reusable workflow from `.github/workflows/ci.yml`. A release tag is not done until it is green on both sides.

```
name: CI

on:
  push:
    branches: ['**']
    tags: ['v*', '*.*.*']

jobs:
  ci:
    uses: waynestate/preflight/.github/workflows/php-package.yml@0.1.1
```

4 Ground check · your machine

### Run Preflight's own checks locally

From a clone of this repo: the template lint, its fixture tests, Pint and PHPStan through `composer ci`, then the inputs contract.

**Windows**

PowerShell 7. `composer ci` needs PHP 8.3+ and Composer; the contract check runs yq in Docker.

```
PS> composer install
PS> composer ci
PS> pwsh -File tests/check-contract.ps1
```

No PHP on the machine? Docker does it:

```
PS> docker run --rm -v "${PWD}:/app" -w /app composer:2 composer install
PS> docker run --rm -v "${PWD}:/app" -w /app composer:2 composer ci
```

**macOS · Linux**

`composer ci` needs PHP 8.3+ and Composer; the contract check needs yq v4.

```
$ composer install
$ composer ci
$ sh tests/check-contract.sh
```

No PHP on the machine? Docker does it:

```
$ docker run --rm -v "$(pwd):/app" -w /app composer:2 composer install
$ docker run --rm -v "$(pwd):/app" -w /app composer:2 composer ci
```

Crew resource management

## Hand it to your copilot

Three clearances, ready for the coding agent you already fly with. Copy one, or run it straight in OpenCode, Claude Code, Codex or ChatGPT. Each one tells the agent where the charts are, what it may not assume, and to ask the tower before it guesses.

### Get started with Preflight

The app's own `.gitlab-ci.yml`, with the components that fit it: raw PHP, Laravel with Blade, or Laravel with Inertia and Vue.

A prompt for your coding agent. Copy it as it stands:

```text
You are a coding agent adding Preflight to the GitLab pipeline of the app in this folder, at Wayne State University. Preflight is the CI of WELD, the Wayne State application stack: GitLab CI/CD components (proctor, php-test, composer-audit, sbom, pint, phpstan, eslint) that give every app the same checks, one include line each.

Read first:
- https://preflight.apps.wayne.edu/llms.txt, the index of Preflight's pages, each one as Markdown. Fetch the pages you need; do not work from memory.
- This app's .gitlab-ci.yml if there is one, composer.json and composer.lock, and package.json with its lock file if there is one.
- ADVISOR, the stack's MCP server, if it is connected: read_project_docs for preflight, and run_proctor_check to see what the proctor job will report. If it is not connected, say so and work from the pages. How to add it: https://advisor.apps.wayne.edu/llms.txt

Task:
1. Say which kind of app this is: raw PHP, raw PHP with Vue, Laravel with Blade, or Laravel with Inertia and Vue.
2. Pick the components that fit, and say why for each one left out. Each has a precondition: proctor needs waynestate/proctor as a dev dependency; pint needs laravel/pint and a pint.json; phpstan needs phpstan/phpstan and a phpstan.neon; eslint needs a package.json with @waynestate/pinstripe, eslint and prettier.
3. Write the include block, every component pinned to the release Preflight's page gives today, and the workflow:rules block (merge request pipelines, and pushes to the default branch) in the app's own .gitlab-ci.yml.
4. Keep every job the file already has. Show me the whole diff before you write it.

Constraints:
- Components work only inside the GitLab instance that hosts Preflight. If this app lives on another instance, stop and say so.
- Pin every component to a released version, never a branch. Never override a component's image with an unpinned one.
- A component is not a lock: never skip or weaken a job with rules or allow_failure to get a green pipeline. Fix the finding, or ask me.
- Strongly recommended: a git.wayne.edu instance runner. Say whether this project has one, or that you cannot tell.
- Ask me before you guess, and before you push anything.

Output: the app kind, the components with a reason each, the diff, then your questions.
```

### Or file for another route

### Preflight on a package's GitHub mirror

Components stop at the instance boundary, so a `waynestate/` package mirrored to GitHub calls Preflight's reusable workflow instead.

A prompt for your coding agent. Copy it as it stands:

```text
You are a coding agent wiring the GitHub mirror of the Composer package in this folder into Preflight, the CI of WELD, the Wayne State application stack. GitLab is the primary; the GitHub copy is a release mirror, and GitLab components cannot run there, so Preflight ships a reusable GitHub Actions workflow that runs the same checks.

Read first:
- https://preflight.apps.wayne.edu/llms.txt, then the GitHub mirrors section of Preflight's README (llms-full.txt carries it).
- This package's composer.json (its scripts, above all ci), .gitlab-ci.yml and .github/workflows/ if they exist.
- ADVISOR, the stack's MCP server, if it is connected: read_project_docs for preflight. If it is not connected, say so and work from the pages.

Task:
1. Check that composer.json has a ci script that runs every check the GitLab pipeline runs. The workflow only calls `composer ci`, so anything missing from the script is missing on GitHub.
2. Write .github/workflows/ci.yml that calls waynestate/preflight/.github/workflows/php-package.yml at the release Preflight's page gives today, on pushes to every branch and on release tags.
3. Set php-versions only if the package needs something other than the default. Show me the whole file before you write it.

Constraints:
- Pin the workflow to the release's full commit SHA, with the tag in a comment: PROCTOR's ci-pipelines check warns on any other uses: ref. If you cannot find the SHA, use the tag and say so.
- Never push to GitHub directly: the mirror fills from GitLab. Commit on GitLab only.
- A release tag is not done until it is green on both sides.
- Ask me before you guess, and before you push anything.

Output: the ci script as it stands and anything it lacks, the workflow file, then your questions.
```

### Version upkeep with Preflight's Renovate preset

One `renovate.json` that extends the shared preset, so patches and minors land green and majors wait for a person.

A prompt for your coding agent. Copy it as it stands:

```text
You are a coding agent putting the repository in this folder on Preflight's shared Renovate preset. Preflight owns the version automation of WELD, the Wayne State application stack: one preset, renovate/default.json in Preflight, and a renovate component that a private runner project runs on a schedule.

Read first:
- https://preflight.apps.wayne.edu/llms.txt, then the Renovate section of Preflight's README (llms-full.txt carries it): what auto-merges, what waits, and why MySQL and HA-Proxy get digests only.
- This repository's renovate.json if there is one, and its .gitlab-ci.yml.
- ADVISOR, the stack's MCP server, if it is connected: read_project_docs for preflight. If it is not connected, say so and work from the pages.

Task:
1. Add or replace renovate.json with the one the README gives: the Renovate schema, and extends set to local>enterprise-apps/preflight//renovate/default.
2. If the existing file has rules of its own, list them and ask me which to keep. Keep none silently.
3. Say what will auto-merge here and what will wait, from the preset's rules and this repository's dependencies.

Constraints:
- Change only renovate.json. Never set up a runner project, a schedule or a token: the runner project is private and holds a group-wide token. Ask me whether this group already runs one.
- Auto-merge needs a pipeline that really tests the change. If this repository has no pipeline, say so first.
- Ask me before you guess, and before you push anything.

Output: the renovate.json, what auto-merges and what waits, then your questions.
```

The agent reads the same pages you do: [llms.txt](https://preflight.apps.wayne.edu/llms.txt) lists them, [llms-full.txt](https://preflight.apps.wayne.edu/llms-full.txt) holds them in one file, and this page has a [Markdown twin](https://preflight.apps.wayne.edu/index.md). Nothing here phones home; the buttons only copy text or open the tool you picked. You have control.

From the flight manual

## Read before flight

What a shared template can do, what it cannot, and how Preflight keeps its own house in order.

Warning

**A component is not a lock.** An app's own `.gitlab-ci.yml` is merged over the included jobs, so it can override a job's keys, skip it with `rules`, or delete the `include:` line. Preflight makes the safe pipeline the easy one; Rollcall is where skipped or weakened gates show up.

A preflight checklist only works if the pilot reads it.

Caution

**Same instance only.** Components work only inside the GitLab instance that hosts Preflight; across instances, only by mirroring. Until git.wayne.edu has one, CI runs on the instance that has a runner. **A git.wayne.edu instance runner is strongly recommended.**

Note

**Every image is pinned by digest** (`name:tag@sha256:…`), so a repointed tag cannot quietly change what a pipeline runs. The `php-test` matrix is the one exception, tag-pinned on purpose so each job gets the newest PHP patch. Pins change only through a reviewed merge request.

```
$ docker buildx imagetools inspect <image>:<tag>
```

Preflight's own preflight

### The checklist checks the checklist

`composer ci` lints every template and workflow for unsafe CI patterns before the fixture tests run.

- `privileged` `privileged: true`
- `dind-service` Docker-in-Docker services
- `docker-sock` references to `docker.sock`
- `kaniko-image` Kaniko images
- `unpinned-action` GitHub `uses:` not pinned to a 40-character SHA
- `image-no-tag` an image with no tag
- `image-latest` an image on `latest`
- `image-no-digest` a warning: tagged, but not pinned by digest

A known warning goes in `lint-allow.yml` with a required `reason`, so an allowlist entry is a reviewed decision, not a silence. And on every pipeline, `contract/inputs.json` holds each input's name, type and default, and each job's name, steady inside a major version.

Wayne State app stack

## Departures

Preflight is one stop on the way to Citadel. Here is everyone else on the board.

- [WayneUI](https://wayneui.apps.wayne.edu/) The interface. Its a11y floor is the one Preflight's accessibility suite will aim at.
- [CREED](https://creed.apps.wayne.edu/) The written standards, and the policy every other part reads.
- [Pinstripe](https://pinstripe.apps.wayne.edu/) The coding standard behind the Pint, PHPStan and ESLint jobs.
- [PROCTOR](https://proctor.apps.wayne.edu/) One command that checks an app. First item on the checklist.
- Preflight Shared CI on every push. **You are here.**
- [Squire](https://squire.apps.wayne.edu/) Carries the cleared release to Citadel.
- [Rollcall](https://rollcall.apps.wayne.edu/) Every app answers "present". Skipped gates show up here.
- [Booster](https://booster.apps.wayne.edu/) Keeps an app's PHP current, so it stays on the test matrix.
- [HELMET](https://helmet.apps.wayne.edu/) Security headers and runtime hardening.
- [SESAME](https://sesame.apps.wayne.edu/) Sign-in for the app.
- [Drawbridge](https://drawbridge.apps.wayne.edu/) The Citadel sign-in gateway, lowered on request.
- [ADVISOR](https://advisor.apps.wayne.edu/) Ask what applies to your app, and what to do next.
- [Sourdough](https://sourdough.apps.wayne.edu/) Starters you feed, with Preflight already in the pipeline.
- [WELD](https://weld.apps.wayne.edu/) One app with every part already joined.
