# Changelog

All notable changes to PREFLIGHT are recorded here. Entries follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); released versions
are Git tags.

## Unreleased

### Added

- Added: advisory secret detection in the repository's own pipeline.
- Added: `tests/check-renovate-review.sh` (and its `.ps1` twin), a contract test that keeps the reviewed-bump rules in `renovate/default.json`.
- Added: README "Protection checklist": protected default branch, protected release tags, merge request approvals, `no_one_allowed` pipeline variables and no protected variables in fork pipelines.
- Added: README "Set up (the user does this)": the private runner project, the `RENOVATE_TOKEN` and optional `GITHUB_COM_TOKEN` CI variables, and a pipeline schedule; this repository creates none of them.

### Changed

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
