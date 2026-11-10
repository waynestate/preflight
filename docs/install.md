---
title: Install
description: Add Preflight's components to an app's .gitlab-ci.yml with one include per component.
---

# Install

Preflight installs as an `include:` in the app's own `.gitlab-ci.yml`, one
line per component, pinned to a commit SHA with the tag in a trailing
comment. A tag or branch can move; a SHA cannot.

## Requirements

- GitLab 17.0 or newer. Components are GA on the Free tier since GitLab 17.0.
- Same instance only. Components work only within the same GitLab instance
  that hosts this project; they cannot be used across instances except by
  mirroring.

## Install

Add the include to the app's `.gitlab-ci.yml`:

```yaml tab="All seven components"
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
```

```yaml tab="One component"
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
    inputs:
      test_command: vendor/bin/phpunit
```

## Verify

Push the change. The components are ordinary jobs, so they run whenever the
app's pipeline runs, and each one lands in the `test` stage by default.
Expected result: the pipeline shows the component's job, and for `php-test`
that is one job per entry of `php_versions`, `8.3`, `8.4` and `8.5` by
default. A green job means the check passed.

## Next steps

- [Quick start](guides/quick-start.md): the same install as numbered steps with expected results.
- [When the components run](guides/when-components-run.md): the `workflow:rules` block that belongs in the app's own file.
- [The php-test component](guides/component-php-test.md): inputs, caching, and trying the next PHP release.
- [The a11y component](guides/component-a11y.md): the accessibility gate for a site's pages, in 0.2.0.
- [The squire-kit component](guides/component-squire-kit.md): the check that a deploy kit still matches its Squire release, in 0.2.0.
- [Reference](reference/components.md): every component, with its inputs and defaults.
- [The inputs contract](guides/inputs-contract.md): what a pin promises your includes, and how to see what moved before you move it.
