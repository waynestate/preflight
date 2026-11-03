---
title: "Same instance only | Preflight docs"
description: "Components work only inside the GitLab instance that hosts this project."
url: https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Same instance only[#](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html#same-instance-only)

This page tells you where Preflight components can run, and what to do when your app is not on the right instance. Read it before you add an include if your app lives on a different GitLab than this project.

## The rule[#](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html#the-rule)

Components work only inside the GitLab instance that hosts this project.

Warning

Components cannot be used across instances except by mirroring.

Every include in this manual takes the form `component: $CI_SERVER_FQDN/enterprise-apps/preflight/<name>@<full commit SHA>`. The path is built from `$CI_SERVER_FQDN`, the instance the pipeline runs on, so the component must be resolvable on that same instance.

## What that means for your app[#](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html#what-that-means-for-your-app)

- Your app must live on the same GitLab instance that hosts this project; if it does not, the components cannot run here.
- Until git.wayne.edu has a runner, CI runs on the GitLab instance that has one, and Preflight and each app must live on or be mirrored to it. See [Strongly recommended: a git.wayne.edu instance runner](https://preflight.apps.wayne.edu/docs/guides/instance-runner.html).
- A package that is also mirrored to `github.com/waynestate` cannot include the components there, because GitHub is not a GitLab instance at all. For those mirrors, Preflight ships a reusable GitHub Actions workflow that runs the same checks: the package's `composer ci` script on each supported PHP version, plus a Composer audit. See [GitHub mirrors](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html).

## Mirroring is the only exception[#](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html#mirroring-is-the-only-exception)

The one way to use the components on another GitLab instance is mirroring: mirror this project to that instance, so the components live there too. Everything else in this manual assumes the app and the components share an instance.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/same-instance-only.html#related)

- [GitHub mirrors](https://preflight.apps.wayne.edu/docs/guides/github-mirrors.html): the reusable GitHub Actions workflow for packages mirrored to `github.com/waynestate`.
- [Strongly recommended: a git.wayne.edu instance runner](https://preflight.apps.wayne.edu/docs/guides/instance-runner.html): where CI runs until git.wayne.edu has a runner.
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html): the `workflow:rules` block that belongs in the app's own file.
