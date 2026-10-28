#!/bin/sh
# check-php-test-cache.sh: does the php-test Composer cache stay correct?
#
# The php-test component caches Composer downloads so repeat runs do not
# re-download every package. The cache is only useful if it is invalidated
# when the dependencies change and if each PHP version gets its own cache.
# This check fails if either guarantee is broken:
#
#   * the cache key stops depending on composer.lock, so a dependency change
#     would silently reuse a stale cache; or
#   * the cache key prefix stops including the PHP version, so the 8.4 and
#     8.5 jobs would share a cache and clobber each other's downloads.
#
# The cache block lives on a hidden job that the php-test job extends when the
# cache input is true (docs: Components, "Use boolean inputs to conditionally
# configure jobs"). Rather than hard-coding that hidden job's name, the check
# finds whichever job in the template carries a cache: block, so it keeps
# working if the hidden job is renamed.
#
# POSIX sh, so it runs in the mikefarah/yq image and on any Linux or macOS
# box. Needs yq v4 (mikefarah/yq); it works with yq alone, no jq required.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TPL="$ROOT/templates/php-test/template.yml"

if [ ! -f "$TPL" ]; then
  echo "templates/php-test/template.yml not found at $TPL" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "yq v4 (mikefarah/yq) is required" >&2
  exit 1
fi

status=0

fail() {
  echo "check-php-test-cache: $1" >&2
  status=1
}

# The job that carries the cache: block. There is exactly one (the hidden job
# the php-test job extends when cache is true).
cache_jobs=$(yq eval 'select(document_index == 1) | to_entries | map(select(.value.cache != null)) | length' "$TPL")
if [ "$cache_jobs" != "1" ]; then
  fail "expected exactly one job with a cache: block, found $cache_jobs"
fi

# The cache key must depend on composer.lock, so a lock change invalidates the
# cache.
files=$(yq eval 'select(document_index == 1) | .[] | select(.cache != null) | .cache.key.files[]' "$TPL")
if [ -z "$files" ]; then
  fail "php-test cache key has no files list (expected composer.lock)"
else
  if ! printf '%s\n' "$files" | grep -qx 'composer.lock'; then
    fail "php-test cache key files do not include composer.lock: $files"
  fi
fi

# The cache key prefix must include the PHP version, so 8.4 and 8.5 jobs do
# not share a cache.
prefix=$(yq eval 'select(document_index == 1) | .[] | select(.cache != null) | .cache.key.prefix' "$TPL")
if [ -z "$prefix" ]; then
  fail "php-test cache key has no prefix"
else
  case $prefix in
    *PHP_VERSION*) ;;
    *) fail "php-test cache key prefix does not include the PHP version: $prefix" ;;
  esac
fi

if [ "$status" -eq 0 ]; then
  echo "check-php-test-cache: ok"
fi
exit "$status"
