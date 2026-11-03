---
title: "Shared conventions | Preflight docs"
description: "The conventions the stack shares: Composer vendor, license, PHP floor and JavaScript installs."
url: https://preflight.apps.wayne.edu/docs/reference/conventions.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Shared conventions[#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#shared-conventions)

This page lists the conventions the stack shares: Composer vendor, license, PHP floor and JavaScript installs. Check a package against the table when you set one up or review one, so every project starts from the same baseline.

## Conventions[#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#conventions)

| Convention | Value |
| --- | --- |
| Composer vendor | `waynestate/` |
| License | MIT |
| PHP floor | `^8.3` |

Preflight itself ships these values in its `composer.json`: `waynestate/preflight` under the MIT license, requiring `php: ^8.3`.

## JavaScript installs[#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#javascript-installs)

JavaScript components install with `npm ci --ignore-scripts`. The job carries no token beyond `CI_JOB_TOKEN` (BEST_PRACTICES.md 4.12).

## Related[#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#related)

- [Updating image pins](https://preflight.apps.wayne.edu/docs/guides/image-pins.html): why component images are digest-pinned and how to change a pin.
- [Template lint](https://preflight.apps.wayne.edu/docs/guides/template-lint.html): the unsafe CI patterns `composer ci` scans for before the fixture tests.
