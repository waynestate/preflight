---
title: "Strongly recommended: a git.wayne.edu instance runner | Preflight docs"
description: "Ask for a non-privileged Docker executor, a fresh ephemeral environment for every job, and no shell executor shared between projects."
url: https://preflight.apps.wayne.edu/docs/guides/instance-runner.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Strongly recommended: a git.wayne.edu instance runner[#](https://preflight.apps.wayne.edu/docs/guides/instance-runner.html#strongly-recommended-a-git-wayne-edu-instance-runner)

This page explains why a git.wayne.edu instance runner is strongly recommended and exactly what to ask for when you request one. Read it before you file the request, and carry the three asks below into the request itself.

## Why the recommendation exists[#](https://preflight.apps.wayne.edu/docs/guides/instance-runner.html#why-the-recommendation-exists)

Until git.wayne.edu has a runner, CI runs on the GitLab instance that has one, and Preflight and each app must live on or be mirrored to it. A git.wayne.edu instance runner is strongly recommended.

## What to ask for[#](https://preflight.apps.wayne.edu/docs/guides/instance-runner.html#what-to-ask-for)

Ask for:

- A non-privileged Docker executor (no privileged mode, no Docker socket mount).
- A fresh ephemeral environment for every job.
- No shell executor shared between projects.

Capacity and maintenance stay with ops.

Tip

A job that needs the host's Docker socket to take off has skipped its own preflight.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/instance-runner.html#related)

- [Same instance only](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html)
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html)
