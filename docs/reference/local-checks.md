---
title: Local checks
description: How maintainers build, test and release this project with Docker.
---

# Local checks

How maintainers build, test and release this project with Docker, and the Composer scripts behind the gate. The pre-flight checklist, run from your own desk: run the same gate CI runs before you push anything.

> [!NOTE]
> Maintainers: how to build, test and release this project, and where its data comes from, is in [MAINTAINING.md](https://git.wayne.edu/enterprise-apps/preflight/-/blob/main/MAINTAINING.md) on the canonical repository.

## The full gate

Run the template lint and the fixture tests with Docker:

```sh tab="linux"
docker run --rm -v "$(pwd):/app" -v stack-composer-cache:/tmp/cache -w /app composer:2 composer install
docker run --rm -v "$(pwd):/app" -v stack-composer-cache:/tmp/cache -w /app composer:2 composer ci
```

```powershell tab="windows"
docker run --rm -v "${PWD}:/app" -v stack-composer-cache:/tmp/cache -w /app composer:2 composer install
docker run --rm -v "${PWD}:/app" -v stack-composer-cache:/tmp/cache -w /app composer:2 composer ci
```

The `stack-composer-cache` volume keeps Composer's downloads between runs; Docker creates it the first time.

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
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -v stack-composer-cache:/tmp/cache -w /app composer:2 composer install
docker run --rm -v "$(pwd)/tests/fixture-app:/app" -w /app php:8.4-cli vendor/bin/phpunit
```

## The portability fixtures

Run the portability fixtures with Docker. The check runs the component's own probe in the component's own Buildah image against `tests/portability/app`, once clean and once per flaw, and exits 0 only when the clean build passes every check and each flaw fails the check it targets. It takes about two minutes. `--security-opt seccomp=unconfined` lets Buildah open the user namespace that Docker's default seccomp profile refuses; it grants no capabilities and is not `--privileged`.

```sh tab="linux"
docker run --rm --security-opt seccomp=unconfined -v "$(pwd):/src:ro" -w /src \
  quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb \
  sh tests/check-portability.sh
```

```powershell tab="windows"
pwsh -File tests/check-portability.ps1
```

To run some cases only, set `PORTABILITY_CASES` (for example `-e PORTABILITY_CASES="none sigterm"` on the `docker run`), or pass `-Cases none,sigterm` to the `.ps1`.

## The accessibility gate

The site's pages have an accessibility gate: the `a11y` component's own checker (`templates/a11y/check.mjs`, axe-core in Playwright), run in Docker with the image and versions pinned in `templates/a11y/template.yml`, so no host browser is needed and a local run checks the same way as the pipeline. With no options it checks the front page and every docs page at WCAG 2.2 AA, in light and dark mode at 320 px and 1280 px, with the reflow check, and fails on any violation:

```sh tab="linux"
sh scripts/a11y.sh
```

```powershell tab="windows"
scripts\a11y.ps1
```

Options pick another folder, pages, tags, a running site or a folder for the reports: `--site=DIR --pages='["index.html"]' --tags='["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]' --base-url=URL --report=DIR` (PowerShell: `-Site`, `-Pages`, `-Tags`, `-BaseUrl`, `-Report`). With `--base-url=URL` (or the `A11Y_BASE_URL` environment variable) the gate checks a running site at URL instead of a folder of HTML, as the component's `base_url` input does in CI; `localhost` inside the container is the container itself, so a site on the host is reached as `host.docker.internal`.

## The accessibility fixtures

`tests/check-a11y.sh` (and `tests/check-a11y.ps1`) prove the checker still tells a clean site from a bad one. They run the gate against `tests/a11y-fixtures` at the component's default WCAG 2.1 AA and exit 0 only when the good site passes, the bad site fails with each known flaw named (a missing `lang`, an image with no `alt`, an unlabeled input, weak contrast, a page that scrolls sideways at 320 px, and a palette that fails in dark mode only), a missing page fails with HTTP 404, and a glob that matches nothing stops with a configuration error. They need Docker; the contract job does not run them.

```sh tab="linux"
sh tests/check-a11y.sh
```

```powershell tab="windows"
pwsh -File tests/check-a11y.ps1
```

`tests/check-a11y-inline.sh` (and `.ps1`) checks that the heredoc in the template is a byte-for-byte copy of `templates/a11y/check.mjs`; the contract job runs it. After editing `check.mjs`, run `sh tests/check-a11y-inline.sh --write` (PowerShell: `tests\check-a11y-inline.ps1 -Write`) to copy it into the template.

## The must-fail fixtures

`tests/check-php-test-fails.sh`, `tests/check-phpstan-fails.sh`, `tests/check-pint-fails.sh`, `tests/check-eslint-fails.sh`, `tests/check-secret-detection-fails.sh` and `tests/check-sbom-fails.sh` (each with a `.ps1` twin) prove the `php-test`, `phpstan`, `pint`, `eslint`, `secret-detection` and `sbom` components still fail a bad app and pass a clean one. Each asserts its template keeps the job lines it promises, then runs the component's own commands from its template, in the component's own image, against the clean case (`tests/fixture-app` for the PHP components, `tests/eslint-clean` for eslint, `tests/secret-detection-clean` for secret-detection, `tests/sbom-clean` for sbom) and the must-fail case in its fixture (`tests/php-test-fails`, `tests/phpstan-fails`, `tests/pint-fails`, `tests/eslint-fails`, a copy of the clean fixture carrying a token in `src/config.php` for secret-detection, built at run time so no secret-shaped string is committed, and `tests/sbom-fails`), in a copy in a temp dir. They exit 0 only when the clean case passes and the bad case fails with the expected finding. The `.sh` is the payload of a container; the `.ps1` runs it with Docker. They need Docker; the contract job does not run them.

```sh tab="linux"
docker run --rm -v "$(pwd):/app" -w /app php:8.3-cli-trixie sh tests/check-php-test-fails.sh
docker run --rm -v "$(pwd):/app" -v stack-composer-cache:/tmp/cache -w /app composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 sh tests/check-phpstan-fails.sh
docker run --rm -v "$(pwd):/app" -v stack-composer-cache:/tmp/cache -w /app composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 sh tests/check-pint-fails.sh
docker run --rm -v "$(pwd):/app" -w /app node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da sh tests/check-eslint-fails.sh
docker run --rm --entrypoint sh -v "$(pwd):/app" -w /app zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f tests/check-secret-detection-fails.sh
docker run --rm -v "$(pwd):/app" -v stack-composer-cache:/tmp/cache -e COMPOSER_CACHE_DIR=/tmp/cache -w /app composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 sh tests/check-sbom-fails.sh
```

```powershell tab="windows"
pwsh -File tests/check-php-test-fails.ps1
pwsh -File tests/check-phpstan-fails.ps1
pwsh -File tests/check-pint-fails.ps1
pwsh -File tests/check-eslint-fails.ps1
pwsh -File tests/check-secret-detection-fails.ps1
pwsh -File tests/check-sbom-fails.ps1
```

`tests/check-composer-audit-fails.sh` (and its `.ps1` twin) does the same for `composer-audit`. It asserts the job has no `allow_failure`, no `--ignore-unreachable` and no swallowed exit code, renders the template's own script lines with each case's inputs, and runs them on copies of `tests/fixture-app` (must pass) and the locks in `tests/audit-fixtures`: `advisory` (laravel/framework v9.0.0, must fail naming CVE-2024-52301) and `malware` (aikido/endpoint-test 0.0.1, Aikido's harmless test package, must fail naming it on the malware list) in every `abandoned` mode, and `abandoned`, which must fail only in `fail` mode. composer audit asks Packagist for advisories and filter lists, so it needs the network; offline, the clean case fails, so it never passes by accident. The `must-fail-composer-audit` job runs it in CI. `tests/check-abandoned-input.sh` keeps the offline half (the input's default, regex and flag in the template and the contract) and runs in the contract job.

```sh tab="linux"
docker run --rm -v "$(pwd):/app:ro" -w /app composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 sh tests/check-composer-audit-fails.sh
```

```powershell tab="windows"
pwsh -File tests/check-composer-audit-fails.ps1
```

## The Squire kit checks

`tests/check-renovate-squire-kit.sh` (and `.ps1`) checks the preset's Squire rule: the exact two post-upgrade commands, the kit-files rule, and the `squire_kit_tasks` allow-list the renovate component writes. It compiles the commands for sample upgrades and checks that each one matches an allowed pattern, and that 22 hostile variants (shell operators, `..` paths, another package or tool, an extra flag) match none. `tests/check-squire-kit.sh` (and `.ps1`) checks the `squire-kit` template: the version it reads, the install flags, `squire init --check` and its exit codes. The contract job runs both `.sh` files; the job itself runs on `tests/squire-kit-fixture` in Preflight's own pipeline.

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
- [The a11y component](../guides/component-a11y.md)
- [Shared conventions](conventions.md)
- [Template lint](../guides/template-lint.md)
- [Updating image pins](../guides/image-pins.md)
- [Troubleshooting](../troubleshooting.md)
- [Changelog](../changelog.md)
- [Upgrading](../upgrading.md)
