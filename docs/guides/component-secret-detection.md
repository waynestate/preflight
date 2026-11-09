---
title: The secret-detection component
description: Scans the checked-out tree for committed secrets with Gitleaks and fails the pipeline when one is found.
---

# The secret-detection component

This page covers the `secret-detection` component: what the job does, how to
include it, and every input it takes. Goal: a committed secret fails the
pipeline before it can ride along in a release. Preflight is named for the
pre-flight check, and this component is the row that makes sure nothing
classified boards the plane.

Version 1 · Category: Security/Secrets · Tags: security,secrets,gitleaks

## What the job does

The component runs [Gitleaks](https://github.com/gitleaks/gitleaks) over the
checked-out tree and fails the pipeline when a rule matches. By default it
runs Gitleaks' built-in rules plus a path allowlist for `vendor/` and
`node_modules/`: Gitleaks scans whatever is checked out, and a CI cache can
restore either tree, so their findings are not our code. Point `config_path`
at your own `.gitleaks.toml` to replace the default, and add the same
`vendor` and `node_modules` path allowlist to your file. Every match is
redacted: the job log and the report carry the rule, the file and the line,
never the value.

The job, in order:

1. Writes the default config to `/tmp` (outside the scanned tree) unless
   `config_path` is set, then runs `gitleaks dir` over the project root with
   `--redact` and `--config`, writing a JSON report to `gitleaks.json` at the
   project root.
2. Exits with Gitleaks' exit code: 0 when the tree is clean, 1 when a rule
   matched.

The report is published as an artifact even when the job fails, so a red
pipeline still shows what was found (redacted). The job is interruptible and
times out after 30 minutes.

## Include the component

Add the include to the app's `.gitlab-ci.yml`, pinned to the full commit SHA
of the release that first ships the component, with the tag in a trailing
comment:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/secret-detection@60314791565a264e97cb210813ef4f3e76512402 # 0.5.0
```

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the job. |
| `job_name` | string | `secret-detection` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f` | Docker image for the job. |
| `image_prefix` | string | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` | Registry path in front of `image`: the job pulls `image_prefix/image`. The default is the group's GitLab Dependency Proxy, so Docker Hub is asked once and GitLab serves the cached copy. Outside a group with the proxy, set `docker.io`. No trailing slash. |
| `config_path` | string | (empty) | Path to a `.gitleaks.toml` config file, relative to the project root. Empty uses the built-in rules plus a path allowlist for `vendor/` and `node_modules/`. When set, your file replaces the default, so add the same `vendor` and `node_modules` path allowlist to it. |
| `allow_failure` | boolean | `false` | Whether the job can fail without failing the pipeline. |

## Allowlist a false positive

Two ways, both reviewed like code:

- **`.gitleaksignore`** at the project root: one fingerprint per line, in the
  form `file:rule:line`. Copy the fingerprint from the job log or the
  `gitleaks.json` artifact. In `dir` mode Gitleaks reads the file without an
  extra flag.
- **A config file**: commit a `.gitleaks.toml` (start from Gitleaks' default
  config and add your own rules and allowlists) and set `config_path` to it.
  Your file replaces the job's default, so it must carry the same path
  allowlist for the dependency trees:

  ```toml
  [allowlist]
  description = "skip dependency trees: vendor and node_modules are not our code"
  paths = ['''(^|/)vendor/''', '''(^|/)node_modules/''']
  ```

> [!NOTE]
> While the stack rolls the component out, `allow_failure: true` keeps the
> pipeline green while a team clears its backlog. The default is `false`:
> once the tree is clean, a new secret fails the pipeline.

## Verify

Push the change. The `secret-detection` job lands in the `test` stage by
default, and a green job means Gitleaks found nothing in the tree.

## Related

- [Quick start](quick-start.md): wire one component into an app and watch the pipeline run it.
- [Install](../install.md): the requirements, the include snippet, and how to verify.
- [Include a component twice](include-twice.md): the `job_name` input in action.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
