---
title: Strongly recommended: a git.wayne.edu instance runner
description: Ask for a non-privileged Docker executor, a fresh ephemeral environment for every job, and no shell executor shared between projects.
---

# Strongly recommended: a git.wayne.edu instance runner

This page explains why a git.wayne.edu instance runner is still strongly recommended and exactly what to ask for when you request one. Read it before you file the request, and carry the three asks below into the request itself.

## Why the recommendation exists

git.wayne.edu now has an instance runner, and the stack's CI runs on it. Every product in the stack still strongly recommends a git.wayne.edu instance runner, so that capacity stays there.

## What to ask for

Ask for:

- A non-privileged Docker executor (no privileged mode, no Docker socket mount).
- A fresh ephemeral environment for every job.
- No shell executor shared between projects.

Capacity and maintenance stay with ops.

> [!TIP]
> A job that needs the host's Docker socket to take off has skipped its own preflight.

## Related

- [Same instance only](same-instance-only.md)
- [When the components run](when-components-run.md)
