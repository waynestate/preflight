---
title: Deprecating and removing a component
description: How a Preflight component is announced as deprecated, how long its old tag keeps working, and when it may be removed.
---

# Deprecating and removing a component

Apps pin Preflight by tag, so a removal is only fair when it was announced first. This page is the policy: what never changes, what may go and in which release, how the announcement works, and how to find out who still pins a version before anything is removed. A deprecation notice is the preflight checklist for goodbye: read it twice, then take off.

## What never changes

- Published tags are never moved or deleted. An app that pins `component: $CI_SERVER_FQDN/enterprise-apps/preflight/<name>@<version>` keeps resolving that reference, and its pipeline keeps running, for as long as the app wants it.
- A deprecation is a promise with a date, not a mood. The notice names the replacement and the release that removes it, and both parts of the promise must hold.

## What may go, and in which release

An input, a job name or a default that an app may rely on is removed only in a minor release while Preflight is below 1.0, or in a major release after 1.0. The CHANGELOG entry for the removal says what replaces it, so an app that reads the changelog knows where to move.

## How the deprecation is announced

Deprecation comes first, one full release ahead of removal:

- The CHANGELOG gets a `Deprecated:` bullet naming the input, job or component and its replacement.
- The component's guide gets a note at the top of the page naming the replacement and the release that removes it.
- Where the component can, its job log prints one line saying it is deprecated, so the app sees the notice in every pipeline run.

A whole component stays in the repo and in the Catalog for at least 6 months after its deprecation release, even if nobody has pinned it since.

## The Catalog toggle stays on

The CI/CD Catalog toggle is never turned off while any published version is still pinned somewhere in the group. Turning it off deletes the Catalog metadata for every published version ([GitLab: components, unpublishing](https://docs.gitlab.com/ci/components/)), and republishing needs a new release. Whether `component:` includes pinned by SHA keep working afterwards is unverified, so do not rely on it.

To find who still pins a version, search the group for `preflight/<name>@`. Rollcall lists the apps that carry the pin, so the fleet report agrees with the search before the toggle question is even asked.

## Related

- [Upgrading](../upgrading.md)
- [What the components cannot force](what-components-cannot-force.md)
- [GitLab: CI/CD components](https://docs.gitlab.com/ci/components/)
