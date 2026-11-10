#!/bin/sh
# check-contract-fails.sh: does the contract guard still fail a drifted
# template?
#
# tests/check-contract.sh marks BEST_PRACTICES 1.4 (inside a major version,
# an input keeps its name, type and default, and a job keeps its name)
# Checked. Nothing proves the guard fails when a template drifts, so this
# script copies the guard, the templates and the contract into a temp tree,
# breaks one thing and requires the guard to fail:
#
#   clean  an unmutated copy exits 0
#   M1     the composer-audit abandoned input's default changes from fail
#          to report; the guard must exit non-zero and name the component
#          and the input
#   M2     the abandoned input key is renamed abandonment in the spec;
#          the guard must exit non-zero and name both names
#
# The guard derives its root from its own location, so the copied guard
# inspects the temp tree. The tree is rebuilt between cases, and a mutation
# that changes nothing fails the script. One ok: or FAIL: line goes to
# stdout per case; the guard's log is printed only for a case that went
# wrong. Needs yq v4 (mikefarah/yq), so it runs in the contract job's
# image and on any Linux or macOS box with yq on the PATH. Its twin,
# check-contract-fails.ps1, does the same on Windows.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

GUARD="$ROOT/tests/check-contract.sh"

[ -f "$GUARD" ] || { echo "FAIL: guard missing: tests/check-contract.sh" >&2; exit 1; }
[ -d "$ROOT/templates" ] || { echo "FAIL: templates/ missing" >&2; exit 1; }
[ -f "$ROOT/contract/inputs.json" ] || { echo "FAIL: contract/inputs.json missing" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "FAIL: yq v4 (mikefarah/yq) is required" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tree="$tmp/tree"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# build_tree: a fresh copy of the guard, the templates and the contract.
build_tree() {
  rm -rf "$tree"
  mkdir -p "$tree/tests" "$tree/contract"
  cp -R "$ROOT/templates" "$tree/templates"
  cp "$ROOT/contract/inputs.json" "$tree/contract/inputs.json"
  cp "$GUARD" "$tree/tests/check-contract.sh"
}

# run_guard: run the copied guard, keep its log and exit code.
run_guard() {
  sh "$tree/tests/check-contract.sh" > "$tmp/guard.log" 2>&1
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
grep -Fxq "contract: all components match contract/inputs.json" "$tmp/guard.log" \
  || { print_log; fail "clean: the guard did not confirm the contract"; }
echo "ok: clean: the guard passes an unmutated copy"

# M1: the abandoned input's default changes from fail to report.
build_tree
tpl="$tree/templates/composer-audit/template.yml"
sed -i 's|^      default: fail$|      default: report|' "$tpl"
grep -Fxq -- '      default: report' "$tpl" || fail "mutation did not apply"
if run_guard; then
  fail "M1: the guard passed a changed abandoned default"
fi
grep -Fq "composer-audit" "$tmp/guard.log" || { print_log; fail "M1: the guard did not name the component"; }
grep -Fq "abandoned" "$tmp/guard.log" || { print_log; fail "M1: the guard did not name the input"; }
echo "ok: M1: the guard fails a changed abandoned default"

# M2: the abandoned input key is renamed abandonment in the spec.
build_tree
sed -i 's|^    abandoned:$|    abandonment:|' "$tpl"
grep -Fxq -- '    abandonment:' "$tpl" || fail "mutation did not apply"
if run_guard; then
  fail "M2: the guard passed a renamed abandoned input"
fi
grep -Fq "abandoned" "$tmp/guard.log" || { print_log; fail "M2: the guard did not name the old name"; }
grep -Fq "abandonment" "$tmp/guard.log" || { print_log; fail "M2: the guard did not name the new name"; }
echo "ok: M2: the guard fails a renamed abandoned input"

echo "check-contract-fails: ok"
