#!/bin/sh
# check-php-test-cache.sh: does the php-test Composer cache stay correct?
#
# The php-test component caches Composer downloads so repeat runs do not
# re-download every package. The key is fixed per PHP version (D-072):
# Composer's cache is additive, so a lock change downloads only the packages
# that changed, and each PHP version keeps its own cache. This check fails if
# either guarantee is broken:
#
#   * the cache key goes back to a lock-file hash (a files: or prefix: line),
#     so every lock bump would miss the cache and refetch everything; or
#   * the cache key stops including the PHP version, so the 8.4 and 8.5 jobs
#     would share a cache and clobber each other's downloads.
#
# The cache block lives directly on the php-test job. The template is two
# YAML documents separated by `---`; the jobs live in the second. This script
# reads the second document with awk and checks the cache block with plain
# grep/awk/sed, so it needs no yq and runs in the alpine image and on any
# Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TPL="$ROOT/templates/php-test/template.yml"

if [ ! -f "$TPL" ]; then
  echo "templates/php-test/template.yml not found at $TPL" >&2
  exit 1
fi

status=0

fail() {
  echo "check-php-test-cache: $1" >&2
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

# There must be exactly one cache block, on the php-test job.
cache_count=$(printf '%s\n' "$block" | grep -cE '^  cache:')
if [ "$cache_count" -ne 1 ]; then
  fail "expected exactly one job with a cache: block, found $cache_count"
fi

# The key must be fixed, not a lock-file hash (D-072): no files: line.
if printf '%s\n' "$block" | grep -qE '^[[:blank:]]*files:'; then
  fail "php-test cache key is a lock-file hash; use a fixed key (D-072)"
fi

# No prefix: line either: the whole key is the fixed name.
if printf '%s\n' "$block" | grep -qE '^[[:blank:]]*prefix:'; then
  fail "php-test cache key has a prefix; use a fixed key (D-072)"
fi

# The key must include the PHP version, so 8.4 and 8.5 jobs do not share a
# cache.
key=$(printf '%s\n' "$block" | grep -E '^[[:blank:]]*key:' | sed -E 's/^[[:blank:]]*key:[[:blank:]]*//')
if [ -z "$key" ]; then
  fail "php-test cache key does not include the PHP version"
else
  case $key in
    *PHP_VERSION*) ;;
    *) fail "php-test cache key does not include the PHP version: $key" ;;
  esac
fi

if [ "$status" -eq 0 ]; then
  echo "check-php-test-cache: ok"
fi
exit "$status"
