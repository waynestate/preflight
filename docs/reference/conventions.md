---
title: Shared conventions
description: The conventions the stack shares: Composer vendor, license, PHP floor and JavaScript installs.
---

# Shared conventions

This page lists the conventions the stack shares: Composer vendor, license,
PHP floor and JavaScript installs. Check a package against the table when you
set one up or review one, so every project starts from the same baseline.

## Conventions

| Convention | Value |
|------------|-------|
| Composer vendor | `waynestate/` |
| License | MIT |
| PHP floor | `^8.3` |

Preflight itself ships these values in its `composer.json`:
`waynestate/preflight` under the MIT license, requiring `php: ^8.3`.

## JavaScript installs

JavaScript components install with `npm ci --ignore-scripts`. The job carries
no token beyond `CI_JOB_TOKEN` (BEST_PRACTICES.md 4.12).

## Related

- [Updating image pins](../guides/image-pins.md): why component images are digest-pinned and how to change a pin.
- [Template lint](../guides/template-lint.md): the unsafe CI patterns `composer ci` scans for before the fixture tests.
