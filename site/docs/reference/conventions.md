---
title: "Shared conventions | Preflight docs"
description: "The conventions the stack shares: Composer vendor, license, PHP floor and JavaScript installs."
url: https://preflight.apps.wayne.edu/docs/reference/conventions.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Shared conventions [#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#shared-conventions)

This page lists the conventions the stack shares: Composer vendor, license, PHP floor and JavaScript installs. Check a package against the table when you set one up or review one, so every project starts from the same baseline.

## Conventions [#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#conventions)

| Convention | Value |
| --- | --- |
| Composer vendor | `waynestate/` |
| License | MIT |
| PHP floor | `^8.3` |

Preflight itself ships these values in its `composer.json`: `waynestate/preflight` under the MIT license, requiring `php: ^8.3`.

## JavaScript installs [#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#javascript-installs)

JavaScript components install with `npm ci --ignore-scripts`. The job carries no token beyond `CI_JOB_TOKEN` (BEST_PRACTICES.md 4.12).

## The Preflight component line [#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#the-preflight-component-line)

Every Preflight job prints a `Preflight component <name> <version> (ref <reference>, sha <sha>)` line as its first command, before anything else runs. When a job misbehaves, read that line to see which Preflight release produced it: `<name>` is the component (for example `php-test`), `<version>` is the tag of the pinned release when the include is pinned by tag, `<reference>` is the ref the include points at, and `<sha>` is the commit SHA of the component template that ran. An include pinned by commit SHA shows that SHA in the line. The line needs GitLab 18.7 or later; on an older instance, pipeline creation fails on the unknown `spec: component:` key, so upgrade GitLab or pin an older Preflight tag.

## Related [#](https://preflight.apps.wayne.edu/docs/reference/conventions.html#related)

- [Updating image pins](https://preflight.apps.wayne.edu/docs/guides/image-pins.html): why component images are digest-pinned and how to change a pin.
- [Template lint](https://preflight.apps.wayne.edu/docs/guides/template-lint.html): the unsafe CI patterns `composer ci` scans for before the fixture tests.
