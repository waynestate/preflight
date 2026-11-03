---
title: The sbom component
description: Generates a CycloneDX SBOM, validates it, and publishes it as an artifact.
---

# The sbom component

This page shows how to add the `sbom` component to an app's `.gitlab-ci.yml`: it generates a CycloneDX SBOM with `cyclonedx/cyclonedx-php-composer`, validates it, and publishes it as an artifact. The SBOM is the aircraft's parts manifest (nothing flies that is not on the list); start with the include, then read what the job does and which inputs it takes.

## Include the component

Add the include to the app's `.gitlab-ci.yml`, pinned to a commit SHA with the tag in a trailing comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/sbom@79029cc2300702d0d450c42cc699e12af1b731f8 # 0.1.4
    inputs:
      output: sbom.cdx.json
```

A tag or branch can move; a SHA cannot.

## What the job does

The job lands in the `test` stage by default, is `interruptible: true`, and has a `timeout: 30 minutes`. It runs four steps:

1. Install the app's dependencies:

   ```sh
   composer install --no-interaction --no-progress --prefer-dist
   ```

   The default image is a composer image, which already ships Composer, so no install step for Composer itself is needed.

2. Allow the CycloneDX plugin:

   ```sh
   composer global config --no-plugins allow-plugins.cyclonedx/cyclonedx-php-composer true
   ```

3. Install the plugin globally:

   ```sh
   composer global require cyclonedx/cyclonedx-php-composer:^6.2
   ```

   The plugin is installed globally, so the app's `composer.json` is never touched.

4. Generate the SBOM. `--validate` fails the job on an invalid SBOM:

   ```sh tab="omit_dev true (default)"
   composer CycloneDX:make-sbom --output-format=JSON --output-reproducible --validate --omit=dev --output-file=sbom.cdx.json
   ```

   ```sh tab="omit_dev false"
   composer CycloneDX:make-sbom --output-format=JSON --output-reproducible --validate --output-file=sbom.cdx.json
   ```

   `--omit=dev` is present only when `omit_dev` is `true`; `--output-file` takes the `output` input (default `sbom.cdx.json`).

## Artifacts

The job publishes the SBOM file as an artifact:

```yaml
artifacts:
  paths:
    - sbom.cdx.json
  expire_in: 30 days
```

The path is the `output` input, and the artifact expires in 30 days.

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `sbom` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc` | Docker image for the job. |
| `omit_dev` | boolean | `true` | Whether to omit dev dependencies from the SBOM. |
| `output` | string | `sbom.cdx.json` | Path of the SBOM file to publish, relative to the project root. |

`job_name` must match `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`.

## Verify

Push the change. The components are ordinary jobs, so the `sbom` job runs whenever the app's pipeline runs, in the `test` stage by default. A green job means the SBOM was generated, validated, and published.

## Related

- [The composer-audit component](component-composer-audit.md): the companion dependency check.
- [Include a component twice](include-twice.md): the `job_name` input when one project includes the same component more than once.
- [When the components run](when-components-run.md): the `workflow:rules` block that belongs in the app's own file.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
