# MAINTAINING: checklists for the checklist

How to build, test and release Preflight. Preflight is the CI that every other stack project runs, so a change here
lands on every runway at once. Walk around the plane before you push.

## What Preflight is and what it depends on

- GitLab CI/CD components in `templates/` (one folder per component, each with a `template.yml`), and a reusable
  GitHub Actions workflow, `.github/workflows/php-package.yml`.
- It is **not** a Composer library. `composer.json` is type `project` and exists only for its own tooling (template
  lint, Pint, PHPStan, `symfony/yaml`). It is not on Packagist.
- `contract/inputs.json` is the contract every component's inputs must match.
- **Who uses it:** every stack repo's `.gitlab-ci.yml` (components pinned at a tag, `@0.1.1` today) and
  `.github/workflows/ci.yml` (the reusable workflow pinned by commit SHA).

## Where it lives

Development happens on nougat, the canonical repository ([enterprise-apps/preflight](https://nougat.snu.gs/enterprise-apps/preflight)). This GitHub repository and git.wayne.edu are read-only mirrors: `main` and tags are
copied automatically, and changes, issues and merge requests go to nougat. Nobody pushes to the mirrors. GitLab
components can only be included from the same GitLab instance, so other instances need their own
copy (see "Same instance only" in the README).

## Build and test

| Task | Command |
|---|---|
| Install | `composer install` |
| All checks (template lint, its own tests, Pint, PHPStan) | `composer ci` |
| Contract tests, Windows (PowerShell) | `tests\check-contract.ps1`, and the other `tests\check-*.ps1` |
| Contract tests, Linux and macOS | `sh tests/check-contract.sh`, and the other `tests/check-*.sh` |

Each contract test comes as a `.sh` and `.ps1` pair that check the same thing (`check-contract`, `check-spec-keys`,
`check-image-inputs`, `check-php-test-cache`, `check-working-dir-regex`, `check-path-input-regex`, `check-github-workflow`,
`check-proctor-install-flags`, `check-secret-detection`, `check-renovate-review`, `check-renovate-buildah`, `check-sha-pins`, `check-release-job`,
`check-abandoned-input`, `check-component-version`, `check-input-interpolation`, `check-a11y-inline`). CI runs the `.sh` ones, except `check-abandoned-input`: the contract job's yq image has no Docker, and the test runs composer in the composer:2.10.3 image, so it stays out of the contract job's script list in `.gitlab-ci.yml`.
Keep both in step when you change one.

`tests/check-portability.sh` (and `tests/check-portability.ps1`) is a local check that needs Docker and runs the
three fixtures in `tests/portability`; the contract job does not run it.

`tests/check-a11y.sh` (and `tests/check-a11y.ps1`) is a local check that needs Docker: it runs the `a11y` component's
checker against the good and bad sites in `tests/a11y-fixtures` and passes only when the good one is clean and the bad
one fails with each known flaw named. Run it after any change to `templates/a11y/check.mjs`, then
`sh tests/check-a11y-inline.sh --write` (PowerShell: `tests\check-a11y-inline.ps1 -Write`) to copy the checker into
the template; the contract job fails while the two differ. The site's own gate is `sh scripts/a11y.sh` (PowerShell:
`scripts\a11y.ps1`).

With only Docker:

```
docker run --rm -v "${PWD}:/app" -w /app composer:2.10.3 sh -c "composer install --no-interaction && composer ci"
```

The fixture app in `tests/fixture-app` is what the components run against in CI. To run its tests by hand, install
and run PHPUnit inside it the same way.

## CI

- **GitLab:** the pipeline runs Preflight's own components against `tests/fixture-app` at the current commit (so a
  broken component fails here first), plus a `contract` job running the `tests/check-*.sh` scripts.
- **GitHub:** `.github/workflows/ci.yml` runs the local reusable workflow with `composer ci`.
- Green means both pass. The fixture-app jobs run on GitLab only.

## Changing a component

- Inputs go in `spec:` and must match `contract/inputs.json`; only real input keys belong in `spec:` (a wrong key stops
  pipelines from starting at all, in every consumer).
- Images are pinned by digest. "Updating image pins" in the README says how.
- `lint-allow.yml` exceptions each need a `reason`.
- Windows `.ps1` files keep CRLF line endings (`.gitattributes`).

## Releasing

1. Move the lines under `## Unreleased` in `CHANGELOG.md` to a new `## X.Y.Z (YYYY-MM-DD)` heading. (Released
   versions are git tags; 0.1.0 predates the heading convention.)
2. `composer ci` and the contract tests green, then both pipelines green for that commit.
3. Run a secrets scan of the history and check that nothing internal is in the tree.
4. Tag `X.Y.Z` (no `v`) on nougat, and protect the tag pattern so a release tag cannot move. Pushing the protected tag
   runs the `release` job, which creates the GitLab Release with the tag's commit SHA in its notes, so consumers can pin
   the SHA. The project's job token must be allowed to create releases, or the job fails. The mirror carries the tag to
   GitHub. Record the tag's commit SHA in the CHANGELOG, because GitHub consumers pin the reusable workflow by SHA.
5. **Then bump the pins in every consumer:** the `@X.Y.Z` on each component include in their `.gitlab-ci.yml`, and the
    SHA in their `.github/workflows/ci.yml`. Every component ships in each tag from 0.1.1 on, so a new consumer pins
    the latest tag on every include.
6. A release needs a maintainer's approval.

## The front page

`site/` is the static front page, for `https://preflight.apps.wayne.edu/` on Citadel, served through a small raw-PHP
`deploy/` layer generated with Squire.

## Who maintains it

Adam Perkins, Wayne State University Enterprise Applications. Internal runbook (accounts, tokens, mirrors, runners):
ask Enterprise Applications.
