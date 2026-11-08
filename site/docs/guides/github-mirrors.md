---
title: "GitHub mirrors | Preflight docs"
description: "A reusable GitHub Actions workflow runs the same checks for packages mirrored to `github.com/waynestate`."
url: https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# GitHub mirrors[#](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html#github-mirrors)

Preflight's components fly inside one GitLab instance only, so this page shows how a package that is also mirrored to `github.com/waynestate` still gets the same checks: call Preflight's reusable GitHub Actions workflow from the mirror's own `.github/workflows/ci.yml`. Start here, then read [Same instance only](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html) for why the components cannot cross instances.

## Why the mirror needs its own workflow[#](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html#why-the-mirror-needs-its-own-workflow)

Components work only inside one GitLab instance, so a package that is also mirrored to `github.com/waynestate` cannot include them there. For those mirrors, Preflight ships a reusable GitHub Actions workflow that runs the same checks: the package's `composer ci` script on each supported PHP version, plus a Composer audit.

## The workflow just calls `composer ci` [#](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html#the-workflow-just-calls-composer-ci)

Each package keeps its checks in a `ci` script in its `composer.json`; the workflow just calls `composer ci`, so the mirror runs whatever the package already runs on GitLab.

## Call the workflow from your package[#](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html#call-the-workflow-from-your-package)

The workflow lives at `.github/workflows/php-package.yml` in this repo. A mirrored package calls it from its own `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: ['**']
    tags: ['v*', '*.*.*']

jobs:
  ci:
    uses: waynestate/preflight/.github/workflows/php-package.yml@<full commit SHA> # 0.3.0
```

## Pin the include to a commit SHA[#](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html#pin-the-include-to-a-commit-sha)

This workflow ships in the `0.1.1` tag, so pin the full commit SHA of the release tag and keep the tag in a trailing comment. A tag or branch can move; a SHA cannot. PROCTOR's `preflight-pinned` check warns when an include is not pinned to a commit SHA. The Renovate preset (see the Renovate section) proposes the bumps, and they wait for review (the `needs-review` label).

## Workflow inputs[#](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html#workflow-inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `php-versions` | string (JSON array) | `'["8.3","8.4","8.5"]'` | PHP versions to test, lowest first. The audit job runs on the first entry. |
| `ci-command` | string | `composer ci` | The command to run in each PHP version job. |
| `working-directory` | string | `.` | Directory to run the command in, relative to the repository root. |

## Green on both sides[#](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html#green-on-both-sides)

The workflow is committed to this repo (and so to GitLab) but only runs on the GitHub mirror; GitLab ignores `.github/workflows`. A release tag is not done until it is green on both sides. Two cockpits, one checklist.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html#related)

- [Same instance only](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html)
- [Renovate](https://preflight.apps.wayne.edu/docs/guides/renovate.html)
- [Composer audit component](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html)
