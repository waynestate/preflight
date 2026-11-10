#!/bin/sh
# check-proctor-lock-fails.sh: does PROCTOR's lock-committed check still
# fail an app without composer.lock, and pass one with it?
#
# Row 4.5 of BEST_PRACTICES.md says the lock file is committed and that
# PROCTOR's lock-committed check fails when it is missing. This script
# proves it with the real PROCTOR (installed from the fixture app's own
# composer.lock), not a stub: it copies tests/fixture-app to a temp dir,
# installs its dependencies with the proctor template's install flags, and
# runs the template's default command,
#
#   vendor/bin/proctor check --format=codequality
#
# on the copy:
#
#   clean copy                exit 0, no lock-committed finding
#   copy without composer.lock non-zero, names proctor/lock-committed
#
# Composer recreates a missing lock while installing, so the no-lock case
# deletes the lock after the install, right before the check: the check
# sees exactly the state row 4.5 describes, an app whose lock is not
# committed. The script also asserts the template's default command stays
# what it runs.
#
# It needs the network: composer install downloads the fixture's packages.
# A provided COMPOSER_CACHE_DIR (the CI job and the Docker wrappers point
# it at a shared cache) is kept; without one the cache stays in the temp
# dir. One result line per case goes to stdout; a case's output is printed
# only when it went wrong.
#
# It runs inside the template's image (composer:2.11.1, pinned by digest in
# templates/proctor/template.yml). Run it with
#
#   docker run --rm -v "$(pwd):/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-proctor-lock-fails.sh
#
# Its twin, check-proctor-lock-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/proctor/template.yml"

status=0
fail() {
  echo "check-proctor-lock-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/proctor/template.yml"
[ -f "$ROOT/tests/fixture-app/composer.json" ] || fail "fixture missing: tests/fixture-app/composer.json"
[ -f "$ROOT/tests/fixture-app/composer.lock" ] || fail "fixture missing: tests/fixture-app/composer.lock"
[ "$status" -eq 0 ] || exit 1

# The script runs the template's default command; if the template changes
# it, teach both.
grep -Fxq '      default: vendor/bin/proctor check --format=codequality' "$TPL" \
  || fail 'the proctor template no longer defaults to "vendor/bin/proctor check --format=codequality"'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A fresh Composer home, so no global config can change a verdict. A
# provided COMPOSER_CACHE_DIR is kept, so the shared download cache works;
# otherwise the cache stays in the temp dir.
export COMPOSER_HOME="$tmp/composer-home"
mkdir -p "$COMPOSER_HOME"
[ -n "${COMPOSER_CACHE_DIR:-}" ] || export COMPOSER_CACHE_DIR="$tmp/composer-cache"
mkdir -p "$COMPOSER_CACHE_DIR"

# run <name> <delete-lock yes|no>: copy the fixture to a temp dir, install
# its dependencies with the proctor template's install flags, delete the
# lock when asked (Composer recreates a missing lock during the install, so
# the deletion comes after it), run the template's default command and keep
# Composer's log, the report, PROCTOR's stderr and the exit code.
run() {
  name=$1
  del=$2
  work="$tmp/$name"
  cp -R "$ROOT/tests/fixture-app" "$work"
  (cd "$work" && composer install --no-interaction --no-progress --no-plugins --no-scripts --ignore-platform-reqs) > "$tmp/$name.install.log" 2>&1
  if [ $? -ne 0 ]; then
    echo "composer install failed; the log below is Composer's" > "$tmp/$name.log"
    cat "$tmp/$name.install.log" >> "$tmp/$name.log"
    echo 99
    return
  fi
  if [ "$del" = yes ]; then
    [ -f "$work/composer.lock" ] || {
      echo "composer.lock is gone before the deletion; the install did not leave one" > "$tmp/$name.log"
      echo 99
      return
    }
    rm "$work/composer.lock"
  fi
  (cd "$work" && vendor/bin/proctor check --format=codequality > report.json 2> stderr.log)
  code=$?
  cat "$work/report.json" > "$tmp/$name.log"
  sed 's/^/  | /' "$work/stderr.log" >> "$tmp/$name.log"
  echo "$code"
}

# expect <name> <delete-lock yes|no> <zero|nonzero> <present|absent>
# <pattern>: one case. The pattern (a fixed string) must be present in, or
# absent from, the report, so a run that found nothing never passes for a
# verdict.
expect() {
  name=$1
  del=$2
  want=$3
  presence=$4
  pattern=$5
  label="proctor lock-committed $name"
  code=$(run "$name" "$del")
  ok=1
  if [ "$want" = zero ]; then
    [ "$code" -eq 0 ] || { fail "$label: exit $code, expected 0"; ok=0; }
  else
    [ "$code" -ne 0 ] || { fail "$label: exit 0, expected non-zero"; ok=0; }
  fi
  if [ "$presence" = present ] && ! grep -Fq -- "$pattern" "$tmp/$name.log"; then
    fail "$label: the report does not name $pattern"
    ok=0
  fi
  if [ "$presence" = absent ] && grep -Fq -- "$pattern" "$tmp/$name.log"; then
    fail "$label: the report names $pattern, expected none"
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "$label: exit $code (expected)"
  else
    sed 's/^/  | /' "$tmp/$name.log" >&2
  fi
}

# clean: the fixture app commits its lock, so lock-committed passes and the
# report holds no such finding.
expect clean no zero absent 'proctor/lock-committed'

# must-fail: without the lock the check fails and names it.
expect no-lock yes nonzero present 'proctor/lock-committed'

if [ "$status" -eq 0 ]; then
  echo "check-proctor-lock-fails: ok"
fi
exit "$status"
