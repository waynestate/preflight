---
title: Dependency caching
description: Docker Hub images come through GitLab's Dependency Proxy and Composer and npm downloads are cached, so busy pipelines do not get the runner rate limited.
---

# Dependency caching

Every image and package a pipeline downloads is a request to someone else's
server. Docker Hub limits anonymous pulls per address, and a runner that
starts fifty jobs on a busy afternoon can hit that limit, or worse, look like
abuse. This page covers how the components keep those downloads cached:
images through GitLab's Dependency Proxy, Composer and npm packages in the
GitLab cache. Read how the image prefix works, what to set on a GitLab without
the proxy, and how the check keeps it that way. A preflight check is cheapest
when it finds nothing; a cache is cheapest when nobody notices it.

## Images: the image_prefix input

Each component whose image comes from Docker Hub (`proctor`, `php-test`,
`composer-audit`, `sbom`, `pint`, `phpstan`, `eslint`, `secret-detection`,
`package-publish`, `renovate` and `squire-kit`) has an `image_prefix` input.
The job pulls `image_prefix/image`:

| Input | Default |
|---|---|
| `image_prefix` | `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}` |
| `image` | the component's image, for example `composer:2.11.1@sha256:...` |

`CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX` is the top-level group's
[Dependency Proxy](https://docs.gitlab.com/user/packages/dependency_proxy/).
The runner signs in to it on its own, the proxy asks Docker Hub once, and
every later pull of the same digest is served from GitLab. Digest pins still
hold: the proxy serves the exact image the digest names.

`image` is the path after the prefix. Set it to change the image, not the
registry:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/proctor@<sha> # <version>
    inputs:
      image: php:8.5-cli-trixie@sha256:<digest>
```

### On a GitLab or group without the proxy

Set `image_prefix` to Docker Hub itself:

```yaml
    inputs:
      image_prefix: docker.io
```

`docker.io` works for every Docker Hub image. `docker.io/library` also works
for the official images (`php`, `composer`, `node`) but not for
`renovate/renovate` or `zricethezav/gitleaks`. For another registry, put its
host and path in `image_prefix` and the rest in `image`, for example
`image_prefix: registry.example.com/mirror` with `image: php:8.4-cli-trixie@sha256:<digest>`.
The prefix has no trailing slash; the input's pattern refuses one.

### Upgrading from a version without image_prefix

Apps that passed `image: ${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/...` only
to reach the proxy drop that input when they move to this version: the
default now does it, and keeping it would put the prefix in twice.

### Images the proxy cannot serve

The Dependency Proxy serves Docker Hub only. The `a11y` component's Playwright
image (`mcr.microsoft.com`) and the `portability` component's Buildah image
(`quay.io`) are pulled from their own registries and have no `image_prefix`;
the runner's own image cache is what saves those pulls.

## Packages: the cache blocks

Each job that installs packages keeps them in the GitLab cache, inside the
project so GitLab can save and restore them:

| Component | Path | Key |
|---|---|---|
| `php-test` | `.composer-cache/` | fixed per PHP version (`preflight-php-${PHP_VERSION}`) |
| `proctor`, `pint`, `phpstan`, `sbom` | `.composer-cache/` | fixed (`preflight-proctor`, `preflight-pint`, `preflight-phpstan`, `preflight-sbom`) |
| `squire-kit` | `.composer-cache/` | fixed (`preflight-squire-kit`), unchanged |
| `eslint` | `.npm-cache/` | fixed (`preflight-eslint`) |
| `a11y` | `.npm-cache/` | fixed (`preflight-a11y`), unchanged |

`npm-audit` installs nothing, so it keeps no cache of its own. It reads the
app's npm cache instead: key `npm`, path `.cache/npm/` (`npm_config_cache`),
the ones Sourdough's generated pipelines use, with `policy: pull`, so an audit
next to the app's install job never overwrites what that job downloaded.

`COMPOSER_CACHE_DIR` and `NPM_CONFIG_CACHE` point the tools at those paths. The
keys are fixed and installs still resolve from the lock, so a cached
run never installs a stale package: Composer and npm only skip the download.
Every component cache also saves with `when: always`, so a retry after a
dropped download fetches only what is missing.

## Your own jobs

The same pattern fits an app's own jobs, such as `composer-ci` or a front-end
build. Sourdough's app templates ship it:

```yaml
variables:
  IMAGE_PREFIX: "${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}"
  COMPOSER_CACHE_DIR: "$CI_PROJECT_DIR/.cache/composer"

composer-ci:
  image: ${IMAGE_PREFIX}/composer:2.11.1
  cache:
    key: composer
    paths: [.cache/composer/]
    when: always
  script:
    - composer install --no-interaction --no-progress --prefer-dist
    - composer ci
```

## How it stays that way

`tests/check-dependency-cache.sh` (and its `.ps1` twin) runs in Preflight's
`contract` job and fails when:

- a component's image default is on Docker Hub but the component has no
  `image_prefix` input defaulting to the proxy, or a job image skips it;
- a component runs `composer install`, `update`, `require` or
  `create-project`, or `npm ci` or `install`, without a `cache:` block and a
  cache directory;
- Preflight's own `.gitlab-ci.yml` pulls a Docker Hub image without the proxy
  prefix, or passes a component an image that already carries it.

## Related

- [Updating image pins](image-pins.md): how the digests behind `image` are chosen and changed.
- [The php-test component](component-php-test.md): the matrix and its per-version cache.
- [GitLab: Dependency Proxy](https://docs.gitlab.com/user/packages/dependency_proxy/) and [GitLab: caching](https://docs.gitlab.com/ci/caching/).
