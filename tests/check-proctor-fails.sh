#!/bin/sh
# check-proctor-fails.sh: does the proctor component still fail a bad app
# and pass a clean one?
#
# The proctor component passes the tool's exit code through: the job runs
# the proctor_command with a plain redirect to gl-code-quality-report.json,
# so a non-zero exit fails the job and the JSON is only the Code Quality
# report. This script checks that the template keeps that plain redirect
# (no tee, no pipe), then runs the two fixtures:
#
#   tests/fixture-app    exit 0, prints [] (the clean case)
#   tests/proctor-fails  non-zero exit, prints one blocker finding
#                        (the must-fail case)
#
# One result line per case goes to stdout; a fixture's output is printed
# only for a case that went wrong. Needs no Docker and no Composer, so it
# runs in the contract job's image and on any Linux or macOS box and in
# Git Bash. Its twin, check-proctor-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/proctor/template.yml"

status=0
fail() {
  echo "check-proctor-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/proctor/template.yml"
[ -f "$ROOT/tests/fixture-app/bin/proctor" ] || fail "clean fixture missing: tests/fixture-app/bin/proctor"
[ -f "$ROOT/tests/proctor-fails/bin/proctor" ] || fail "must-fail fixture missing: tests/proctor-fails/bin/proctor"

# (a) the job keeps a plain redirect of the command to the report, so the
# exit code is the job result: no tee, no pipe.
grep -Fxq -- '    - $[[ inputs.proctor_command ]] > "$CI_PROJECT_DIR/gl-code-quality-report.json"' "$TPL" \
  || fail "proctor job does not redirect the command plainly to gl-code-quality-report.json (no tee, no pipe)"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# run <dir>: run the fixture's fake proctor, keep its output, print its exit code.
run() {
  (cd "$ROOT/$1" && sh bin/proctor check --format=codequality) > "$tmp" 2>&1
  echo $?
}

# clean: the stub prints an empty report and exits 0.
code=$(run tests/fixture-app)
ok=1
[ "$code" -eq 0 ] || { fail "proctor clean: exit $code, expected 0"; ok=0; }
[ "$(cat "$tmp")" = "[]" ] || { fail "proctor clean: the output is not []"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "proctor clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp" >&2
fi

# must-fail: the fixture prints one blocker finding and exits non-zero.
code=$(run tests/proctor-fails)
ok=1
[ "$code" -ne 0 ] || { fail "proctor must-fail: exit 0, expected non-zero"; ok=0; }
grep -Fq '"severity":"blocker"' "$tmp" || { fail "proctor must-fail: the output does not carry the blocker finding"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "proctor must-fail: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "check-proctor-fails: ok"
fi
exit "$status"
