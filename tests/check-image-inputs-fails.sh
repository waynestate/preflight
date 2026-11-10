#!/bin/sh
# check-image-inputs-fails.sh: does the image-input guard still fail a
# broken template?
#
# tests/check-image-inputs.sh marks BEST_PRACTICES 2.10 (every job image is
# an input) and 4.10 (a default php: tag names the Debian release) Checked.
# Nothing proves the guard fails when a template breaks, so this script
# copies the guard and templates/ into a temp tree, breaks one thing and
# requires the guard to fail:
#
#   clean  an unmutated copy exits 0
#   A      the php-test base job's image line becomes the hard-coded
#          php:8.4-cli-trixie; the guard must exit non-zero
#   B      the image input's default loses its Debian release,
#          php:${PHP_VERSION}-cli; the guard must exit non-zero
#
# The guard derives its root from its own location, so the copied guard
# inspects the temp tree. The tree is rebuilt between cases, and a mutation
# that changes nothing fails the script. One ok: or FAIL: line goes to
# stdout per case; the guard's log is printed only for a case that went
# wrong. Needs no Docker and no Composer, so it runs in the contract job's
# image and on any Linux or macOS box and in Git Bash. Its twin,
# check-image-inputs-fails.ps1, does the same on Windows.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

GUARD="$ROOT/tests/check-image-inputs.sh"

[ -f "$GUARD" ] || { echo "FAIL: guard missing: tests/check-image-inputs.sh" >&2; exit 1; }
[ -d "$ROOT/templates" ] || { echo "FAIL: templates/ missing" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tree="$tmp/tree"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# build_tree: a fresh copy of the guard and the templates.
build_tree() {
  rm -rf "$tree"
  mkdir -p "$tree/tests"
  cp -R "$ROOT/templates" "$tree/templates"
  cp "$GUARD" "$tree/tests/check-image-inputs.sh"
}

# run_guard: run the copied guard, keep its log and exit code.
run_guard() {
  sh "$tree/tests/check-image-inputs.sh" > "$tmp/guard.log" 2>&1
  return $?
}

# print_log: the guard's log, prefixed, for a case that went wrong.
print_log() {
  sed 's/^/  | /' "$tmp/guard.log" >&2
}

# clean: the guard passes an unmutated copy.
build_tree
if ! run_guard; then
  print_log
  fail "clean: the guard failed an unmutated copy"
fi
echo "ok: clean: the guard passes an unmutated copy"

# A: the base job's image line becomes a hard-coded image.
build_tree
tpl="$tree/templates/php-test/template.yml"
sed -i 's|^  image: \$\[\[ inputs\.image_prefix \]\]/\$\[\[ inputs\.image \]\]$|  image: php:8.4-cli-trixie|' "$tpl"
grep -Fxq -- '  image: php:8.4-cli-trixie' "$tpl" || fail "mutation did not apply"
if run_guard; then
  fail "A: the guard passed a hard-coded php-test image"
fi
echo "ok: A: the guard fails a hard-coded php-test image"

# B: the image input's default loses its Debian release.
build_tree
sed -i 's|^      default: php:\${PHP_VERSION}-cli-trixie$|      default: php:${PHP_VERSION}-cli|' "$tpl"
grep -Fxq -- '      default: php:${PHP_VERSION}-cli' "$tpl" || fail "mutation did not apply"
if run_guard; then
  fail "B: the guard passed a default tag without the Debian release"
fi
echo "ok: B: the guard fails a default tag without the Debian release"

echo "check-image-inputs-fails: ok"
