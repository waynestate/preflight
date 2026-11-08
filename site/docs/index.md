---
title: "Preflight | Preflight docs"
description: "Preflight is a set of GitLab CI/CD components that give every WSU app the same checks."
url: https://preflight.apps.wayne.edu/docs/
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

[![Preflight's front page: the headline Preflight, 'Every push is cleared for takeoff.', the include block for the php-test component, and the runway mark set in a heading-indicator instrument.](https://preflight.apps.wayne.edu/docs/readme/hero.jpg)](https://preflight.apps.wayne.edu/index.html)

# Preflight[#](https://preflight.apps.wayne.edu/docs/#preflight)

![php ^8.3](https://preflight.apps.wayne.edu/docs/readme/badges/php.svg) ![license MIT](https://preflight.apps.wayne.edu/docs/readme/badges/license.svg) ![gitlab ci components: 13](https://preflight.apps.wayne.edu/docs/readme/badges/components.svg)

**Every push is cleared for takeoff.**

Preflight is a set of GitLab CI/CD components that give every WSU app the same checks: PROCTOR, PHP tests on each supported version, Composer audit, an SBOM, Pint, PHPStan and ESLint. One include per component, pinned to a commit SHA, and the same checklist flies on every push.

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/php-test@b90323b5823287a7840095d0d5f0682aaeedf327 # 0.3.1
    inputs:
      test_command: vendor/bin/phpunit
```

## Pick your path[#](https://preflight.apps.wayne.edu/docs/#pick-your-path)

- [Quick start](https://preflight.apps.wayne.edu/docs/guides/quick-start.html): wire one component into an app and watch the pipeline run it.
- [Install](https://preflight.apps.wayne.edu/docs/install.html): the requirements, the include snippet, and how to verify the pipeline picked the component up.
- [Reference](https://preflight.apps.wayne.edu/docs/reference/components.html): every component, with its include example, inputs and defaults.

Preflight 0.3.0; GitLab components are GA on the Free tier since GitLab 17.0; MIT licensed.

Agents: fetch [https://preflight.apps.wayne.edu/llms.txt](https://preflight.apps.wayne.edu/llms.txt) for a machine-readable index of this manual.
