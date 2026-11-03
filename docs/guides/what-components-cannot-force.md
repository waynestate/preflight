---
title: What the components cannot force
description: An included component is a set of ordinary jobs that the app's own `.gitlab-ci.yml` is merged over.
---

# What the components cannot force

An included component is a set of ordinary jobs. The app's own `.gitlab-ci.yml`
is merged over them, so an app can override a job's keys, skip it with `rules`,
or delete the `include:` line. Preflight makes the safe pipeline the easy one;
it does not lock it. Rollcall is where skipped or weakened gates will show up.
A preflight checklist only works if the pilot reads it. This page lists which
jobs may be allowed to fail and the five project settings that make the gates
harder to skip.

## Which jobs may be allowed to fail

Only `proctor` takes an `allow_failure` input (default `false`). A policy
finding is a warning while an app adopts PROCTOR's rules, so the job may fail
without failing the pipeline during adoption. `composer-audit` has no such
input on purpose: a known advisory must fail the pipeline. The other jobs have
no `allow_failure` input either.

No template adds a global key such as `default:`, `variables:`, `workflow:` or
`stages:`. `tests/check-contract.sh` (and its `.ps1` twin) fails on any
top-level key in a template that is not a job named in `contract/inputs.json`,
so a global key fails `composer ci`.

## Protection checklist

A pilot signs each line of the checklist; the plane does not sign for you.
Five project settings make the gates harder to skip, and every one of them
works on GitLab Community Edition:

- [ ] **Protect the default branch** and require a merge request to change it. Every change to `.gitlab-ci.yml` then
  gets a reviewer. (Code owner approval needs Premium, so on Community Edition the reviewer is whoever merges.)
- [ ] **Protect the release tags.** Protect `*` or the release tag pattern so only maintainers can create or move a
  tag. A component ref is a tag, so whoever can move it controls every pipeline that pins it.
- [ ] **Set merge request approvals to at least one** for changes to the default branch. Approvals are available on
  every tier, but code owner rules within them need Premium, so on Community Edition the approval rests with whoever
  has merge rights: rely on the merger as the reviewer.
- [ ] **Set "Minimum role to use pipeline variables" to `no_one_allowed`** unless the project needs pipeline variables.
  The components take inputs, which are fixed and type checked for the whole run. Self-managed GitLab defaults this
  setting to `maintainer`.
- [ ] **Keep secrets away from fork merge requests.** A fork's merge request pipeline runs the fork's configuration.
  Review a fork's `.gitlab-ci.yml` before running its pipeline, and never give it protected variables.

> [!NOTE]
> These are project settings Preflight cannot create or check, and a read-only
> token drift report was considered and left out on purpose: it would trade a
> token for a warning, and the checklist costs nothing to keep.

## Related

- [When the components run](./when-components-run.md)
- [The job token allowlist](./job-token-allowlist.md)
- [GitHub mirrors](./github-mirrors.md)
- [The `proctor` component](./component-proctor.md)

