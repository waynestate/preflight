# Changelog

All notable changes to PREFLIGHT are recorded here. Entries follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); released versions
are Git tags.

## Unreleased

### Added

- `package-publish` component: publishes a semantic version tag to the
  GitLab group's built-in Composer registry. The job reads the registry
  before publishing, so republishing from the same commit is a no-op and
  republishing from a different commit fails instead of overwriting the
  version.

### Changed

- PHPStan: `phpstan.neon` now includes Pinstripe's `raw.neon` preset from
  the new `waynestate/pinstripe` dev dependency instead of carrying a hand
  copy of its settings. The repo keeps only its own paths, excluded fixture
  app and PHP version range. Strict rules stay off as before, and
  deprecation checks now run on every analysis.
