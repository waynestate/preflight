#!/bin/sh
# check-portability.sh: does the portability probe still pass a portable app
# and fail each flaw for the right reason?
#
# Runs templates/portability/probe.sh (the probe the component inlines, kept
# in step by check-portability-inline) against the fixture in
# tests/portability/app, once clean and once per flaw:
#
#   none             every check passes
#   needs-root       strict-boot fails (writable paths not writable by uid:0)
#   writes-root      strict-boot fails (a write outside the writable paths)
#   fixed-port       strict-boot fails (replica B cannot use its PORT)
#   host-bound       health fails (/up refuses Host: 10.1.2.3:8080)
#   dotenv           env-only fails (the image ships a .env)
#   trusts-proxy     forwarded-headers fails (forged headers believed)
#   file-logs        logs fails (a log file under storage/logs)
#   file-sessions    session-hop fails (sessions on one replica's disk)
#   no-term-handler  sigterm fails (no SIGTERM handler in the main process)
#   bad-healthcheck  healthcheck fails (the image's HEALTHCHECK exits 1)
#   reopens-stderr   every check passes (the app reopens /proc/self/fd/2)
#   signals-group    every check passes (the app signals its process group
#                    on SIGTERM)
#
# The last two are regression cases for the probe's launcher: Buildah alone
# refuses both (root-owned stdio; a group shared with buildah-chroot-exec,
# which SIGKILLs the app), and every container runtime allows them.
#
# A flaw passes only when the probe exits non-zero AND names the expected
# check as FAIL, so a build error or a wrong-reason failure is caught too.
# One result line per case goes to stdout; the probe's output is printed only
# for a case that went wrong. PORTABILITY_CASES (space-separated flaw names)
# limits the run, for example PORTABILITY_CASES="none sigterm".
#
# It needs Buildah, so it runs inside the component's own image. The
# must-fail-portability job runs it in CI. Locally:
#
#   docker run --rm --security-opt seccomp=unconfined -v "$(pwd):/src:ro" -w /src \
#     quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb \
#     sh tests/check-portability.sh
#
# seccomp=unconfined, not --privileged: Docker's default seccomp profile
# refuses the user namespace Buildah's chroot isolation needs, and GitLab
# runners commonly allow it. No extra capabilities are granted either way.
# Its twin, check-portability.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROBE="$ROOT/templates/portability/probe.sh"

if ! command -v buildah >/dev/null 2>&1; then
  echo "check-portability: buildah is required; run this inside the Buildah image (see the header)" >&2
  exit 1
fi
[ -f "$PROBE" ] || { echo "check-portability: missing templates/portability/probe.sh" >&2; exit 1; }
[ -f "$ROOT/tests/portability/app/Dockerfile" ] || { echo "check-portability: missing tests/portability/app" >&2; exit 1; }

export STORAGE_DRIVER="${STORAGE_DRIVER:-vfs}"
export BUILDAH_ISOLATION="${BUILDAH_ISOLATION:-chroot}"

CASES="none:pass needs-root:strict-boot writes-root:strict-boot fixed-port:strict-boot host-bound:health dotenv:env-only trusts-proxy:forwarded-headers file-logs:logs file-sessions:session-hop no-term-handler:sigterm bad-healthcheck:healthcheck reopens-stderr:pass signals-group:pass"

# In GitLab, pull the fixture's base image through the Dependency Proxy. The
# probe replaces ${NAME} from the job's variables.
registry_arg=""
if [ -n "${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX:-}" ]; then
  registry_arg='"BASE_REGISTRY=${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}", '
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$ROOT" || exit 1

status=0
for entry in $CASES; do
  flaw=${entry%%:*}
  expect=${entry#*:}
  if [ -n "${PORTABILITY_CASES:-}" ]; then
    case " $PORTABILITY_CASES " in
      *" $flaw "*) ;;
      *) continue ;;
    esac
  fi

  inputs="$tmp/$flaw.inputs"
  cat > "$inputs" <<EOF
dockerfile=Dockerfile
context=tests/portability/app
build_args=[${registry_arg}"FLAW=$flaw"]
app_root=/app
writable_paths=["storage", "bootstrap/cache"]
runtime_paths=["/tmp", "/var/tmp", "/run", "/var/run"]
port=8080
port_env=PORT
health_path=/up
uid=100123
start_command=
env=["APP_URL=http://portability.invalid", "APP_KEY=portability-fixture-key-not-a-secret"]
boot_timeout=30
stop_timeout=10
probe_path=/
identity_header=X-Forwarded-User
session_login_path=/login
session_check_path=/me
logs_path=storage/logs
require_healthcheck=false
checks=["health", "env-only", "forwarded-headers", "logs", "session-hop", "sigterm", "healthcheck"]
EOF

  sh "$PROBE" "$inputs" > "$tmp/$flaw.log" 2>&1
  rc=$?
  buildah rmi -f localhost/portability-app >/dev/null 2>&1

  if [ "$expect" = pass ]; then
    if [ "$rc" -eq 0 ]; then
      echo "$flaw: pass"
      continue
    fi
    echo "$flaw: fail (expected pass)"
  elif grep -qF "portability: build: FAIL" "$tmp/$flaw.log"; then
    echo "$flaw: build failed (expected the $expect check to fail)"
  elif [ "$rc" -ne 0 ] && grep -qxF "portability: $expect: FAIL" "$tmp/$flaw.log"; then
    echo "$flaw: fail (expected, $expect)"
    continue
  elif [ "$rc" -eq 0 ]; then
    echo "$flaw: pass (expected the $expect check to fail)"
  else
    echo "$flaw: failed, but not the $expect check"
  fi
  status=1
  sed 's/^/  | /' "$tmp/$flaw.log" >&2
done

exit "$status"
