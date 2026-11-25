---
title: "When the components run | Preflight docs"
description: "The components are ordinary jobs, so they run whenever the app's pipeline runs."
url: https://preflight.apps.wayne.edu/docs/guides/when-components-run.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# When the components run [#](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html#when-the-components-run)

The components are ordinary jobs, so they run whenever the app's pipeline runs. This page shows the recommended `workflow:rules` block and why it must live in the app's own file. What each pipeline runs is on the [Recommended pipeline shape](https://preflight.apps.wayne.edu/docs/guides/recommended-pipeline-shape.html) page.

## The workflow:rules block [#](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html#the-workflow-rules-block)

To give the app the recommended pipeline shape, put this block in the app's own `.gitlab-ci.yml`:

```yaml
workflow:
  auto_cancel:
    on_new_commit: interruptible
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: never
    - if: $CI_COMMIT_TAG
      variables: { PREFLIGHT_TIER: full }
    - if: $CI_PIPELINE_SOURCE == "schedule" && $PREFLIGHT_TIER == "full"
    - if: $CI_PIPELINE_SOURCE == "schedule"
      variables: { PREFLIGHT_TIER: fast }
    - if: $CI_PIPELINE_SOURCE == "web"
      variables: { PREFLIGHT_TIER: full }
    - if: $CI_COMMIT_BRANCH
      variables: { PREFLIGHT_TIER: fast }
default:
  interruptible: true

include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@b1fa3809495794e98475e9d2c20877a331cd6975 # 0.12.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@b1fa3809495794e98475e9d2c20877a331cd6975 # 0.12.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/composer-audit@b1fa3809495794e98475e9d2c20877a331cd6975 # 0.12.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@b1fa3809495794e98475e9d2c20877a331cd6975 # 0.12.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@b1fa3809495794e98475e9d2c20877a331cd6975 # 0.12.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/phpstan@b1fa3809495794e98475e9d2c20877a331cd6975 # 0.12.0
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/eslint@b1fa3809495794e98475e9d2c20877a331cd6975 # 0.12.0
```

Note

The `workflow:rules` block must live in the app's own file. A component cannot set the pipeline's `workflow:rules` for the project that includes it, so the `merge_request_event` rule goes in the app's `.gitlab-ci.yml`.

## Related [#](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html#related)

- [Install](https://preflight.apps.wayne.edu/docs/install.html)
- [Quick start](https://preflight.apps.wayne.edu/docs/guides/quick-start.html)
- [Include a component twice](https://preflight.apps.wayne.edu/docs/guides/include-twice.html)
- [Recommended pipeline shape](https://preflight.apps.wayne.edu/docs/guides/recommended-pipeline-shape.html)
- [What the components cannot force](https://preflight.apps.wayne.edu/docs/guides/what-components-cannot-force.html)
