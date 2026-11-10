---
title: The portability component
description: Proves the app image runs the way OpenShift, Coolify and plain Docker run it, not only on Citadel.
---

# The portability component

The portability component proves your app image runs anywhere a container platform runs it: OpenShift, Coolify, plain Docker, and Citadel too. It builds the image, boots it twice side by side as a stranger (an arbitrary uid with no name, in group 0, with no capabilities), and runs the six checks from ADR-0010 plus the image's own HEALTHCHECK. Like the real pre-flight, it is a list you finish on the ground: if one light is red, nobody taxis.

## What it checks

The strict boot comes first, because every other check stands on it. Then the seven checks, each reported on its own line.

| Check | What it does | What a failure usually means |
|-------|--------------|------------------------------|
| `strict-boot` | Starts the image as `uid:0` (default `100123:0`) with no `/etc/passwd` entry and every capability dropped. Fails if the app root is writable by that user, if a writable path is missing or not writable by group 0, if the second replica does not listen on the port its `port_env` variable names, or if the app wrote anywhere outside `writable_paths` and `runtime_paths` while it ran (what a read-only root filesystem would refuse). | The image expects root, a named user, a fixed port, or writes caches next to the code. |
| `health` | Asks for `health_path` with a bare IP address in `Host` (`Host: <ip>:<port>`), no forwarded headers, at the job's own address, and expects 200. That is what a platform's probe sends. | Trusted-host lists, HTTPS redirects, sessions or auth run before the health route. |
| `env-only` | Fails on a `.env` file or a Laravel config cache (`bootstrap/cache/config.php`) baked into the image; the app must boot on the `env` input alone. | Config was copied or cached at build time. |
| `forwarded-headers` | Requests `probe_path` twice: plain, then with forged `X-Forwarded-Host`, `-Proto`, `-Port` and the `identity_header`, sent from an untrusted peer. Fails if the status or `Location` changes or a forged value shows up in the answer. | The app trusts every proxy, so anyone can set its host, scheme or user. |
| `logs` | Fails if nothing reached stdout or stderr during the run, or if anything was written under `logs_path` (default `storage/logs`). | Logs go to files that vanish with the container. |
| `session-hop` | Signs in on replica A with `session_login_path`, then sends that cookie to replica B's `session_check_path` and expects 200. The replicas have separate disks. | Sessions live in local files instead of a shared store or a signed cookie. |
| `sigterm` | Sends SIGTERM to the main process and expects it to exit by itself within `stop_timeout` seconds, as PID 1 must. | The process has no SIGTERM handler (PID 1 ignores the signal by default), or the handler hangs. |
| `healthcheck` | Runs the image's own `HEALTHCHECK` command, if it declares one, inside replica A as the app's uid with the same environment, up to three times two seconds apart, and expects exit 0. Fails when the command exits non-zero, or when the image declares no HEALTHCHECK and `require_healthcheck` is true. | The image's own health command fails, so Docker and Coolify would mark the container unhealthy. |

The job prints one `portability: <check>: problem: ...` line per problem as it finds it, then a summary with `pass`, `FAIL` or `skipped` for every check, and passes only when every check that ran passed.

## Add the include

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/portability@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
    inputs:
      env: ["APP_KEY=${PORTABILITY_APP_KEY}", "APP_URL=https://myapp.example.edu", "SESSION_DRIVER=cookie", "LOG_CHANNEL=stderr"]
      session_login_path: /_portability/login
      session_check_path: /_portability/me
```

> [!NOTE]
> The one-job component on this page ships in 0.2.0. 0.1.4 carries an earlier two-job version (`portability-build` and `portability-run`, checked with goss); see [Upgrading](../upgrading.md). Pin the full commit SHA of the release tag you use.

With no `start_command`, the job runs the image's own `ENTRYPOINT` and `CMD`, exactly as the platforms do. An Apache image (Squire's portable image, a Sourdough or WELD app) needs no `start_command` shim for Buildah: the job gives each replica stdio its uid owns and a process group of its own, as a container runtime does (see [What the job emulates](#what-the-job-emulates)). Put secrets such as `APP_KEY` in CI/CD variables and name them in `env`: `$NAME` and `${NAME}` in `env` and `build_args` values are replaced from the job's variables.

> [!WARNING]
> The runner must allow user namespaces, which Buildah's chroot isolation uses. Ordinary unprivileged Docker-executor runners do; no privileged mode, Docker-in-Docker or registry is needed.

### A sign-in route for session-hop

`session-hop` needs a GET route that signs in a test user and one that answers 200 only when signed in. Enable them with an environment variable that only this job sets, so they never exist in production. In Laravel (and a Sourdough or WELD app):

```php
if (env('PORTABILITY_PROBE') === 'yes') {
    Route::middleware('web')->group(function () {
        Route::get('/_portability/login', function () {
            Auth::login(User::firstOrCreate(['email' => 'portability@example.invalid'], ['name' => 'Portability', 'password' => Str::random(40)]));

            return 'signed in';
        });
        Route::get('/_portability/me', fn () => Auth::check() ? 'ok' : abort(401));
    });
}
```

Add `"PORTABILITY_PROBE=yes"` to `env`. An app with no sign-in leaves `session-hop` out of `checks` on purpose; the other checks still run.

### A shared database for session-hop

An app that keeps its sessions in a database (WELD does) needs both replicas to reach the same store. The `services` input starts one as a GitLab service container, which the replicas reach by its alias exactly as the job script does:

```yaml
include:
  - component: $CI_SERVER_FQDN/enterprise-apps/preflight/portability@30dd7094089931015ec8754fb321e17659749f05 # 0.6.0
    inputs:
      services: [{ name: "mysql:8.4.7@sha256:<digest>", alias: db, variables: { MYSQL_ROOT_PASSWORD: "portability", MYSQL_DATABASE: "app" } }]
      env: ["APP_KEY=${PORTABILITY_APP_KEY}", "DB_CONNECTION=mysql", "DB_HOST=db", "DB_DATABASE=app", "DB_USERNAME=root", "DB_PASSWORD=portability", "SESSION_DRIVER=database", "LOG_CHANNEL=stderr"]
      session_login_path: /_portability/login
      session_check_path: /_portability/me
