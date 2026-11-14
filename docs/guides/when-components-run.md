---
title: When the components run
description: The components are ordinary jobs, so they run whenever the app's pipeline runs.
---

# When the components run

The components are ordinary jobs, so they run whenever the app's pipeline
runs. This page shows the `workflow:rules` block that runs them on every merge
request and on pushes to the default branch, and why that block must live in
the app's own file.

## The workflow:rules block

To run the components on every merge request and on pushes to the default
branch, put a `workflow:rules` block in the app's own `.gitlab-ci.yml`:

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@fb73b538f3980292119b5b306ff64383d760a214 # 0.9.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@fb73b538f3980292119b5b306ff64383d760a214 # 0.9.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@fb73b538f3980292119b5b306ff64383d760a214 # 0.9.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@fb73b538f3980292119b5b306ff64383d760a214 # 0.9.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@fb73b538f3980292119b5b306ff64383d760a214 # 0.9.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@fb73b538f3980292119b5b306ff64383d760a214 # 0.9.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@fb73b538f3980292119b5b306ff64383d760a214 # 0.9.0
```

> [!NOTE]
> The `workflow:rules` block must live in the app's own file. A component
> cannot set the pipeline's `workflow:rules` for the project that includes it,
> so the `merge_request_event` rule goes in the app's `.gitlab-ci.yml`.

## Related

- [Install](../install.md)
- [Quick start](./quick-start.md)
- [Include a component twice](./include-twice.md)
- [What the components cannot force](./what-components-cannot-force.md)

