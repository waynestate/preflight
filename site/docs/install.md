---
title: "Install | Preflight docs"
description: "Add Preflight's components to an app's .gitlab-ci.yml with one include per component."
url: https://preflight.apps.wayne.edu/docs/install.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Install[#](https://preflight.apps.wayne.edu/docs/install.html#install)

Preflight installs as an `include:` in the app's own `.gitlab-ci.yml`, one line per component, pinned to a commit SHA with the tag in a trailing comment. A tag or branch can move; a SHA cannot.

## Requirements[#](https://preflight.apps.wayne.edu/docs/install.html#requirements)

- GitLab 17.0 or newer. Components are GA on the Free tier since GitLab 17.0.
- Same instance only. Components work only within the same GitLab instance that hosts this project; they cannot be used across instances except by mirroring.

## Install[#](https://preflight.apps.wayne.edu/docs/install.html#install-1)

Add the include to the app's `.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
```

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      test_command: vendor/bin/phpunit
```

## Verify[#](https://preflight.apps.wayne.edu/docs/install.html#verify)

Push the change. The components are ordinary jobs, so they run whenever the app's pipeline runs, and each one lands in the `test` stage by default. Expected result: the pipeline shows the component's job, and for `php-test` that is one job per entry of `php_versions`, `8.3`, `8.4` and `8.5` by default. A green job means the check passed.

## Next steps[#](https://preflight.apps.wayne.edu/docs/install.html#next-steps)

- [Quick start](https://preflight.apps.wayne.edu/docs/guides/quick-start.html): the same install as numbered steps with expected results.
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html): the `workflow:rules` block that belongs in the app's own file.
- [The php-test component](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html): inputs, caching, and trying the next PHP release.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
