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
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@87d9b6fc6b0ed302dd729986525282cd7b567ebd # 0.4.0
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

