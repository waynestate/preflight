#!/bin/sh
# check-eslint-fails.sh: does the eslint component still fail a bad app
# and pass a clean one?
#
# The eslint component passes the tools' exit codes through: the job runs
# the app's own ESLint and Prettier plainly, so a non-zero exit fails the
# job. This script checks that the template keeps those plain lines (no
# tee, no pipe, no swallowed exit code), then runs the two fixtures:
#
#   tests/eslint-clean  exit 0 (the clean case)
#   tests/eslint-fails  non-zero exit, the output names no-unused-vars
#                       (the must-fail case)
#
# It runs inside the template's image (node:22.13-alpine, pinned by digest
# in templates/eslint/template.yml), where it performs the template's own
# commands from templates/eslint/template.yml for each fixture, in a copy
# in a temp dir: npm ci --ignore-scripts --cache .npm-cache, then
# npx --no-install eslint ., then npx --no-install prettier --check .
# (the template's defaults: working_dir ., eslint_args ., prettier true).
# The npm cache is pointed at the repository root's .npm-cache, which the
# must-fail-eslint job in .gitlab-ci.yml saves under a fixed key, so
# repeat pipelines skip the download. One result line per case goes to
# stdout; a fixture's output is printed only for a case that went wrong.
# Run it with
#
#   docker run --rm -v "$(pwd):/app" -w /app \
#     node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da \
#     sh tests/check-eslint-fails.sh
#
# Its twin, check-eslint-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/eslint/template.yml"

status=0
fail() {
  echo "check-eslint-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/eslint/template.yml"
[ -f "$ROOT/tests/eslint-clean/package.json" ] || fail "clean fixture missing: tests/eslint-clean"
[ -f "$ROOT/tests/eslint-fails/package.json" ] || fail "must-fail fixture missing: tests/eslint-fails"
[ "$status" -eq 0 ] || exit 1

# (a) the job keeps the plain npm ci and eslint lines, so the tools' exit
# codes are the job result: no tee, no pipe, no swallowed exit code.
grep -Fxq -- '    - npm ci --ignore-scripts --cache .npm-cache' "$TPL" \
  || fail "eslint job does not run npm ci plainly (no tee, no pipe)"
grep -Fxq -- '    - npx --no-install eslint $[[ inputs.eslint_args ]]' "$TPL" \
  || fail "eslint job does not run eslint plainly (no tee, no pipe)"
if grep 'eslint' "$TPL" | grep -Eq '\|\||\| *tee|; *true'; then
  fail "an eslint line swallows the exit code (||, | tee or ; true)"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run <name> <dir>: copy the fixture to a temp dir, run the template's own
# commands there, keep the log and the exit code.
run() {
  name=$1
  dir=$2
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  (cd "$work" && npm ci --ignore-scripts --cache "$ROOT/.npm-cache" && npx --no-install eslint . && npx --no-install prettier --check .) > "$tmp/$name.log" 2>&1
  echo $?
}

# clean: ESLint and Prettier exit 0.
code=$(run clean tests/eslint-clean)
ok=1
[ "$code" -eq 0 ] || { fail "eslint clean: exit $code, expected 0"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "eslint clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/clean.log" >&2
fi

# must-fail: the output carries no-unused-vars and ESLint exits non-zero.
code=$(run mustfail tests/eslint-fails)
ok=1
[ "$code" -ne 0 ] || { fail "eslint must-fail: exit 0, expected non-zero"; ok=0; }
grep -Fq "no-unused-vars" "$tmp/mustfail.log" || { fail "eslint must-fail: the output does not carry no-unused-vars"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "eslint must-fail: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/mustfail.log" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "check-eslint-fails: ok"
fi
exit "$status"
