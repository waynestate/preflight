---
title: "The a11y component | Preflight docs"
description: "Opens the app's pages in a real browser and fails the pipeline on accessibility violations (axe-core in Playwright)."
url: https://preflight.apps.wayne.edu/docs/guides/component-a11y.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# The a11y component[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#the-a11y-component)

This page covers the `a11y` component: what the job checks, how to include it, every input it takes, and how to roll it out on a site that already has findings. Goal: accessibility is a gate the pipeline runs, not a claim in a README. One include line gives any app or site the same check the stack's own sites run. A pilot walks round the aircraft before every flight; this job walks round every page, in daylight and at night.

Version 1 · Category: Testing/Validation · Tags: accessibility,a11y,wcag,axe-core,playwright

## What the job checks[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#what-the-job-checks)

The job opens each page in a real Chromium browser with [Playwright](https://playwright.dev/) and runs [axe-core](https://github.com/dequelabs/axe-core) on it through [@axe-core/playwright](https://www.npmjs.com/package/@axe-core/playwright). Every rule it applies is axe-core's; Preflight adds no rules of its own except one, below.

- **The standard.** The default tags are `wcag2a`, `wcag2aa`, `wcag21a` and `wcag21aa`: WCAG 2.1 Level AA. The stack follows the ADA Title II rule, which names WCAG 2.1 Level AA, so that is the default; a repo may opt into WCAG 2.2 Level AA by adding `wcag22aa`, the floor WayneUI's own gate and the stack's sites use. Content that meets WCAG 2.2 AA also meets 2.1 AA.
- **Every mode.** Each page is checked once per color scheme (light and dark by default) and once per viewport width (320 px and 1280 px by default), so a dark palette with weak contrast or a phone layout that hides a label is caught.
- **Settled pages.** Every check runs with `prefers-reduced-motion: reduce`, the page's own settled state, so scroll reveals and transitions never hide content from axe-core.
- **Reflow.** At 320 px or narrower, while the tags include `wcag21aa`, the job also checks WCAG 1.4.10 Reflow, which axe-core cannot test: the page must not scroll sideways. A failure is reported as `preflight-reflow` and names the elements where the overflow starts. A wide code block that scrolls inside its own box is fine.
- **Pages that do not load.** A page that answers 404 (or any status of 400 or more), or does not load at all, fails its check.

Warning

An automated check finds only some accessibility failures. A green job means axe-core found nothing it can test; it does not prove the page conforms. Keyboard use, focus order, screen reader output and plain language still need a person. The report counts the items axe-core could not decide ("to review by hand") so that review has a list.

## Include the component[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#include-the-component)

Add the include to the app's `.gitlab-ci.yml`, pinned to a full commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/a11y@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
```

With no inputs, the job serves the `site/` folder on a local port and checks every `.html` file in it at WCAG 2.1 AA.

Note

The a11y component ships in Preflight 0.2.0; 0.1.4 does not include it. Pin that tag's full commit SHA, or the full commit SHA of a commit at or after it.

To hold the stack's floor, WCAG 2.2 AA, and to name the pages:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/a11y@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
    inputs:
      site_dir: site
      pages: ["index.html", "docs/**/*.html"]
      wcag_tags: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]
```

## Inputs[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#inputs)

| Input | Type | Default | What it does |
| --- | --- | --- | --- |
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `a11y` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `mcr.microsoft.com/playwright:v1.65.0-noble@sha256:6e3fb709361521eb27161606e6da6d2674e5e89fa16516cb37d6fdd91372273d` | Playwright image the job runs in (amd64 and arm64). It carries Node and Chromium; its `vX.Y.Z` tag sets the playwright npm version. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline. Set it to `true` while a site fixes its first findings. |
| `site_dir` | string | `site` | Static folder to serve, relative to the project root. Page globs expand in it. A relative path; GitLab refuses the pipeline at creation if it is not. |
| `pages` | array | `["**/*.html"]` | Pages to check, relative to the site root: paths (`index.html`, `docs/`) or globs (`docs/**/*.html`). A glob must match at least one file. |
| `base_url` | string | `""` | Check a running site at this URL instead of serving `site_dir`, for example `$CI_ENVIRONMENT_URL`. Empty serves `site_dir`. |
| `wcag_tags` | array | `["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]` | axe-core tags to run. The default is WCAG 2.1 AA; add `wcag22aa` for WCAG 2.2 AA. |
| `color_schemes` | array | `["light", "dark"]` | Color schemes each page is checked in: `light`, `dark` or `no-preference`. |
| `widths` | array | `[320, 1280]` | Viewport widths in CSS pixels. At 320 or less the job also checks reflow. |
| `playwright_version` | string | `""` | playwright npm version. Empty reads it from the image tag; set it only for an image whose tag does not carry `vX.Y.Z`. |
| `axe_core_version` | string | `4.14.0` | axe-core version, the rules engine. The job fails if a different axe-core ran. |
| `axe_playwright_version` | string | `4.14.0` | @axe-core/playwright version, the bridge to Playwright. Its axe-core range must include `axe_core_version`. |

A page glob uses `**` for any number of folders and `*` inside one folder name. Folders that start with a dot, `node_modules` and `vendor` are skipped. A literal page that is not there fails its check (HTTP 404); a glob that matches nothing stops the job as a configuration error, so a moved docs folder cannot quietly shrink the gate.

## How the job works[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#how-the-job-works)

From `templates/a11y/template.yml`, the job (named by `job_name`) runs in the `test` stage by default, is `interruptible: true`, and has a timeout of 30 minutes. In order:

1. Reads the Playwright version from the image tag (`playwright:v1.65.0-noble` gives `1.65.0`), unless `playwright_version` is set, so the npm package always matches the browsers in the image.
2. Installs `playwright`, `@axe-core/playwright` and `axe-core` at those exact versions with `npm install --ignore-scripts` into a temporary folder outside the project. Nothing is added to the app's `package.json`, and no install script runs.
3. Writes the inputs as JSON and the checker (`templates/a11y/check.mjs`, inlined in the template, because a component ships only its `template.yml`), then runs it from the project root.
4. Serves `site_dir` on a local port (or uses `base_url`), opens each page in each mode, runs axe-core, and writes the reports.

The job exits 0 when every check is clean, 1 when a page has a violation or did not load, and 2 on a tool or configuration error (an unknown color scheme, a glob that matches nothing, a different axe-core than the one pinned).

## Reports[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#reports)

Both reports are written to the project root and kept as artifacts for 30 days, whether the job passes or fails:

- `gl-a11y-junit.xml`, published as a JUnit report: the merge request's test summary lists one test case per page and mode (`docs/index.html dark 320px`), and a failed case carries each rule, its help link and the selectors it hit.
- `gl-a11y-report.json`: the tool versions, tags, modes and every check with its violations (rule id, impact, help, help link, WCAG tags, selectors and axe-core's failure summary) and its count of items to review by hand.

The job log prints one line per page and mode, then the details of every violation. It prints selectors, never page text.

## Roll it out on a site with findings[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#roll-it-out-on-a-site-with-findings)

A site that has never been checked usually has a few findings. Land the gate first, fix the findings, then make it blocking:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/a11y@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
    inputs:
      allow_failure: true
```

While `allow_failure` is `true`, a red job shows as a warning and the pipeline still passes; the reports are written either way. Remove the input (or set it to `false`) once the job is green. Leave a date in a comment so the warning does not become wallpaper.

## Check a running site[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#check-a-running-site)

For pages a static folder cannot hold (a Laravel or raw-PHP app), point the job at a running copy, such as a review app or a pre-production deploy, and list the paths:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/a11y@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
    inputs:
      base_url: $CI_ENVIRONMENT_URL
      pages: ["/", "about", "apply"]
```

`base_url` goes into a job variable, so GitLab expands CI variables in it. Pages are paths under it. Globs still expand in `site_dir`, so with `base_url` and no local folder, list the pages by hand. The job must be able to reach the URL; put it in a stage after the deploy.

## Run it on your desk[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#run-it-on-your-desk)

Preflight's own repository runs this checker locally with `scripts/a11y.sh` (Linux and macOS) or `scripts/a11y.ps1` (Windows), in Docker, with the image and versions pinned in the template. See [Local checks](https://preflight.apps.wayne.edu/docs/reference/local-checks.html).

## Verify[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#verify)

Push the change. The `a11y` job lands in the `test` stage by default, and its last line reads `a11y: clean` when every page passes. Open the merge request's test summary to see each page and mode.

Note

The job needs the npm registry (to install the pinned packages) and, for `base_url`, the site it checks. It needs no token and no Docker socket.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/component-a11y.html#related)

- [Quick start](https://preflight.apps.wayne.edu/docs/guides/quick-start.html): wire one component into an app and watch the pipeline run it.
- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html): check two sites in one project with `job_name`.
- [What the components cannot force](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html): which jobs may be allowed to fail.
- [Troubleshooting](https://preflight.apps.wayne.edu/docs/troubleshooting.html): the a11y job's error messages.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
