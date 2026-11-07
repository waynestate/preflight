---
title: "Include a component twice | Preflight docs"
description: "Set the `job_name` input when one project includes the same component more than once."
url: https://preflight.apps.wayne.edu/docs/guides/include-twice.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Include a component twice[#](https://preflight.apps.wayne.edu/docs/guides/include-twice.html#include-a-component-twice)

Goal: run the same component more than once in one project, for example in a monorepo with two apps, and keep the two jobs separate. Set the `job_name` input on each include, as shown below.

## Set `job_name` [#](https://preflight.apps.wayne.edu/docs/guides/include-twice.html#set-job-name)

Every component takes a `job_name` input, whose default is the job's usual name. Set it when one project includes the same component more than once, for example in a monorepo with two apps; without it the two jobs would share a name and merge into one.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@<full commit SHA> # <tag>
    inputs:
      working_dir: app
      job_name: pint-app
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/pint@<full commit SHA> # <tag>
    inputs:
      working_dir: admin
      job_name: pint-admin
```

Expected: the pipeline runs two separately named jobs, `pint-app` and `pint-admin`, instead of two jobs that merge into one.

Note

`job_name` ships in 0.1.4, so pin 0.1.4 or a SHA at or after that release. `portability` gained it with its one-job form, in the first release after 0.1.4.

## Another use: the next PHP release[#](https://preflight.apps.wayne.edu/docs/guides/include-twice.html#another-use-the-next-php-release)

Including a component twice is also how you try a PHP release before it is supported. Include `php-test` a second time for the release that is not supported yet, name that job, and let it fail. The name is what lets your own `.gitlab-ci.yml` loosen only that job:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@<full commit SHA> # <tag>
    inputs:
      php_versions: ["8.6"]
      job_name: php-test-next
      # While 8.6 only has release candidate images, name the tag: php:${PHP_VERSION}-rc-cli-trixie
      # image: "php:${PHP_VERSION}-rc-cli-trixie"

php-test-next:
  allow_failure: true
```

A red `php-test-next` job is an early warning, not a stop. Drop the `allow_failure` and move the version into the main `php_versions` list once the release is supported (the supported versions follow `policy.json`).

## Related[#](https://preflight.apps.wayne.edu/docs/guides/include-twice.html#related)

- [The php-test component](https://preflight.apps.wayne.edu/docs/guides/component-php-test.html): inputs, caching, and the full next-release example.
- [The portability component](https://preflight.apps.wayne.edu/docs/guides/component-portability.html): include it once per app image, each with its own `job_name`.
- [When the components run](https://preflight.apps.wayne.edu/docs/guides/when-components-run.html): the `workflow:rules` block that belongs in the app's own file.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its inputs and defaults.
