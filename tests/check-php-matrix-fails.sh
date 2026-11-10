#!/bin/sh
# check-php-matrix-fails.sh: does the PHP matrix guard still fail a broken
# template?
#
# tests/check-php-matrix.sh marks BEST_PRACTICES 6.3 Checked: php-test
# keeps its parallel: matrix wiring (one job per PHP version) and the
# array-typed php_versions input behind it. Nothing proves the guard fails
# when the template breaks, so this script copies the guard and templates/
# into a temp tree, breaks one thing and requires the guard to fail:
#
#   clean  an unmutated copy exits 0
#   A      the parallel: block's three lines are deleted; the guard must
#          exit non-zero
#   B      php_versions' type: array becomes type: string; the guard must
#          exit non-zero
#
# The guard derives its root from its own location, so the copied guard
# inspects the temp tree. The tree is rebuilt between cases, and a mutation
# that changes nothing fails the script. One ok: or FAIL: line goes to
# stdout per case; the guard's log is printed only for a case that went
# wrong. Needs no Docker and no Composer, so it runs in the contract job's
# image and on any Linux or macOS box and in Git Bash. Its twin,
# check-php-matrix-fails.ps1, does the same on Windows.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

GUARD="$ROOT/tests/check-php-matrix.sh"

[ -f "$GUARD" ] || { echo "FAIL: guard missing: tests/check-php-matrix.sh" >&2; exit 1; }
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
  cp "$GUARD" "$tree/tests/check-php-matrix.sh"
}

# run_guard: run the copied guard, keep its log and exit code.
run_guard() {
  sh "$tree/tests/check-php-matrix.sh" > "$tmp/guard.log" 2>&1
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

# A: the parallel: block's three lines are deleted.
build_tree
tpl="$tree/templates/php-test/template.yml"
sed -i -e '/^  parallel:[[:blank:]]*$/d' \
       -e '/^    matrix:[[:blank:]]*$/d' \
       -e '/^      - PHP_VERSION: \$\[\[ inputs\.php_versions \]\][[:blank:]]*$/d' "$tpl"
if grep -Fxq -- '  parallel:' "$tpl" \
  || grep -Fxq -- '    matrix:' "$tpl" \
  || grep -Fxq -- '      - PHP_VERSION: $[[ inputs.php_versions ]]' "$tpl"; then
  fail "mutation did not apply"
fi
if run_guard; then
  fail "A: the guard passed a template without the parallel: block"
fi
echo "ok: A: the guard fails a template without the parallel: block"

# B: php_versions' type: array becomes type: string.
build_tree
sed -i 's|^      type: array$|      type: string|' "$tpl"
if grep -Fxq -- '      type: array' "$tpl"; then
  fail "mutation did not apply"
fi
if run_guard; then
  fail "B: the guard passed a php_versions input that is not type: array"
fi
echo "ok: B: the guard fails a php_versions input that is not type: array"

echo "check-php-matrix-fails: ok"
