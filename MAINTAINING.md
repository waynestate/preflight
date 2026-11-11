# MAINTAINING: checklists for the checklist

How to build, test and release Preflight. Preflight is the CI that every other stack project runs, so a change here
lands on every runway at once. Walk around the plane before you push.

## What Preflight is and what it depends on

- GitLab CI/CD components in `templates/` (one folder per component, each with a `template.yml`), and a reusable
  GitHub Actions workflow, `.github/workflows/php-package.yml`.
- It is **not** a Composer library. `composer.json` is type `project` and exists only for its own tooling (template
  lint, Pint, PHPStan, `symfony/yaml`). It is not on Packagist.
- `contract/inputs.json` is the contract every component's inputs must match.
- **Who uses it:** every stack repo's `.gitlab-ci.yml` (components pinned at a release tag or its commit SHA) and
  `.github/workflows/ci.yml` (the reusable workflow pinned by commit SHA).

## Where it lives

Development happens on git.wayne.edu, the canonical repository ([enterprise-apps/preflight](https://git.wayne.edu/enterprise-apps/preflight)). GitHub ([waynestate/preflight](https://github.com/waynestate/preflight)) is a read-only push mirror of it: `main` and
tags are copied automatically, nobody pushes to it, and changes, issues and merge requests go to git.wayne.edu.
GitLab components can only be included from the same GitLab instance, so other instances need their own
copy (see "Same instance only" in the README).

## Build and test

| Task | Command |
|---|---|
| Install | `composer install` |
| All checks (template lint, its own tests, Pint, PHPStan) | `composer ci` |
| Contract tests, Windows (PowerShell) | `tests\check-contract.ps1`, and the other `tests\check-*.ps1` |
| Contract tests, Linux and macOS | `sh tests/check-contract.sh`, and the other `tests/check-*.sh` |

Each contract test comes as a `.sh` and `.ps1` pair that check the same thing (`check-contract`, `check-spec-keys`,
`check-image-inputs`, `check-dependency-cache`, `check-php-test-cache`, `check-working-dir-regex`, `check-path-input-regex`, `check-github-workflow`,
`check-proctor-install-flags`, `check-secret-detection`, `check-renovate-review`, `check-renovate-buildah`, `check-sha-pins`, `check-release-job`,
`check-abandoned-input`, `check-component-version`, `check-input-interpolation`, `check-a11y-inline`, `check-portability-inline`, `check-renovate-squire-kit`, `check-squire-kit`). CI runs the `.sh` ones in the contract job.
Keep both in step when you change one.

`tests/check-portability.sh` runs the portability probe (`templates/portability/probe.sh`) on the fixture in
`tests/portability/app`, once clean and once per flaw (`ARG FLAW` in its Dockerfile), and passes only when the clean
build passes every check and each flaw fails the check it targets. Two more builds, `reopens-stderr` and `signals-group`, are regression cases for the probe's launcher (stdio the uid owns, a session of its own) and must pass. It needs Buildah, so it runs inside the
component's Buildah image: the `must-fail-portability` job runs it in CI, and `tests/check-portability.ps1` (or the
`docker run` in the .sh header) runs it locally with `--security-opt seccomp=unconfined`, never `--privileged`.
Preflight's pipeline also includes the component itself on the clean fixture. Change the probe in `probe.sh`, then run
`sh tests/check-portability-inline.sh --write` (PowerShell: `tests\check-portability-inline.ps1 -Write`) to copy it into
the template; the contract job fails while the two differ. A new flaw gets a branch in the fixture and a line in the
case list of `tests/check-portability.sh`.

`tests/check-a11y.sh` (and `tests/check-a11y.ps1`) is a local check that needs Docker: it runs the `a11y` component's
checker against the good and bad sites in `tests/a11y-fixtures` and passes only when the good one is clean and the bad
one fails with each known flaw named. Run it after any change to `templates/a11y/check.mjs`, then
`sh tests/check-a11y-inline.sh --write` (PowerShell: `tests\check-a11y-inline.ps1 -Write`) to copy the checker into
the template; the contract job fails while the two differ. The site's own gate is `sh scripts/a11y.sh` (PowerShell:
`scripts\a11y.ps1`).

`tests/check-php-test-fails.sh`, `tests/check-phpstan-fails.sh` and `tests/check-pint-fails.sh` (each with a `.ps1`
twin) run the `php-test`, `phpstan` and `pint` components' own commands, in the components' own images, against the
clean case in `tests/fixture-app` and the must-fail case in `tests/php-test-fails`, `tests/phpstan-fails` and
`tests/pint-fails`, and pass only when the clean case passes and the bad case fails. The `must-fail-php-test` and
`must-fail-phpstan-pint` jobs run them in CI, in the templates' own images, and they still run locally with Docker, as
the script headers show.

`tests/check-composer-audit-fails.sh` (and its `.ps1` twin) renders the `composer-audit` template's own script lines
and runs them in its image on `tests/fixture-app` (must pass) and on the locks in `tests/audit-fixtures`: `advisory`
and `malware` must fail in every `abandoned` mode, `abandoned` only in `fail` mode, each naming its finding. The
`must-fail-composer-audit` job runs it in CI. It needs Packagist (advisories and filter lists are fetched on every
run), so a run offline fails. The fixtures are pinned so the answers never move; if Packagist ever drops one (for
example Aikido retires its test package), pick another permanent entry and update the expected name in the script.

`tests/squire-kit-fixture` is a deploy kit written by `squire init --target=raw`; Preflight's own pipeline runs the
`squire-kit` component on it. Renovate moves it with each Squire release, like any kit. Never edit its files by hand:
rewrite it with Squire (`squire update`, then `squire init`, on the folder) so it stays a kit that passes
`squire init --check`. Pint and PHPStan skip it.

With only Docker:

```
docker run --rm -v "${PWD}:/app" -w /app composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 sh -c "composer install --no-interaction && composer ci"
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
4. Tag `X.Y.Z` (no `v`) on git.wayne.edu, and protect the tag pattern so a release tag cannot move. Pushing the protected tag
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

The stack maintainer (a role, not a named person), Wayne State University Enterprise Applications. To reach them,
open an issue on git.wayne.edu. Internal runbook (accounts, tokens, mirrors, runners):
ask Enterprise Applications.
