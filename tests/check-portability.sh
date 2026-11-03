#!/bin/sh
# check-portability.sh: do the portability fixtures still prove the contract?
#
# Runs the same steps as templates/portability/template.yml against local
# Docker (localhost instead of the registry), for the three fixtures under
# tests/portability. Exits 0 only when good passes and both bad-* fixtures
# fail.
#
# POSIX sh, so it runs on any Linux or macOS box. Needs Docker. The fixtures
# are built and run the strict way: a non-root user in group 0, a read-only
# root filesystem, /tmp as a tmpfs, and one anonymous volume per writable
# path. The goss file and run script are bind-mounted at /goss, because docker
# cp fails on a read-only rootfs. The goss checks
# (templates/portability/goss.yaml) run inside the container as the app user,
# so they see the same permissions the app has. If the app fails to boot (the
# container exits), goss runs in a keep-alive container from the same image,
# so the checks fail for the right reason.
#
# One line per fixture goes to stdout (good: pass, bad-writes-root: fail
# (expected), and so on). Build output, container logs and the goss output go
# to stderr, so the result lines stay easy to read.

set -u

# Disable MSYS2 (Git Bash on Windows) path conversion so the container paths
# (/app/..., /tmp) are passed to docker verbatim. No-op on Linux and macOS.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURES="$ROOT/tests/portability"
GOSS_TEMPLATE="$ROOT/templates/portability/goss.yaml"

# Convert a host path for docker. On Git Bash, docker.exe is a Windows
# program and needs a Windows path, so cygpath (present only there) is used.
# On Linux and macOS the path is already correct and is returned as is.
host_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

# The goss checks run inside the container as the app user. The uid, port,
# health path, app root and writable paths mirror the component's defaults.
UID_NUM=100123
PORT=8080
HEALTH_PATH="/up"
APP_ROOT="/app"
WRITABLE_PATHS="storage bootstrap/cache"
BOOT_TIMEOUT=60

# Generate the goss file from the template and the fixture's inputs. The
# template is the same file the component uses; the writable-path checks are
# appended one per path.
new_goss_file() {
  out=$1
  sed -e "s|{{PORT}}|$PORT|g" \
      -e "s|{{HEALTH_PATH}}|$HEALTH_PATH|g" \
      -e "s|{{APP_ROOT}}|$APP_ROOT|g" \
      -e "s|{{UID}}|$UID_NUM|g" \
      "$GOSS_TEMPLATE" > "$out"
  for p in $WRITABLE_PATHS; do
    key="writable-$(printf '%s' "$p" | tr '/' '-')"
    printf '  %s:\n    exec: test -w %s/%s\n    exit-status: 0\n' "$key" "$APP_ROOT" "$p" >> "$out"
  done
}

# The goss download-and-run script, run inside the container as the app user.
# It is the same steps the portability-run job does inline, except the goss
# binary is downloaded to /goss (the bind mount) instead of /tmp: docker
# mounts --tmpfs with noexec, so the binary cannot be executed from /tmp. The
# goss file is bind-mounted at /goss/goss.yaml (docker cp fails on a read-only
# rootfs).
write_goss_run_script() {
  out=$1
  cat > "$out" <<'GOSSRUN'
set -eu
arch=$(uname -m)
case "$arch" in
  x86_64) goss_arch=x86_64; goss_sha=26e365428946294bcec0c61d867bb3c8349f39feb3d0e6f59084e98632785cc7 ;;
  aarch64|arm64) goss_arch=arm64; goss_sha=90a59612b4d67d9f1a9038634c000790136bb82526a69de1e81ac075c2f6d2c6 ;;
  *) echo "portability: unsupported architecture $arch" >&2; exit 1 ;;
esac
curl -fsSL -o /goss/goss.tar.gz "https://github.com/goss-org/goss/releases/download/v0.4.10/goss_0.4.10_linux_${goss_arch}.tar.gz"
echo "${goss_sha}  /goss/goss.tar.gz" | sha256sum -c -
tar -xzf /goss/goss.tar.gz -C /goss goss
chmod +x /goss/goss
/goss/goss validate -g /goss/goss.yaml --retry-timeout 60s
GOSSRUN
}