```

Replace `<digest>` with the digest of the image you actually pull; never copy a placeholder pin into a pipeline. Two things to know about the service:

- The database has to accept connections before the replicas boot. The probe's `boot_timeout` covers that wait, or a `start_command` can run migrations first. A Laravel app needs its `sessions` table, so its `start_command` runs `php artisan migrate --force` before it serves.
- The runner is arm64, so the service image must be multi-arch. `mysql:8.4` is; `mysql:5.6` is not.

## How the job works

The component is one job, named by `job_name` (default `portability`). It runs in the Buildah image, pinned by digest, with `STORAGE_DRIVER=vfs` and `BUILDAH_ISOLATION=chroot`, `interruptible: true` and `timeout: 30 minutes`. In order, it:

1. Builds the image with `buildah bud`, from `dockerfile` in `context`, with `build_args`. It builds with `--format docker`, because Buildah's default OCI format drops the image's HEALTHCHECK and the docker format keeps it. Nothing is pushed: the image stays in the job's own storage.
2. Reads the image's `ENTRYPOINT` and `CMD`, makes two copies of its filesystem (replicas A and B) and runs the static parts of `strict-boot` and `env-only` on them.
3. Starts both replicas with `buildah run --user <uid>:0 --cap-drop=ALL` and the `env` input, each through a small launcher that gives it its own stdio and session; B gets `port + 1` through `port_env`.
4. Waits up to `boot_timeout` seconds for each replica's health path, then runs `health`, `env-only`, `forwarded-headers`, `session-hop`, `logs` and `sigterm` with curl.
5. Stops both replicas and compares what changed on disk against `writable_paths` and `runtime_paths`.

The probe is `templates/portability/probe.sh`, inlined in the template byte for byte, because a component ships only its `template.yml`. The inputs reach it through a quoted heredoc as data; nothing in them is run except `start_command`.

### Why Buildah

The old runner allowed no Docker-in-Docker, and a privileged runner is a key to the building. Buildah is maintained by Red Hat, builds from a Dockerfile with no daemon, and can also run the image it built, as any uid, with no capabilities, inside an ordinary job. kaniko builds but cannot run a container, and Google archived it in 2025. A GitLab `services:` entry runs an image but cannot set its uid or drop its capabilities, and needs the image pushed to a registry first. Buildah needs neither a push nor a second job.

### What the job emulates

The checks run in an unprivileged job, so a few things are emulated rather than enforced by a kernel. Each one fails the same apps the real thing would.

- **Read-only root.** The image is not mounted read-only; the job looks for files written outside the allowed paths after the run. A write is caught, not refused.
- **PID 1.** `buildah run` starts no PID namespace, so the main process is not PID 1. The job checks that it handles SIGTERM, and fails it when it dies of the signal's default action, which PID 1 would ignore.
- **No new privileges.** Every capability is dropped, but `buildah run` has no `no-new-privileges` flag. The uid has no passwd entry, so set-uid tools have little to grab.
- **Networking.** Both replicas share the job's network namespace; the second one listens on `port + 1`.
- **Stdio and process group.** On its own, `buildah run` differs from every container runtime twice. It hands the app stdout and stderr pipes owned by root, so an app running as the uid cannot reopen them (Apache fails with `could not open error log file /proc/self/fd/2`). And it starts no session, so the app shares a process group with `buildah-chroot-exec`, which runs as the same uid and SIGKILLs the app when the app signals its own group on SIGTERM (Apache's graceful stop does). runc and CRI-O do neither. So the job starts each replica through a launcher: it pipes stdout and stderr through `cat`, on a pipe the uid owns, then execs the app through `setsid`, keeping its pid, so the `sigterm` check still signals the app itself. The launcher uses the Buildah image's own `bash`, `setsid` and `cat` (its `/usr`, bind-mounted read-only at `/.preflight/usr` for the run only), so the app image needs none of them and nothing is written into it.

> [!NOTE]
> Before 0.5.0 an Apache image needed a `start_command` shim such as `exec setsid bash -c 'exec > >(exec cat) 2>&1; exec <entrypoint>'`. Remove it when you upgrade: the job now does both itself, and a `setsid` inside the launcher's session forks the app away from the replica's main process, so `health` fails.

## Inputs

| Input | Type | Default | What it does |
|-------|------|---------|--------------|
| `stage` | string | `test` | Pipeline stage for the portability job. |
| `job_name` | string | `portability` | Name of the job. Set it when you include this component more than once. |
| `image` | string | `quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb` | Buildah image the job runs in. It builds the app image and runs the probe, so it needs buildah, curl, awk and find. |
| `dockerfile` | string | `Dockerfile` | Dockerfile to build, relative to the context. |
| `context` | string | `.` | Build context, relative to the project root. |
| `build_args` | array | `[]` | Build arguments as `NAME=value`. `$NAME` and `${NAME}` in a value are replaced from the job's variables. |
| `app_root` | string | `/app` | Directory inside the image where the app lives. |
| `writable_paths` | array | `["storage", "bootstrap/cache"]` | Paths the app may write to, relative to `app_root`. Each must be writable by the uid in group 0. |
| `runtime_paths` | array | `["/tmp", "/var/tmp", "/run", "/var/run"]` | Absolute paths the platform mounts as tmpfs. Writes there are allowed. |
| `port` | number | `8080` | Port the app listens on by default. The second replica gets `port + 1` through `port_env`. |
| `port_env` | string | `PORT` | Environment variable that sets the app's listen port. |
| `health_path` | string | `/up` | Path that must answer 200 for any Host, before trusted hosts, HTTPS redirects, sessions and auth. |
| `uid` | number | `100123` | Numeric uid the app runs as, with no `/etc/passwd` entry. The gid is always 0. |
| `start_command` | string | `""` | Command that starts the app, run with `sh -c`. Empty runs the image's own `ENTRYPOINT` and `CMD`. |
| `env` | array | `[]` | Environment for both replicas, as `NAME=value` (or `NAME` to pass the job's variable through). Keep secrets in CI/CD variables. |
| `services` | array | `[]` | Service containers for the job, as GitLab's `services:` keyword takes them (an image string, or a map with `name`, `alias` and `variables`). A database or cache the replicas share lets `session-hop` pass for an app that keeps sessions there. Pin each image by digest. |
| `boot_timeout` | number | `60` | Seconds each replica has to answer the health path. |
| `stop_timeout` | number | `10` | Seconds the main process has to exit after SIGTERM. |
| `probe_path` | string | `/` | Page probed with and without forged forwarded headers; one that redirects or builds absolute URLs shows the most. |
| `identity_header` | string | `X-Forwarded-User` | Identity header a gateway would set (forged in `forwarded-headers`). |
| `session_login_path` | string | `""` | GET path that signs in a test user and sets the session cookie. Needed by `session-hop`. |
| `session_check_path` | string | `""` | Path that answers 200 only for a signed-in user. Needed by `session-hop`. |
| `logs_path` | string | `storage/logs` | Directory, relative to `app_root`, where nothing may be written. |
| `require_healthcheck` | boolean | `false` | Fail when the image declares no HEALTHCHECK. Docker and Coolify use it; OpenShift and Kubernetes use their own probes. |
| `checks` | array | `["health", "env-only", "forwarded-headers", "logs", "session-hop", "sigterm", "healthcheck"]` | The checks to run. Leave one out only on purpose; the strict boot always runs. |

The `image` default is an immutable tag (`-immutable`) pinned by digest, because the plain version tag can be re-pushed and its old digest removed.

## Verify locally

`tests/check-portability.sh` (and its `.ps1` twin) run the same probe in the same Buildah image against `tests/portability/app`: once clean, where every check must pass, and once per flaw (needs root, writes outside its paths, fixed port, host-bound health, a baked `.env`, trusts any proxy, file logs, file sessions, no SIGTERM handler, a failing HEALTHCHECK), where the targeted check must fail. Two more builds must pass every check: one reopens `/proc/self/fd/2` and one signals its whole process group on SIGTERM, as Apache does; they fail without the launcher. Preflight's own pipeline runs the component on the clean fixture and this check as `must-fail-portability`. See [Local checks](../reference/local-checks.md) for the commands.

## Related

- [Include a component twice](include-twice.md): the `job_name` input.
- [Same instance only](same-instance-only.md): components run only inside the GitLab instance that hosts this project.
- [When the components run](when-components-run.md): the `workflow:rules` block that belongs in the app's own file.
- [Reference](../reference/components.md): every component, with its inputs and defaults.
