---
title: Which hosts the jobs reach
description: Every host a Preflight job or its image pull reaches, by component, for a runner whose network is locked down.
---

# Which hosts the jobs reach

A runner that can reach only the hosts its jobs need cannot send your code to a stranger or pull a tool from one
(BEST_PRACTICES 5.4). This page is the list for Preflight's own components, read from `templates/`: what each job
downloads, and from where. Air traffic control wants a flight plan before it opens the airspace; this is that plan.

> [!NOTE]
> This list covers Preflight's components only. Your app adds its own hosts: a private Composer or npm registry,
> the base images its Dockerfile names, and any service its tests call. Confirm the list against one real pipeline's
> proxy or firewall log before you enforce it, because package hosts move their downloads between CDNs.

## Two places ask

- **The runner host pulls the images.** With the default `image_prefix` (the group's GitLab Dependency Proxy),
  every Docker Hub image comes from the GitLab instance itself, so the runner needs no Docker Hub access. With
  `image_prefix: docker.io`, it needs `registry-1.docker.io`, `auth.docker.io` and
  `production.cloudflare.docker.com`. Two images are not on Docker Hub and never go through the proxy: the
  Playwright image (`mcr.microsoft.com` and its blob hosts, `*.data.mcr.microsoft.com`) and the Buildah image
  (`quay.io`, `cdn.quay.io`, `cdn01.quay.io`, `cdn02.quay.io` and `cdn03.quay.io`).
- **The job container makes the requests in the table below.** Every job also talks to the GitLab instance
  (`$CI_SERVER_FQDN`): the component include, the Git fetch, caches, artifacts and reports.

## By component

| Component | What the job downloads | Hosts (besides the GitLab instance) |
|-----------|------------------------|-------------------------------------|
| `proctor` | `unzip` and `git` with `apt-get`; Composer, by the official installer, checked against its signature; the app's dependencies | `deb.debian.org`, `getcomposer.org`, `composer.github.io`, `repo.packagist.org`, `api.github.com`, `codeload.github.com`, `github.com` |
| `php-test` | The same as `proctor`, once per PHP version | `deb.debian.org`, `getcomposer.org`, `composer.github.io`, `repo.packagist.org`, `api.github.com`, `codeload.github.com`, `github.com` |
| `composer-audit` | Package metadata and the advisory list; it installs nothing | `repo.packagist.org`, `packagist.org` |
| `composer-ci` | The app's dependencies, installed from the lock file | `repo.packagist.org`, `packagist.org`, `api.github.com`, `codeload.github.com`, `github.com` |
| `npm-audit` | npm's bulk advisory lookup; it installs nothing | `registry.npmjs.org` |
| `sbom` | The app's dependencies and the CycloneDX Composer plugin | `repo.packagist.org`, `api.github.com`, `codeload.github.com`, `github.com` |
| `pint` | The app's dependencies (Pint is one of them) | `repo.packagist.org`, `api.github.com`, `codeload.github.com`, `github.com` |
| `phpstan` | The app's dependencies (PHPStan is one of them) | `repo.packagist.org`, `api.github.com`, `codeload.github.com`, `github.com` |
| `eslint` | The app's npm dependencies, with install scripts off | `registry.npmjs.org` |
| `a11y` | `playwright`, `axe-core` and `@axe-core/playwright` at exact versions, scripts off; the browsers are in the image | `registry.npmjs.org` |
| `secret-detection` | Nothing: Gitleaks and its rules are in the image | none |
| `squire-kit` | The Squire release the kit records, by `composer create-project` | `repo.packagist.org`, `api.github.com`, `codeload.github.com`, `github.com` |
| `mysql56-migrate` | `git` and `unzip` with `apt-get` and the Composer 2.11.1 phar (checked by SHA-256) when the image has no Composer; the app's dependencies. The MySQL 5.6.51 service is an image, pulled by the runner | `deb.debian.org`, `getcomposer.org`, `repo.packagist.org`, `api.github.com`, `codeload.github.com`, `github.com` |
| `portability` | Nothing for the probe itself. The build pulls the app's base images and runs its Dockerfile, so it reaches whatever they name | the app's own |
| `package-publish` | The group's Composer registry index and the package's metadata; then the publish request | none |
| `renovate` | Every registry it looks up updates in, and release notes | `registry.npmjs.org`, `repo.packagist.org`, `packagist.org`, `registry-1.docker.io`, `auth.docker.io`, `quay.io`, `mcr.microsoft.com`, `api.github.com`, `github.com` |

Composer fetches a GitHub-hosted package from `api.github.com`, which redirects to `codeload.github.com`; when that
fails it clones from `github.com`. A private Packagist mirror or an HTTP proxy with path rules can narrow those three.

## The list, deduplicated

```
GitLab        the instance ($CI_SERVER_FQDN) and its Dependency Proxy
Composer      repo.packagist.org  packagist.org  getcomposer.org  composer.github.io
GitHub        api.github.com  codeload.github.com  github.com
npm           registry.npmjs.org
Debian        deb.debian.org
Microsoft     mcr.microsoft.com  *.data.mcr.microsoft.com          (a11y image)
Quay          quay.io  cdn.quay.io  cdn01.quay.io  cdn02.quay.io  cdn03.quay.io  (portability image)
Docker Hub    registry-1.docker.io  auth.docker.io  production.cloudflare.docker.com
              (only with image_prefix: docker.io, and for renovate's lookups)
```

Leave out what you do not include: an app without npm needs no `registry.npmjs.org`, and one without `a11y` or
`portability` needs neither Microsoft's nor Quay's hosts. Prefer named hosts to wildcards such as `*.github.com`.

## How this page stays true

`tests/DocsEgressTest.php`, in `composer ci`, fails when a component in `contract/inputs.json` has no row here, when a
template fetches from an `https://` host this page does not name, or when a component's default image comes from a
registry host this page does not name. A new download reaches a tag only with its host on this page.

## Related

- [Dependency caching](dependency-caching.md): the Dependency Proxy and the Composer and npm caches.
- [The instance runner](instance-runner.md): why the stack runs on a git.wayne.edu instance runner.
- [What the components cannot force](what-components-cannot-force.md): the settings that stay yours.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
