---
title: Recommended pipeline shape
description: The workflow block the stack recommends: a fast tier on pushes, the full tier nightly, on tags and on manual runs.
---

# Recommended pipeline shape

The shared runners are small, and every app in the stack asks them for
time. Two habits keep the queue honest: one pipeline per push, and the heavy
jobs out of the way until they are needed. Pushes run a fast tier; the full
tier runs nightly, on tags and on manual runs, and a new commit cancels the
pipeline it supersedes.

| Pipeline | Runs |
|---|---|
| Merge request event | Nothing: branch pipelines only, so no duplicates |
| Push to any branch | Fast tier: tests on the latest PHP, audits, secret scan, PROCTOR |
| Nightly schedule with `PREFLIGHT_TIER=full` | Everything |
| Tag | Everything, then the release jobs |
| Manual "Run pipeline" | Everything |

Put this block in the app's own `.gitlab-ci.yml`:

```yaml
workflow:
  auto_cancel:
    on_new_commit: interruptible
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: never
    - if: $CI_COMMIT_TAG
      variables: { PREFLIGHT_TIER: full }
    - if: $CI_PIPELINE_SOURCE == "schedule" && $PREFLIGHT_TIER == "full"
    - if: $CI_PIPELINE_SOURCE == "schedule"
      variables: { PREFLIGHT_TIER: fast }
    - if: $CI_PIPELINE_SOURCE == "web"
      variables: { PREFLIGHT_TIER: full }
    - if: $CI_COMMIT_BRANCH
      variables: { PREFLIGHT_TIER: fast }
default:
  interruptible: true
```

## Marking the heavy jobs

Components that take a `tier` input run in both tiers by default
(`always`). Set `tier: full` on the ones that cost real time, and they run
only when the pipeline sets `PREFLIGHT_TIER` to `full`. A heavy job that
lives in the repo's own file gets the same gate as a rule:
`rules: [{ if: '$PREFLIGHT_TIER == "full"' }]`.

## Release and publish jobs

The block ends with `default: interruptible: true`, so a new commit cancels
every running job. A release or publish job must not stop halfway through:
set `interruptible: false` on it.

## The nightly schedule

Create a pipeline schedule on the default branch (project settings, Build,
Pipeline schedules) that runs nightly with the variable
`PREFLIGHT_TIER=full`. That run covers everything between tags, including
the jobs a push skips.

## Robot schedules

A schedule that exists to run jobs gated by a variable such as `CREED_JOB`
leaves `PREFLIGHT_TIER` unset, so the block gives it the fast tier. The
robot jobs run on their own variable, and the heavy jobs stay off.

## Related

- [When the components run](./when-components-run.md)
- [What the components cannot force](./what-components-cannot-force.md)
- [Troubleshooting](../troubleshooting.md)