# Run one fixture the strict way and report its outcome.
# $1 = fixture name (good, bad-writes-root, bad-needs-root)
# $2 = expected outcome (pass or fail)
check_fixture() {
  name=$1
  expected=$2
  dir="$FIXTURES/$name"
  image="portability-$name"
  container=""
  goss_container=""
  tmpdir=""

  if [ ! -d "$dir" ]; then
    echo "$name: no fixture at tests/portability/$name" >&2
    return 1
  fi

  # Build the image from the fixture. The context and Dockerfile are host
  # paths, so they are converted for docker (a no-op off Git Bash).
  dockerfile=$(host_path "$dir/Dockerfile")
  context=$(host_path "$dir")
  if ! build_output=$(docker build -t "$image" -f "$dockerfile" "$context" 2>&1); then
    printf '%s\n' "$build_output" >&2
    echo "$name: build failed" >&2
    return 1
  fi

  # Generate the goss file and the goss run script in a host temp dir. They
  # are bind-mounted into the container at /goss, because docker cp fails on
  # a read-only rootfs (the daemon copies through the rootfs layer, not the
  # tmpfs).
  tmpdir=$(mktemp -d)
  new_goss_file "$tmpdir/goss.yaml"
  write_goss_run_script "$tmpdir/goss-run.sh"

  # The strict run flags: a non-root user in group 0, a read-only root
  # filesystem, /tmp as a tmpfs, one anonymous volume per writable path (each
  # starts from the image contents), and the bind mount at /goss. The bind
  # source is a host path, so it is converted for docker (a no-op off Git
  # Bash).
  set -- \
    --user "${UID_NUM}:0" \
    --read-only \
    --tmpfs /tmp
  for p in $WRITABLE_PATHS; do
    set -- "$@" "--mount=type=volume,dst=$APP_ROOT/$p"
  done
  set -- "$@" "--mount=type=bind,src=$(host_path "$tmpdir"),dst=/goss"

  # Run the app the strict way.
  if ! container=$(docker run -d "$@" "$image" 2>&1); then
    printf '%s\n' "$container" >&2
    echo "$name: run failed" >&2
    docker rmi "$image" >/dev/null 2>&1 || true
    rm -rf "$tmpdir"
    return 1
  fi

  # Give the app a moment to boot or fail.
  sleep 2

  # If the app container is still running, run goss in it. If it has exited
  # (the app failed to boot), run goss in a keep-alive container from the same
  # image with the same strict flags, so the checks fail for the right reason:
  # the health check fails because the app is not running, and the writable
  # path checks fail where the paths are not writable.
  goss_container=$container
  if [ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != "true" ]; then
    if ! goss_container=$(docker run -d "$@" "$image" sh -c "sleep 3600" 2>&1); then
      printf '%s\n' "$goss_container" >&2
      echo "$name: keep-alive run failed" >&2
      docker rm -f "$container" >/dev/null 2>&1 || true
      docker rmi "$image" >/dev/null 2>&1 || true
      rm -rf "$tmpdir"
      return 1
    fi
  fi

  # Run goss inside the container as the app user.
  goss_output=$(docker exec --user "${UID_NUM}:0" "$goss_container" sh /goss/goss-run.sh 2>&1)
  goss_exit=$?
  printf '%s\n' "$goss_output" >&2

  # Always remove the containers, the image, and the temp dir.
  docker rm -f "$goss_container" >/dev/null 2>&1 || true
  if [ "$goss_container" != "$container" ]; then
    docker rm -f "$container" >/dev/null 2>&1 || true
  fi
  docker rmi "$image" >/dev/null 2>&1 || true
  rm -rf "$tmpdir"

  if [ "$goss_exit" -eq 0 ]; then
    if [ "$expected" = "pass" ]; then
      echo "$name: pass"
      return 0
    fi
    echo "$name: pass (unexpected)"
    return 1
  fi

  if [ "$expected" = "fail" ]; then
    echo "$name: fail (expected)"
    return 0
  fi
  echo "$name: fail"
  return 1
}

status=0
check_fixture good pass || status=1
check_fixture bad-writes-root fail || status=1
check_fixture bad-needs-root fail || status=1

exit "$status"
