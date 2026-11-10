---
title: "Quick start | Preflight docs"
description: "Wire one Preflight component into an app and watch the pipeline run it."
url: https://preflight.apps.wayne.edu/docs/guides/quick-start.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Quick start [#](https://preflight.apps.wayne.edu/docs/guides/quick-start.html#quick-start)

This quick start adds the `php-test` component to an app, the same way the front page shows it. Every other component installs the same way: one include, pinned to a commit SHA.

1. **Check the requirements.** Your GitLab must be 17.0 or newer (components are GA on the Free tier since GitLab 17.0), and the app must live on the same GitLab instance that hosts this project. Expected: both true, or the components cannot run here.
2. **Add the include** to the app's `.gitlab-ci.yml`:
   ```yaml
   include:
     - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@435665959434e5b5adca563c34762bd7061a6b8a # 0.7.0
     inputs:
       test_command: vendor/bin/phpunit
   ```
   Expected: the file includes the component pinned to a full commit SHA, with the tag in a trailing comment. A tag or branch can move; a SHA cannot.
3. **Commit and push** the change:
   ```sh
   git push
   ```
   Expected: the next pipeline runs the `php-test` jobs, one per entry of `php_versions`, `8.3`, `8.4` and `8.5` by default, each in the `test` stage.
4. **Read the result.** Each job installs the app's dependencies, caches Composer downloads in `.composer-cache/`, and runs the test command. Expected: a green matrix, meaning the app passes on every supported PHP version.

## What you built [#](https://preflight.apps.wayne.edu/docs/guides/quick-start.html#what-you-built)

Your app now runs the same PHP tests on each supported PHP version that every WSU app runs, from one pinned include. Add the remaining components the same way, one include each.

## Next steps [#](https://preflight.apps.wayne.edu/docs/guides/quick-start.html#next-steps)

- [Install](https://preflight.apps.wayne.edu/docs/install.html): requirements, the full include, and how to verify.
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html): the `workflow:rules` block that keeps the checks on merge requests and the default branch.
- [The php-test component](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html): inputs, caching, and trying the next PHP release without breaking the pipeline.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
