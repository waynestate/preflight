---
title: Template lint
description: `composer ci` scans the templates for unsafe CI patterns before the fixture tests.
---

# Template lint

This page lists the unsafe CI patterns the template lint catches and how to
allowlist a known warning. Run `composer ci` to see the lint, which runs
before the fixture tests.

## What it runs

`composer ci` runs `bin/lint-templates` before the fixture tests. The lint
scans `templates/**/*.yml` and `.github/workflows/*.yml` for unsafe CI
patterns.

## Rules

| Rule | Catches |
|------|---------|
| `privileged` | `privileged: true` |
| `dind-service` | Docker-in-Docker services |
| `docker-sock` | references to `docker.sock` |
| `kaniko-image` | Kaniko images |
| `unpinned-action` | GitHub `uses:` entries that are not pinned to a 40-character SHA |
| `image-no-tag` | image references with no tag |
| `image-latest` | image references with `latest` |
| `image-no-digest` | a warning for a tagged image that is not pinned by digest |

The container-build rules (`privileged`, `dind-service`, `docker-sock` and
`kaniko-image`) are explained in BEST_PRACTICES.md 4.17.

## Allowlist a known warning

Known warnings can be allowlisted in `lint-allow.yml`. Each entry needs
`file`, `rule` and `reason`; the reason is required so an allowlist entry is
a reviewed decision, not a silence. The preflight checklist checks the
checklist.

## Related

- [Updating image pins](image-pins.md): why component images are digest-pinned and how to change a pin.
- [Shared conventions](../reference/conventions.md): Composer vendor, license, PHP floor and JavaScript installs.
