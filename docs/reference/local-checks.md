---
title: Local checks
description: How maintainers build, test and release this project with Docker.
---

# Local checks

How maintainers build, test and release this project with Docker, and the Composer scripts behind the gate. The pre-flight checklist, run from your own desk: run the same gate CI runs before you push anything.

> [!NOTE]
> Maintainers: how to build, test and release this project, and where its data comes from, is in [MAINTAINING.md](https://nougat.snu.gs/enterprise-apps/preflight/-/blob/main/MAINTAINING.md) on the canonical repository.

## The full gate

Run the template lint and the fixture tests with Docker:

```sh tab="linux"
docker run --rm -v "$(pwd):/app" -w /app composer:2 composer install
docker run --rm -v "$(pwd):/app" -w /app composer:2 composer ci
```

```powershell tab="windows"
docker run --rm -v "${PWD}:/app" -w /app composer:2 composer install
docker run --rm -v "${PWD}:/app" -w /app composer:2 composer ci
```

In PowerShell, use `${PWD}` instead of `$(pwd)`. `composer ci` is the whole gate: it runs the template lint, the fixture tests, Pint, PHPStan, the agent-ready file check and the docs site check, in that order.

## Composer scripts

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
|--------|------|--------------|
| `ci` | the array above | The full CI gate: template lint, fixture tests, Pint, PHPStan, agent-ready files, docs site. |
| `lint` | `pint --test` | Run Pint in test mode; fails on style errors without changing files. |
| `fix` | `pint` | Run Pint and rewrite the files it finds. |
| `analyse` | `phpstan analyse --memory-limit=1G` | Run PHPStan with a 1G memory limit. |
| `site:agent-ready` | `php bin/agent-ready.php` | Rewrite the Markdown twins, llms.txt, llms-full.txt, robots.txt and sitemap.xml in `site/` (Squire's agent-ready kit). |
| `site:agent-ready-check` | `php bin/agent-ready.php --check` | Fail when the agent-ready files are stale, a page lacks its Markdown link, a prompt drifts from the docs, or the kit was edited here. |
| `docs` | `php bin/docs-site.php` | Build the docs site from `docs/` into `site/docs/` (Squire's docs builder): render the pages, fill the generated command and environment reference, and stamp the current version. |
| `docs:check` | `php bin/docs-site.php --check` | Fail when the built docs site is stale or the generated command or environment reference has drifted from the CLI or source. |

## The PHP fixture app

Run the PHP fixture app separately:

```sh
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app composer:2 composer install
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app php:8.4-cli vendor/bin/phpunit
```

## The portability fixtures

Run the portability fixtures with Docker; they build and boot the three fixtures under `tests/portability` the strict way and exit 0 only when `good` passes and both `bad-*` fixtures fail:

```sh tab="linux"
sh tests/check-portability.sh
```

```powershell tab="windows"
pwsh -File tests/check-portability.ps1
```

## Proof

Proof runs against real Wayne State applications are on a private site, [proof.apps.wayne.edu/preflight](https://proof.apps.wayne.edu/preflight/), behind a Wayne State employee sign-in. What was run, what held and what it caught in Preflight itself is on the public [Proof](proof.md) page.

## Docs

The full documentation lives at [preflight.apps.wayne.edu/docs/](https://preflight.apps.wayne.edu/docs/) on the project site, built from `docs/` by Squire's docs builder. It starts with the overview page; the rest of the manual follows as the pages are written.

- `composer docs` rebuilds `site/docs/` from `docs/`; run it after editing a page.
- `composer docs:check` fails when the built site is stale; `composer ci` runs it.

The pages are committed because the deploy server serves `site/` without building. Every page links back to its Markdown, and the footer stamps the version the docs describe. Cleared for takeoff: the flight manual flies with the aircraft.

The pages wear the front page's flight deck: `docs/_header.html` is the front page's top bar and `docs/theme/preflight.css` maps its palette and B612 type onto the docs kit, with a dark mode taken from the instrument panel. `docs/docs.json` names both under `theme`. Restyle the docs in those two files, never in `site/assets/docs.css` or `bin/docs-site.php`: those are Squire's bytes.

## Related

- [Components](components.md)
- [Shared conventions](conventions.md)
- [Template lint](../guides/template-lint.md)
- [Updating image pins](../guides/image-pins.md)
- [Troubleshooting](../troubleshooting.md)
- [Changelog](../changelog.md)
- [Upgrading](../upgrading.md)
