---
title: Preflight
description: Preflight is a set of GitLab CI/CD components that give every WSU app the same checks.
---

<div align="center">
  <a href="../index.html"><img src="readme/hero.jpg" width="100%" alt="Preflight's front page: the headline Preflight, 'Every push is cleared for takeoff.', the include block for the php-test component, and the runway mark set in a heading-indicator instrument."></a>
</div>

# Preflight

<div align="center">
  <img src="readme/badges/php.svg" alt="php ^8.3">
  <img src="readme/badges/license.svg" alt="license MIT">
  <img src="readme/badges/components.svg" alt="gitlab ci components: 13">
</div>

**Every push is cleared for takeoff.**

Preflight is a set of GitLab CI/CD components that give every WSU app the
same checks: PROCTOR, PHP tests on each supported version, Composer audit,
an SBOM, Pint, PHPStan and ESLint. One include per component, pinned to a
commit SHA, and the same checklist flies on every push.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@28d9c5994d06c633850d431dcf6ca56c48a96055 # 0.8.0
    inputs:
      test_command: vendor/bin/phpunit
```

## Pick your path

- [Quick start](guides/quick-start.md): wire one component into an app and watch the pipeline run it.
- [Install](install.md): the requirements, the include snippet, and how to verify the pipeline picked the component up.
- [Reference](reference/components.md): every component, with its include example, inputs and defaults.

Preflight 0.7.0; GitLab components are GA on the Free tier since GitLab 17.0; MIT licensed.

Agents: fetch [https://preflight.apps.wayne.edu/llms.txt](https://preflight.apps.wayne.edu/llms.txt) for a machine-readable index of this manual.
