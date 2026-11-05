---
title: The portability component
description: Proves the app image meets the twelve-factor boot contract.
---

# The portability component

The portability component proves your app image meets the twelve-factor boot contract: it builds the image, boots it the strict way, and validates it before anything else gets to run it. Like the real pre-flight, it is a list of checks you finish on the ground before you are cleared for takeoff. Add the include below to your app's `.gitlab-ci.yml`, then read what the two jobs check.

## What it checks

Proves the app image meets the twelve-factor boot contract. It builds the image with Buildah (no Docker daemon, no elevated runner), boots it the strict way, and validates it with goss: the health path answers 200 for a foreign Host, the root filesystem and the app root are not writable, the app runs as the declared uid, and each declared writable path is writable. No takeoff without a clean pre-flight.

This is the twelve-factor boot check from ADR-0010: the app must start as a non-root user, write only to its declared paths, and answer its health path for any Host, not just its own.

## Add the include

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/portability@<full-commit-sha> # <tag, once one ships>
    inputs:
      dockerfile: Dockerfile
      context: .
      start_command: php -S 0.0.0.0:8080 -t public
```

> [!NOTE]
> Portability ships in 0.1.4 and later (0.1.3 does not include it), so pin the `0.1.4` tag, or the full commit SHA of a commit at or after it.

> [!WARNING]
> The build job needs a runner that permits user namespaces (Buildah uses unshare for its storage); the run job needs only the project's container registry and an app image that carries curl, sha256sum and tar.

`start_command` is the one input with no default: it is app-specific, so you must set it.

## How the jobs work

The component is two jobs.

`portability-build` builds the image with Buildah, which needs no Docker daemon, and pushes it to the project's container registry. Buildah stores its layers with the vfs driver, which needs no special kernel support and runs in an ordinary container. Both jobs are interruptible and carry `timeout: 30 minutes`.

`portability-run` pulls that image, starts the app as an arbitrary uid, and validates it with goss. In order, the job:

1. Generates the goss file from the template and the inputs. The template is the same file the local checks use (`templates/portability/goss.yaml`); it is inlined in the component because a component only ships its `template.yml` to the including project. The `PORT`, `HEALTH_PATH`, `APP_ROOT` and `UID` placeholders are replaced with the inputs, and one command check per writable path is appended.
2. Downloads goss, pinned by version and checksum (v0.4.10, verified with `sha256sum -c`).
3. Starts the app in the background with `start_command`, then runs `goss validate` against the generated file, retrying the health check until the app answers or `boot_timeout` seconds expire.

goss runs as the app user (uid, gid 0), so the command checks see the same permissions the app has.

### The goss checks

| Check | Command or request | What it asserts |
|-------|--------------------|-----------------|
| Health path | `http://127.0.0.1:{{PORT}}{{HEALTH_PATH}}`, `method: GET`, request header `Host: portability-check.invalid` | The app answers 200 for a foreign Host, not just its own. |
| `root-not-writable` | `test ! -w /` | The app cannot write to the root of the filesystem. |
| `app-root-not-writable` | `test ! -w {{APP_ROOT}}` | The app cannot write to its own root directory. |
| `runs-as-uid` | `test "$(id -u)" = "{{UID}}"` | The app runs as the declared uid, not root. |
| One `writable-...` check per entry of `writable_paths` | `test -w <app_root>/<path>` | Each declared writable path is writable by the app user. |

> [!NOTE]
> goss sends the method as written, so the health check uses upper case `GET`.

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the portability jobs. |
| `image` | string | `$CI_REGISTRY_IMAGE/portability:$CI_COMMIT_SHORT_SHA` | App image the portability-run job starts and validates. The default is what portability-build pushes; GitLab expands the CI variables at job time. |
| `buildah_image` | string | `quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb` | Buildah image for the portability-build job; it builds and pushes the app image. |
| `dockerfile` | string | `Dockerfile` | Dockerfile to build, relative to the context. |
| `context` | string | `.` | Build context, relative to the project root. |
| `app_root` | string | `/app` | Directory inside the image where the app lives. |
| `writable_paths` | array | `["storage", "bootstrap/cache"]` | Paths the app may write to, relative to app_root. Each must be writable by the app user. |
| `port` | number | `8080` | Port the app listens on inside the container. |
| `health_path` | string | `/up` | Path the app must answer 200 on for any Host. |
| `uid` | number | `100123` | Numeric uid the app runs as. The gid is always 0. |
| `start_command` | string | none | Command that starts the app inside the image. It is app-specific, so it is required and has no default. |
| `boot_timeout` | number | `60` | Seconds goss retries the health check while the app boots. |

The default is an immutable tag (`-immutable`) pinned by digest, because the plain version tag can be re-pushed and its old digest removed.

## Verify locally

The goss template is the same file the local checks use. `tests/check-portability.sh` (and its `.ps1` twin) do the placeholder replacement for the fixtures and build and boot the three fixtures under `tests/portability` the strict way; they exit 0 only when `good` passes and both `bad-*` fixtures fail. See [Local checks](../reference/local-checks.md) for the commands.

## Related

- [Include a component twice](include-twice.md): the `job_name` input, and why `portability` keeps its two fixed job names instead.
- [Same instance only](same-instance-only.md): components run only inside the GitLab instance that hosts this project.
- [When the components run](when-components-run.md): the `workflow:rules` block that belongs in the app's own file.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
