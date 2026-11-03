---
title: Keep the job token allowlist short
description: List only the projects an app really needs in its CI/CD job token allowlist, and review the list when a dependency is dropped.
---

# Keep the job token allowlist short

This page is for an app that installs private packages from GitLab's package registry. It sets out what belongs in the CI/CD job token allowlist, where the setting lives, and when to review it. Apply the rule once, then repeat the review whenever a dependency is dropped.

## What to list

An app that installs private packages from GitLab's package registry should list only the projects it really needs in its CI/CD job token allowlist (project settings, Settings, CI/CD, Job token permissions), use the fine-grained permissions where they fit, and review the list when a dependency is dropped.

> [!WARNING]
> A leaked job token acts with the triggering user's access.

## When to review

Review the list when a dependency is dropped, and drop any project the app no longer installs from it.

## What Preflight cannot do

This is a project setting, not a file Preflight can create or check. The setting is made in the app's GitLab project settings, so no file in the app's repository sets it for you.

## Related

- [What the components cannot force](what-components-cannot-force.md)
- [Install](../install.md)
