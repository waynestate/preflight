---
title: "Local checks | Preflight docs"
description: "How maintainers build, test and release this project with Docker."
url: https://preflight.apps.wayne.edu/docs/reference/local-checks.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Local checks[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#local-checks)

How maintainers build, test and release this project with Docker, and the Composer scripts behind the gate. The pre-flight checklist, run from your own desk: run the same gate CI runs before you push anything.

Note

Maintainers: how to build, test and release this project, and where its data comes from, is in [MAINTAINING.md](https://git.wayne.edu/enterprise-apps/preflight/-/blob/main/MAINTAINING.md) on the canonical repository.

## The full gate[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#the-full-gate)

Run the template lint and the fixture tests with Docker:

linux

```sh
docker run --rm -v "$(pwd):/app" -w /app composer:2 composer install
docker run --rm -v "$(pwd):/app" -w /app composer:2 composer ci
```

windows

```powershell
docker run --rm -v "${PWD}:/app" -w /app composer:2 composer install
docker run --rm -v "${PWD}:/app" -w /app composer:2 composer ci
```

In PowerShell, use `${PWD}` instead of `$(pwd)`. `composer ci` is the whole gate: it runs the template lint, the fixture tests, Pint, PHPStan, the agent-ready file check and the docs site check, in that order.

## Composer scripts[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#composer-scripts)

The scripts from `composer.json`:

```json
{
    "ci": [
        "php bin/lint-templates",
        "php bin/lint-templates --test",
        "@lint",
        "@analyse",
        "@site:agent-ready-check",
        "@docs:check"
    ],
    "lint": "pint --test",
    "fix": "pint",
    "analyse": "phpstan analyse --memory-limit=1G",
    "site:agent-ready": "php bin/agent-ready.php",
    "site:agent-ready-check": "php bin/agent-ready.php --check",
    "docs": "php bin/docs-site.php",
    "docs:check": "php bin/docs-site.php --check"
}
```

| Script | Runs | What it does |
| --- | --- | --- |
| `ci` | the array above | The full CI gate: template lint, fixture tests, Pint, PHPStan, agent-ready files, docs site. |
| `lint` | `pint --test` | Run Pint in test mode; fails on style errors without changing files. |
| `fix` | `pint` | Run Pint and rewrite the files it finds. |
| `analyse` | `phpstan analyse --memory-limit=1G` | Run PHPStan with a 1G memory limit. |
| `site:agent-ready` | `php bin/agent-ready.php` | Rewrite the Markdown twins, llms.txt, llms-full.txt, robots.txt and sitemap.xml in `site/` (Squire's agent-ready kit). |
| `site:agent-ready-check` | `php bin/agent-ready.php --check` | Fail when the agent-ready files are stale, a page lacks its Markdown link, a prompt drifts from the docs, or the kit was edited here. |
| `docs` | `php bin/docs-site.php` | Build the docs site from `docs/` into `site/docs/` (Squire's docs builder): render the pages, fill the generated command and environment reference, and stamp the current version. |
| `docs:check` | `php bin/docs-site.php --check` | Fail when the built docs site is stale or the generated command or environment reference has drifted from the CLI or source. |

## The PHP fixture app[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#the-php-fixture-app)

Run the PHP fixture app separately:

```sh
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app composer:2 composer install
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app php:8.4-cli vendor/bin/phpunit
```

## The portability fixtures[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#the-portability-fixtures)

Run the portability fixtures with Docker. The check runs the component's own probe in the component's own Buildah image against `tests/portability/app`, once clean and once per flaw, and exits 0 only when the clean build passes every check and each flaw fails the check it targets. It takes about two minutes. `--security-opt seccomp=unconfined` lets Buildah open the user namespace that Docker's default seccomp profile refuses; it grants no capabilities and is not `--privileged`.

linux

```sh
docker run --rm --security-opt seccomp=unconfined -v "$(pwd):/src:ro" -w /src \
  quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb \
  sh tests/check-portability.sh
```

windows

```powershell
pwsh -File tests/check-portability.ps1
```

To run some cases only, set `PORTABILITY_CASES` (for example `-e PORTABILITY_CASES="none sigterm"` on the `docker run`), or pass `-Cases none,sigterm` to the `.ps1`.

## The accessibility gate[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#the-accessibility-gate)

The site's pages have an accessibility gate: the `a11y` component's own checker (`templates/a11y/check.mjs`, axe-core in Playwright), run in Docker with the image and versions pinned in `templates/a11y/template.yml`, so no host browser is needed and a local run checks the same way as the pipeline. With no options it checks the front page and every docs page at WCAG 2.2 AA, in light and dark mode at 320 px and 1280 px, with the reflow check, and fails on any violation:

linux

```sh
sh scripts/a11y.sh
```

windows

```powershell
scripts\a11y.ps1
```

Options pick another folder, pages, tags or a folder for the reports: `--site=DIR --pages='["index.html"]' --tags='["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]' --report=DIR` (PowerShell: `-Site`, `-Pages`, `-Tags`, `-Report`).

## The accessibility fixtures[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#the-accessibility-fixtures)

`tests/check-a11y.sh` (and `tests/check-a11y.ps1`) prove the checker still tells a clean site from a bad one. They run the gate against `tests/a11y-fixtures` at the component's default WCAG 2.1 AA and exit 0 only when the good site passes, the bad site fails with each known flaw named (a missing `lang`, an image with no `alt`, an unlabeled input, weak contrast, a page that scrolls sideways at 320 px, and a palette that fails in dark mode only), a missing page fails with HTTP 404, and a glob that matches nothing stops with a configuration error. They need Docker; the contract job does not run them.

linux

```sh
sh tests/check-a11y.sh
```

windows

```powershell
pwsh -File tests/check-a11y.ps1
```

`tests/check-a11y-inline.sh` (and `.ps1`) checks that the heredoc in the template is a byte-for-byte copy of `templates/a11y/check.mjs`; the contract job runs it. After editing `check.mjs`, run `sh tests/check-a11y-inline.sh --write` (PowerShell: `tests\check-a11y-inline.ps1 -Write`) to copy it into the template.

## The must-fail fixtures[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#the-must-fail-fixtures)

`tests/check-php-test-fails.sh`, `tests/check-phpstan-fails.sh` and `tests/check-pint-fails.sh` (each with a `.ps1` twin) prove the `php-test`, `phpstan` and `pint` components still fail a bad app and pass a clean one. Each asserts its template keeps the job line it promises, then runs the component's own commands from its template, in the component's own image, against the clean case in `tests/fixture-app` and the must-fail case in its fixture (`tests/php-test-fails`, `tests/phpstan-fails`, `tests/pint-fails`), in a copy in a temp dir. They exit 0 only when the clean case passes and the bad case fails with the expected finding. The `.sh` is the payload of a container; the `.ps1` runs it with Docker. They need Docker; the contract job does not run them.

linux

```sh
docker run --rm -v "$(pwd):/app" -w /app php:8.3-cli-trixie sh tests/check-php-test-fails.sh
docker run --rm -v "$(pwd):/app" -w /app composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc sh tests/check-phpstan-fails.sh
docker run --rm -v "$(pwd):/app" -w /app composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc sh tests/check-pint-fails.sh
```

windows

```powershell
pwsh -File tests/check-php-test-fails.ps1
pwsh -File tests/check-phpstan-fails.ps1
pwsh -File tests/check-pint-fails.ps1
```

## The Squire kit checks[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#the-squire-kit-checks)

`tests/check-renovate-squire-kit.sh` (and `.ps1`) checks the preset's Squire rule: the exact two post-upgrade commands, the kit-files rule, and the `squire_kit_tasks` allow-list the renovate component writes. It compiles the commands for sample upgrades and checks that each one matches an allowed pattern, and that 22 hostile variants (shell operators, `..` paths, another package or tool, an extra flag) match none. `tests/check-squire-kit.sh` (and `.ps1`) checks the `squire-kit` template: the version it reads, the install flags, `squire init --check` and its exit codes. The contract job runs both `.sh` files; the job itself runs on `tests/squire-kit-fixture` in Preflight's own pipeline.

## Proof[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#proof)

Proof runs against real Wayne State applications are on a private site, [proof.apps.wayne.edu/preflight](https://proof.apps.wayne.edu/preflight/), behind a Wayne State employee sign-in. What was run, what held and what it caught in Preflight itself is on the public [Proof](https://preflight.apps.wayne.edu/docs/reference/proof.html) page.

## Docs[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#docs)

The full documentation lives at [preflight.apps.wayne.edu/docs/](https://preflight.apps.wayne.edu/docs/) on the project site, built from `docs/` by Squire's docs builder. It starts with the overview page; the rest of the manual follows as the pages are written.

- `composer docs` rebuilds `site/docs/` from `docs/`; run it after editing a page.
- `composer docs:check` fails when the built site is stale; `composer ci` runs it.

The pages are committed because the deploy server serves `site/` without building. Every page links back to its Markdown, and the footer stamps the version the docs describe. Cleared for takeoff: the flight manual flies with the aircraft.

The pages wear the front page's flight deck: `docs/_header.html` is the front page's top bar and `docs/theme/preflight.css` maps its palette and B612 type onto the docs kit, with a dark mode taken from the instrument panel. `docs/docs.json` names both under `theme`. Restyle the docs in those two files, never in `site/assets/docs.css` or `bin/docs-site.php`: those are Squire's bytes.

## Related[#](https://preflight.apps.wayne.edu/docs/reference/local-checks.html#related)

- [Components](https://preflight.apps.wayne.edu/docs/reference/components.html)
- [The a11y component](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html)
- [Shared conventions](https://preflight.apps.wayne.edu/docs/reference/conventions.html)
- [Template lint](https://preflight.apps.wayne.edu/docs/guides/template-lint.html)
- [Updating image pins](https://preflight.apps.wayne.edu/docs/guides/image-pins.html)
- [Troubleshooting](https://preflight.apps.wayne.edu/docs/troubleshooting.html)
- [Changelog](https://preflight.apps.wayne.edu/docs/changelog.html)
- [Upgrading](https://preflight.apps.wayne.edu/docs/upgrading.html)
