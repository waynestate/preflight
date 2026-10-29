# Changelog

All notable changes to PREFLIGHT are recorded here. Entries follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); released versions
are Git tags.

## Unreleased

### Changed

- Changed: the deploy layer's Squire kit is refreshed to 0.3.3 (release options can now live in ./.env.squire).
- Changed: the deploy layer's Squire kit is refreshed to 0.3.4 (the local .env.squire file is now git-ignored).

### Fixed

- Fixed: stale 0.1.0 and next-tag wording in the best practices, the GitHub example and the checklist art.
- Fixed: the readme art script handles all nine components, including package-publish and renovate.

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
  image tags, CI component pins, GitHub action SHAs and package versions
  across the stack. Digest, pin and patch/minor updates auto-merge when CI
  is green; majors open a merge request and wait for a person.

### Changed

- PHPStan: `phpstan.neon` now includes Pinstripe's `raw.neon` preset from
  the new `waynestate/pinstripe` dev dependency instead of carrying a hand
  copy of its settings. The repo keeps only its own paths, excluded fixture
  app and PHP version range. Strict rules stay off as before, and
  deprecation checks now run on every analysis.

## 0.1.0 (2026-10-27)

- First tagged release.
