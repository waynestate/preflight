#!/bin/sh
# check-proctor-cache.sh: does the proctor Composer cache stay correct?
#
# The proctor component caches Composer downloads so repeat runs do not
# re-download every package. The key is fixed (D-072): Composer's cache is
# additive, so a lock change downloads only the packages that changed. This
# check fails if either guarantee is broken:
#
#   * the cache key goes back to a lock-file hash (a files: line), so every
#     lock bump would miss the cache and refetch everything; or
#   * the cache key stops being preflight-proctor, so the cache would stop
#     belonging to the proctor job.
#
# The cache block lives directly on the proctor job. The template is two
# YAML documents separated by `---`; the jobs live in the second. This script
# reads the second document with awk and checks the cache block with plain
# grep/awk/sed, so it needs no yq and runs in the alpine image and on any
# Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TPL="$ROOT/templates/proctor/template.yml"

if [ ! -f "$TPL" ]; then
  echo "templates/proctor/template.yml not found at $TPL" >&2
  exit 1
fi

status=0

fail() {
  echo "check-proctor-cache: $1" >&2
  status=1
}

# The jobs document is everything after the first `---` line.
jobs=$(awk 'BEGIN { d = 0 } /^---[[:blank:]]*$/ { d = 1; next } d == 1 { print }' "$TPL")

# The cache block is a `cache:` key at two-space indent (a direct child of a
# job); it runs until the next two-space key or a zero-indent line. Capture
# it so the checks below look only inside the block.
block=$(printf '%s\n' "$jobs" | awk '
  /^  cache:[[:blank:]]*$/ { inblock = 1; print; next }
  inblock {
    if (/^  [A-Za-z_]/ || /^[^ ]/) { inblock = 0; next }
    print
  }')

# There must be exactly one cache block, on the proctor job.
cache_count=$(printf '%s\n' "$block" | grep -cE '^  cache:')
if [ "$cache_count" -ne 1 ]; then
  fail "expected exactly one job with a cache: block, found $cache_count"
fi

# The key must be fixed, not a lock-file hash (D-072): no files: line.
if printf '%s\n' "$block" | grep -qE '^[[:blank:]]*files:'; then
  fail "proctor cache key is a lock-file hash; use a fixed key (D-072)"
fi

# The key must be exactly preflight-proctor, so the cache belongs to the
# proctor job.
key=$(printf '%s\n' "$block" | grep -E '^[[:blank:]]*key:' | sed -E 's/^[[:blank:]]*key:[[:blank:]]*//')
if [ -z "$key" ]; then
  fail "proctor cache key is not preflight-proctor"
elif [ "$key" != "preflight-proctor" ]; then
  fail "proctor cache key is not preflight-proctor: $key"
fi

# The cache must cover the directory the job points Composer at.
if ! printf '%s\n' "$block" | grep -qE '^[[:blank:]]*-[[:blank:]]*\.composer-cache/[[:blank:]]*$'; then
  fail "proctor cache paths do not include .composer-cache/"
fi

# The job must point Composer at the cached directory.
var_value=$(printf '%s\n' "$jobs" | grep -E '^[[:blank:]]*COMPOSER_CACHE_DIR:' | sed -E 's/^[[:blank:]]*COMPOSER_CACHE_DIR:[[:blank:]]*//' | tr -d '"')
if [ -z "$var_value" ]; then
  fail "proctor job does not set COMPOSER_CACHE_DIR"
elif [ "$var_value" != '$CI_PROJECT_DIR/.composer-cache' ]; then
  fail "proctor COMPOSER_CACHE_DIR does not point at the cached directory: $var_value"
fi

if [ "$status" -eq 0 ]; then
  echo "check-proctor-cache: ok"
fi
exit "$status"
