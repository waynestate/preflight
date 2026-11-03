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
  <img src="readme/badges/components.svg" alt="gitlab ci components: 9">
</div>

**Every push is cleared for takeoff.**

Preflight is a set of GitLab CI/CD components that give every WSU app the
same checks: PROCTOR, PHP tests on each supported version, Composer audit,
an SBOM, Pint, PHPStan and ESLint.

**Not to be confused with:** Preflight is the CI pipeline; it runs Pinstripe's style checks and PROCTOR but sets neither.

Front page: [`site/index.html`](https://github.com/waynestate/preflight/blob/main/site/index.html), a static page; see [`site/README.md`](https://github.com/waynestate/preflight/blob/main/site/README.md).
On Citadel it is served by the raw-PHP deploy layer in [`deploy/`](https://github.com/waynestate/preflight/tree/main/deploy): a Squire kit whose front controller serves `site/` behind HELMET's security headers. For local development, keep serving `site/` directly.

## Where the code lives

The canonical repository is on nougat: [enterprise-apps/preflight](https://nougat.snu.gs/enterprise-apps/preflight). git.wayne.edu and GitHub ([waynestate/preflight](https://github.com/waynestate/preflight)) are read-only mirrors of it.
Open issues and merge requests on nougat, not on the mirrors.
This moves to git.wayne.edu once it has CI runners. Cleared for takeoff from nougat; the mirrors are just other gates.

<details>
<summary><b>Walk round the aircraft</b>: the placards, the flight plan and the flight manual from the front page</summary>
<br>
<div align="center"><img src="readme/gallery.jpg" width="100%" alt="Three crops of the front page on a phone: the cockpit placards ('Seven components, one include each', with the proctor placard), the flight plan ('File a flight plan', the workflow rules and include block), and the flight manual ('Read before flight', a warning that a component is not a lock and a caution that it works on the same instance only)."></div>
</details>

Components are GA on the Free tier since GitLab 17.0. They work only within
the same GitLab instance that hosts this project.
