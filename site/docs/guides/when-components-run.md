---
title: "When the components run | Preflight docs"
description: "The components are ordinary jobs, so they run whenever the app's pipeline runs."
url: https://preflight.apps.wayne.edu/docs/guides/when-components-run.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# When the components run[#](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html#when-the-components-run)

The components are ordinary jobs, so they run whenever the app's pipeline runs. This page shows the `workflow:rules` block that runs them on every merge request and on pushes to the default branch, and why that block must live in the app's own file.

## The workflow:rules block[#](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html#the-workflow-rules-block)

To run the components on every merge request and on pushes to the default branch, put a `workflow:rules` block in the app's own `.gitlab-ci.yml`:

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@<full commit SHA> # 0.3.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@<full commit SHA> # 0.3.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@<full commit SHA> # 0.3.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@<full commit SHA> # 0.3.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@<full commit SHA> # 0.3.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@<full commit SHA> # 0.3.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@<full commit SHA> # 0.3.0
```

Note

The `workflow:rules` block must live in the app's own file. A component cannot set the pipeline's `workflow:rules` for the project that includes it, so the `merge_request_event` rule goes in the app's `.gitlab-ci.yml`.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html#related)

- [Install](https://preflight.apps.wayne.edu/docs/install.html)
- [Quick start](https://preflight.apps.wayne.edu/docs/guides/quick-start.html)
- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html)
- [What the components cannot force](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html)
