#!/bin/sh
# check-cache-fails.sh: do the cache guards still fail a broken template?
#
# Three guards mark BEST_PRACTICES 4.8 Checked:
#
#   * tests/check-php-test-cache.sh: the php-test key stays fixed and keeps
#     the PHP version;
#   * tests/check-proctor-cache.sh: the proctor key stays preflight-proctor;
#   * tests/check-dependency-cache.sh: every cache block saves with
#     when: always.
#
# Nothing proves they fail when a template breaks, so this script copies
# the three guards and templates/ into a temp tree, breaks one thing and
# requires the named guard to fail:
#
#   clean  all three guards exit 0 on an unmutated copy
#   1      a files: [composer.lock] line after the php-test key
#          (php-test-cache guard)
#   2      the php-test key drops the PHP version (php-test-cache guard)
#   3      a files: [composer.lock] line after the proctor key
#          (proctor-cache guard)
#   4      the proctor key is renamed (proctor-cache guard)
#   5      the php-test cache block loses when: always (dependency-cache
#          guard)
#
# Each guard derives its root from its own location, so a copied guard
# inspects the temp tree. The tree is rebuilt between cases, and a mutation
# that changes nothing fails the script. One ok: or FAIL: line goes to
# stdout per case; the guard's log is printed only for a case that went
# wrong. Needs no Docker and no Composer, so it runs in the contract job's
# image and on any Linux or macOS box and in Git Bash. Its twin,
# check-cache-fails.ps1, does the same on Windows.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

for g in check-php-test-cache check-proctor-cache check-dependency-cache; do
  [ -f "$ROOT/tests/$g.sh" ] || { echo "FAIL: guard missing: tests/$g.sh" >&2; exit 1; }
done
[ -d "$ROOT/templates" ] || { echo "FAIL: templates/ missing" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tree="$tmp/tree"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# build_tree: a fresh copy of the three guards and the templates.
build_tree() {
  rm -rf "$tree"
  mkdir -p "$tree/tests"
  cp -R "$ROOT/templates" "$tree/templates"
  cp "$ROOT/tests/check-php-test-cache.sh" \
     "$ROOT/tests/check-proctor-cache.sh" \
     "$ROOT/tests/check-dependency-cache.sh" "$tree/tests/"
}

# run_guard <script>: run the named copied guard, keep its log and exit code.
run_guard() {
  sh "$tree/tests/$1" > "$tmp/guard.log" 2>&1
  return $?
}

# print_log: the guard's log, prefixed, for a case that went wrong.
print_log() {
  sed 's/^/  | /' "$tmp/guard.log" >&2
}

# clean: all three guards pass an unmutated copy.
build_tree
for g in check-php-test-cache check-proctor-cache check-dependency-cache; do
  if ! run_guard "$g.sh"; then
    print_log
    fail "clean: $g failed an unmutated copy"
  fi
done
echo "ok: clean: all three guards pass an unmutated copy"

# 1: the php-test key gains a lock-hash files: line.
build_tree
tpl="$tree/templates/php-test/template.yml"
sed -i 's|^    key: preflight-php-\${PHP_VERSION}$|    key: preflight-php-${PHP_VERSION}\n    files: [composer.lock]|' "$tpl"
grep -Fxq -- '    files: [composer.lock]' "$tpl" || fail "mutation did not apply"
if run_guard check-php-test-cache.sh; then
  fail "1: the php-test-cache guard passed a files: line in the key"
fi
echo "ok: 1: the php-test-cache guard fails a files: line in the key"

# 2: the php-test key drops the PHP version.
build_tree
sed -i 's|^    key: preflight-php-\${PHP_VERSION}$|    key: preflight-php|' "$tpl"
grep -Fxq -- '    key: preflight-php' "$tpl" || fail "mutation did not apply"
if run_guard check-php-test-cache.sh; then
  fail "2: the php-test-cache guard passed a key without the PHP version"
fi
echo "ok: 2: the php-test-cache guard fails a key without the PHP version"

# 3: the proctor key gains a lock-hash files: line.
build_tree
tpl="$tree/templates/proctor/template.yml"
sed -i 's|^    key: preflight-proctor$|    key: preflight-proctor\n    files: [composer.lock]|' "$tpl"
grep -Fxq -- '    files: [composer.lock]' "$tpl" || fail "mutation did not apply"
if run_guard check-proctor-cache.sh; then
  fail "3: the proctor-cache guard passed a files: line in the key"
fi
echo "ok: 3: the proctor-cache guard fails a files: line in the key"

# 4: the proctor key is renamed.
build_tree
sed -i 's|^    key: preflight-proctor$|    key: preflight-proctor-old|' "$tpl"
grep -Fxq -- '    key: preflight-proctor-old' "$tpl" || fail "mutation did not apply"
if run_guard check-proctor-cache.sh; then
  fail "4: the proctor-cache guard passed a renamed key"
fi
echo "ok: 4: the proctor-cache guard fails a renamed key"

# 5: the php-test cache block loses when: always.
build_tree
tpl="$tree/templates/php-test/template.yml"
sed -i '/^    when: always/d' "$tpl"
if grep -q 'when: always' "$tpl"; then
  fail "mutation did not apply"
fi
if run_guard check-dependency-cache.sh; then
  fail "5: the dependency-cache guard passed a cache block without when: always"
fi
echo "ok: 5: the dependency-cache guard fails a cache block without when: always"

echo "check-cache-fails: ok"
