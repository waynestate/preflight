---
title: "The npm-audit component | Preflight docs"
description: "Runs `npm audit` on the app's lock file and fails on advisories at or above a severity."
url: https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The npm-audit component[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#the-npm-audit-component)

The front-end half of [composer-audit](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html): this component runs `npm audit` on the app's `package-lock.json` and fails the pipeline on an advisory at or above `audit_level` (`high` by default) in a runtime dependency. Then it prints a full report, dev dependencies included, that never fails. This page shows how to add it, what each input does, and how CREED's severity words map to npm's.

## Include the component[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#include-the-component)

Goal: your app's pipeline fails whenever a locked runtime npm package has a known high or critical advisory. Add the include to your app's `.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/npm-audit@<full commit SHA> # the first tag with npm-audit
    inputs:
      working_dir: .
```

npm-audit is on main and not in a tag yet: pin the commit SHA of the first release that lists it in the [Changelog](https://preflight.apps.wayne.edu/docs/changelog.html).

## Inputs[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `npm-audit` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da` | Docker image for the job: the same Node image and digest the `eslint` component pins. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `working_dir` | string | `.` | Directory that holds `package-lock.json`, relative to the project root. |
| `audit_level` | string | `high` | Lowest severity that fails the job: `low`, `moderate`, `high` or `critical`. `medium` is accepted too and means `moderate` (see Severity words below). |
| `omit_dev` | boolean | `true` | Whether the failing audit leaves dev dependencies out. The full report after it always lists them and never fails. |

Note

The template adds regexes to three inputs: `job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, `working_dir` must match `^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$` and `audit_level` must match `^(low|moderate|medium|high|critical)$`.

## What the job does[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#what-the-job-does)

The job is `interruptible: true` with a `timeout: 10 minutes`. Its script changes into `working_dir`, then:

1. **No lock, nothing to audit.** With no `package-lock.json` (or `npm-shrinkwrap.json`) the job prints `npm-audit: no lock file (package-lock.json or npm-shrinkwrap.json) in <dir>, nothing to audit.` and passes. An app with no front end never goes red.
2. **The gate.** `npm audit --omit=dev --audit-level=<audit_level> --audit=true --offline=false` (no `--omit=dev` when `omit_dev` is `false`). npm exits non-zero on an advisory at or above the level, and the job keeps that exit code.
3. **The full report.** When `omit_dev` is `true`, a second `npm audit` lists every finding, dev dependencies included, and never fails the job. A dev-only finding shows up in the log without stopping the merge.

`npm audit` reads only the lock. Nothing is installed, so no package's install script runs in this job.

Warning

The component carries no `allow_failure` input on purpose: an advisory at or above `audit_level` must fail the pipeline. To let one advisory through while a fix lands, raise `audit_level` for a short time and say why in the merge request, or move the package to a fixed version.

### Why `--audit=true --offline=false` [#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#why-audit-true-offline-false)

An app's own `.npmrc` can carry `audit=false` or `offline=true`. Either one makes `npm audit` skip the request, print `found 0 vulnerabilities` and exit 0: a pass that audited nothing. The two flags override the file, so the job always asks the registry.

### When the registry cannot be reached[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#when-the-registry-cannot-be-reached)

`npm audit` posts the lock's package tree to the registry's audit endpoint, so the job needs outbound HTTPS to the registry (`registry.npmjs.org` unless the app's `.npmrc` names another). When the endpoint cannot be reached, or the registry does not offer one, npm exits non-zero with `audit endpoint returned an error`, and the job adds `npm-audit: the registry's audit endpoint could not be reached or refused the request, so nothing was audited.` It fails rather than passes unchecked. A private registry that proxies npm must also serve npm's audit endpoints (`/-/npm/v1/security/advisories/bulk`, with `/-/npm/v1/security/audits/quick` as npm's fallback), or the job fails on every run.

## Severity words[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#severity-words)

CREED's policy (`rules.audit_severity_threshold` in `policy.json`, read by PROCTOR) and Composer use `low`, `medium`, `high` and `critical`. npm uses `low`, `moderate`, `high` and `critical` (plus `info` and `none`, which this component does not accept: `none` would never fail and `info` fails on notes). The map:

| CREED and Composer | npm (`--audit-level`) |
| --- | --- |
| `low` | `low` |
| `medium` | `moderate` |
| `high` | `high` |
| `critical` | `critical` |

So `audit_level` takes the policy's value as it is: `audit_level: medium` runs `npm audit --audit-level=moderate`, and the log says `failing on moderate or higher`. The default, `high`, matches the stack policy's `audit_severity_threshold`.

## Caching[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#caching)

The job installs nothing, but npm fetches package metadata while it reports. It reads the app's own npm cache: the fixed key `npm` and the path `.cache/npm/` (`npm_config_cache` points there), the ones Sourdough's generated pipelines use, with `policy: pull`. The audit never uploads, so an audit running next to the app's install job cannot overwrite the packages that job just downloaded (D-072). In an app with no npm cache of its own the job simply starts cold.

## Proof[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#proof)

Preflight's own pipeline keeps these promises with the `must-fail-npm-audit` job. It runs this template's own script on fixed locks: lodash 4.17.20 (GHSA-35jh-r3h4-6jhm, high) fails at `high` and `medium` and passes at `critical`, an `.npmrc` that turns the audit off still fails, the same lodash as a dev dependency fails only with `omit_dev: false`, a clean lock and an app with no lock pass, and an unreachable registry fails a clean lock. The pipeline also includes the component on the clean fixture, where it must pass. A smoke detector is only worth the batteries if someone pressed the test button.

## Run it on a schedule[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#run-it-on-a-schedule)

New advisories are published after code is merged. The weekly pipeline schedule from [composer-audit](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html#run-it-on-a-schedule) covers this job too: it carries no `rules:` block, so it runs in scheduled pipelines like any other.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/component-npm-audit.html#related)

- [The composer-audit component](https://preflight.apps.wayne.edu/docs/guides/component-composer-audit.html)
- [The eslint component](https://preflight.apps.wayne.edu/docs/guides/component-eslint.html)
- [Dependency caching](https://preflight.apps.wayne.edu/docs/guides/dependency-caching.html)
