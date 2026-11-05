---
title: "What the components cannot force | Preflight docs"
description: "An included component is a set of ordinary jobs that the app's own `.gitlab-ci.yml` is merged over."
url: https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# What the components cannot force[#](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html#what-the-components-cannot-force)

An included component is a set of ordinary jobs. The app's own `.gitlab-ci.yml` is merged over them, so an app can override a job's keys, skip it with `rules`, or delete the `include:` line. Preflight makes the safe pipeline the easy one; it does not lock it. Rollcall is where skipped or weakened gates will show up. A preflight checklist only works if the pilot reads it. This page lists which jobs may be allowed to fail and the five project settings that make the gates harder to skip.

## Which jobs may be allowed to fail[#](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html#which-jobs-may-be-allowed-to-fail)

Only `proctor` takes an `allow_failure` input (default `false`). A policy finding is a warning while an app adopts PROCTOR's rules, so the job may fail without failing the pipeline during adoption. `composer-audit` has no such input on purpose: a known advisory must fail the pipeline. The other jobs have no `allow_failure` input either.

No template adds a global key such as `default:`, `variables:`, `workflow:` or `stages:`. `tests/check-contract.sh` (and its `.ps1` twin) fails on any top-level key in a template that is not a job named in `contract/inputs.json`, so a global key fails `composer ci`.

## Protection checklist[#](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html#protection-checklist)

A pilot signs each line of the checklist; the plane does not sign for you. Five project settings make the gates harder to skip, and every one of them works on GitLab Community Edition:

Note

These are project settings Preflight cannot create or check, and a read-only token drift report was considered and left out on purpose: it would trade a token for a warning, and the checklist costs nothing to keep.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html#related)

- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html)
- [The job token allowlist](https://preflight.apps.wayne.edu/docs/guides/job-token-allowlist.html)
- [GitHub mirrors](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html)
- [The `proctor` component](https://preflight.apps.wayne.edu/docs/guides/component-proctor.html)
