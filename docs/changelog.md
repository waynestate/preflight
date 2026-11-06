---
title: "Changelog"
description: All notable changes to this project.
---

<!-- Generated from CHANGELOG.md by bin/docs-site.php. Edit CHANGELOG.md, not this file. -->

# Changelog

All notable changes to PREFLIGHT are recorded here. Entries follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); released versions
are Git tags.

## Unreleased

- Fixed: the proctor and sbom jobs install the app with `--ignore-platform-reqs`. Both only read the app, yet a lock built for an older PHP or one needing gd, oci8 or ldap stopped them before PROCTOR or CycloneDX ran, so the oldest apps got no report. The sbom job also passes `--no-scripts`, so the app's Composer scripts no longer run in it. Found by the 2026-11-05 proof run; `tests/check-proctor-install-flags` (sh and ps1) now checks both lines.
- Added: a public Proof page (`docs/reference/proof.md`, under Reference): the components run against 82 Wayne State applications, what held, what the run caught in Preflight, and what it does not prove. Local checks and the README link to it.
- Added: troubleshooting entries for an install that stops on another PHP or a missing extension, a private package with no credential, and `npm ci` without a `package-lock.json`.
- Security: the front-page deploy layer moves to Symfony 7.4.23 (symfony/http-foundation and symfony/yaml advisories, including CVE-2026-118514).
- Changed: the docs theme carries the hero's sectional chart (its grid and contour rings) faintly under the top of every page, frames the overview's picture of the front page like the hero's instrument, and sets the badges in a row. Dark mode now really is the instrument panel: the kit's dark block had been winning for the page and inline code backgrounds, which left WayneUI's dark green surface everywhere; titles are panel light and the lit green is kept to links, the current page and focus.
- Changed: the docs pages wear the front page's look: its top bar and main menu (Docs marked current), B612 and B612 Mono, the cream chart page, commands on the quickstart's slab with its Copy key, callouts as the handbook's NOTE, CAUTION and WARNING boxes, tables and the pager as flight-plan forms, and the green runway footer; dark mode follows the instrument panel. New `docs/_header.html` and `docs/theme/preflight.css`, named under `theme` in `docs/docs.json`.
- Changed: the docs builder and kit are Squire's 0778fed: the theme hook, callouts, code tabs, task-list checkbox labels (fixes the axe `label` failures on the protection checklist) and a keyboard-reachable scrolling code block.
- Fixed: the contract job's Buildah pin check no longer needs git, which the mikefarah/yq image does not have; when git is missing or fails it scans regular files with find instead, skipping .git, vendor/ and node_modules/.
- Added: a Composer cache on the proctor component, keyed on composer.lock (BEST_PRACTICES 4.8); new test tests/check-proctor-cache.
- Added: every component job prints a `Preflight component <name> <version> (ref <reference>, sha <sha>)` line as its first command, so a job log says which Preflight release produced it; each template declares `spec: component: [name, version, sha, reference]`. New tests `tests/check-component-version.sh` and `tests/check-component-version.ps1`; `tests/check-spec-keys` and the template lint allow `component` under `spec:`.
- Changed: Preflight now needs GitLab 18.7 or later: `spec: component:` is generally available from 18.7, and pipeline creation fails on the unknown key on older instances.
- Added: the docs site at `site/docs/`, built from `docs/` by Squire's shared docs builder (`bin/docs-site.php`), starting with the overview page. New composer scripts: `docs` builds it, `docs:check` fails when it is stale, and `ci` now runs the check.
- Docs: component pins in the README and site examples now point at 0.1.4.
- Changed: the front-page deploy layer pins HELMET ^0.3, PROCTOR ^0.4 and CREED ^0.1 (lock: HELMET 0.3.0, PROCTOR 0.4.0, CREED 0.1.6).
- Changed: the deploy layer sets minimum-stability to stable.
- Changed: phpstan config and memory_limit, pint config and sbom output now carry an input regex (relative paths and PHP sizes only); a value outside it stops the pipeline at creation. New test tests/check-path-input-regex.
- Added: a tag-triggered `release` job in the repository's own pipeline: pushing a protected tag creates the GitLab Release through the Releases API with curl, and the release notes carry the tag's commit SHA so consumers can pin it (BEST_PRACTICES 1.3, 1.6); new test tests/check-release-job.
- Added: a packageRule in `renovate/default.json` that restricts `quay.io/buildah/stable` to `-immutable` tags (regex versioning), so Renovate never moves a pin back to a mutable tag after Red Hat re-pushed one and garbage-collected the old digest; new test tests/check-renovate-buildah.
- Changed: the portability component's `buildah_image` default moves to the immutable tag `quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb`; Red Hat re-pushed the plain version tag and garbage-collected the old digest, so pipelines pinned to the mutable tag broke. New test tests/check-buildah-pin.
- Added: an `abandoned` input on the composer-audit component (`fail`, `report` or `ignore`, default `fail`) so an app can relax how `composer audit` treats abandoned packages on purpose; the job now runs `composer audit --locked --abandoned=$[[ inputs.abandoned ]]`. New test tests/check-abandoned-input (and its `.ps1` twin) with the fixtures in tests/audit-fixtures.

## 0.1.4 (2026-11-03)

### Changed

