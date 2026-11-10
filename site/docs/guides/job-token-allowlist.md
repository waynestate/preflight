---
title: "Keep the job token allowlist short | Preflight docs"
description: "List only the projects an app really needs in its CI/CD job token allowlist, and review the list when a dependency is dropped."
url: https://preflight.apps.wayne.edu/docs/guides/job-token-allowlist.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Keep the job token allowlist short [#](https://preflight.apps.wayne.edu/docs/guides/job-token-allowlist.html#keep-the-job-token-allowlist-short)

This page is for an app that installs private packages from GitLab's package registry. It sets out what belongs in the CI/CD job token allowlist, where the setting lives, and when to review it. Apply the rule once, then repeat the review whenever a dependency is dropped.

## What to list [#](https://preflight.apps.wayne.edu/docs/guides/job-token-allowlist.html#what-to-list)

An app that installs private packages from GitLab's package registry should list only the projects it really needs in its CI/CD job token allowlist (project settings, Settings, CI/CD, Job token permissions), use the fine-grained permissions where they fit, and review the list when a dependency is dropped.

Warning

A leaked job token acts with the triggering user's access.

## When to review [#](https://preflight.apps.wayne.edu/docs/guides/job-token-allowlist.html#when-to-review)

Review the list when a dependency is dropped, and drop any project the app no longer installs from it.

## What Preflight cannot do [#](https://preflight.apps.wayne.edu/docs/guides/job-token-allowlist.html#what-preflight-cannot-do)

This is a project setting, not a file Preflight can create or check. The setting is made in the app's GitLab project settings, so no file in the app's repository sets it for you.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/job-token-allowlist.html#related)

- [What the components cannot force](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html)
- [Install](https://preflight.apps.wayne.edu/docs/install.html)