- Changed: the README explains which jobs may be allowed to fail (only `proctor`) and that the contract check rejects global keys; BEST_PRACTICES 2.3 is now Enforced.
- Changed: check-image-inputs allows `portability-build` to take `buildah_image` (the only exemption from 2.10).
- Changed: docs and package metadata name nougat as the canonical repository, with git.wayne.edu and GitHub as read-only mirrors, until git.wayne.edu has CI runners.

### Added

- Added: README example for an advisory job on the next PHP release (a second `php-test` include with `job_name`), and PowerShell forms of the local Docker commands.
- Added: a `job_name` input on every component except `portability` (default is the usual job name), so one project can include a component more than once; `tests/check-job-names` enforces it and `tests/check-contract` resolves the key.
- Added: portability component (Buildah build, arbitrary-uid boot, goss checks, fixtures).
- Added: a Squire kit version rule in `renovate/default.json`: a custom regex manager reads the `version` line of `.squire.json`, and the `waynestate/squire` bump carries the `squire-kit` label and never auto-merges; a person runs `squire update` to refresh the kit files.

### Fixed

- Fixed: the component-rule manager name in `renovate/default.json` (`gitlabci`, matching repository deps), so component version bumps really wait for review instead of auto-merging; the contract test now checks the new rule and the Squire kit rule.
- Fixed: the portability goss health check uses `method: GET`; goss sends the method as written, and a lower-case one makes the server close the connection, so the good fixture failed with EOF.
- Fixed: the portability fixtures make their temp dir mode 0777 and the goss files in it mode 0644, because the app user is not the host user that owns the dir and goss is downloaded into it.

## 0.1.3 (2026-11-03)

### Added

- Added: advisory secret detection in the repository's own pipeline.
- Added: `tests/check-renovate-review.sh` (and its `.ps1` twin), a contract test that keeps the reviewed-bump rules in `renovate/default.json`.
- Added: README "Protection checklist": protected default branch, protected release tags, merge request approvals, `no_one_allowed` pipeline variables and no protected variables in fork pipelines.
- Added: README "Set up (the user does this)": the private runner project, the `RENOVATE_TOKEN` and optional `GITHUB_COM_TOKEN` CI variables, and a pipeline schedule; this repository creates none of them.

### Changed

- Changed: README and examples show SHA pins with the tag in a trailing comment.
- Changed: `renovate/default.json` no longer auto-merges updates inside `templates/**`, `contract/**` and `.gitlab-ci.yml`, or component include version bumps: they carry the `needs-review` label and wait for a person.
- Changed: the deploy layer's Squire kit is refreshed to 0.3.3 (release options can now live in ./.env.squire).
- Changed: the deploy layer's Squire kit is refreshed to 0.3.4 (the local .env.squire file is now git-ignored).
- Documented: running the composer-audit component on a weekly pipeline schedule.
- Documented: the job token allowlist rule and the runner request wording (non-privileged, ephemeral Docker executor).
- Changed: the repository's own pipeline pulls Docker Hub images through the GitLab Dependency Proxy (component defaults are unchanged).
- Changed: the proctor component installs the app with --no-plugins --no-scripts.

### Fixed

- Fixed: stale 0.1.0 and next-tag wording in the best practices, the GitHub example and the checklist art.
- Fixed: the readme art script handles all nine components, including package-publish and renovate.
- Fixed: BEST_PRACTICES 2.2, 2.9 and 6.2 match the templates.
- Fixed: BEST_PRACTICES statements match the repo; README no longer claims Renovate bumps component pins.
- Fixed: the renovate component no longer sets `RENOVATE_TOKEN` and `GITHUB_COM_TOKEN` from themselves in the job `variables:`; on GitLab 19.5 that self-reference arrived as literal text and shadowed the masked project CI/CD variables, so the job now reads both tokens straight from the project.

## 0.1.2 (2026-10-29)

### Added

- Added: agent-ready site (prompt blocks, Markdown twins, llms.txt), from Squire's kit.

### Fixed

- Fixed: stale capability claims in the site and README.

### Changed

- Docs: README.md, MAINTAINING.md and site/index.html pin components at
  `@0.1.1`, and the notes about components arriving in a later tag are gone,
  because 0.1.1 contains every component.
- Changed: the proof page moves to a private site that needs a Wayne State sign-in.
- Changed: project names written as words except acronyms.

## 0.1.1 (2026-10-29)

### Added

- `package-publish` component: publishes a semantic version tag to the
  GitLab group's built-in Composer registry. The job reads the registry
  before publishing, so republishing from the same commit is a no-op and
  republishing from a different commit fails instead of overwriting the
  version.
- `renovate` component and shared preset `renovate/default.json`: Renovate
  runs as a scheduled GitLab pipeline in a private runner project and bumps
  image digests, GitHub action SHAs and package versions across the stack.
  Bumps of `component:` include pins are not covered yet: the preset carries
  no manager for them. Digest, pin and patch/minor updates auto-merge when CI
  is green; majors open a merge request and wait for a person.

### Changed

- PHPStan: `phpstan.neon` now includes Pinstripe's `raw.neon` preset from
  the new `waynestate/pinstripe` dev dependency instead of carrying a hand
  copy of its settings. The repo keeps only its own paths, excluded fixture
  app and PHP version range. Strict rules stay off as before, and
  deprecation checks now run on every analysis.

## 0.1.0 (2026-10-27)

- First tagged release.
