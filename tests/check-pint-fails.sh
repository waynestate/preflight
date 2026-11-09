#!/bin/sh
# check-pint-fails.sh: does the pint component still fail a bad app
# and pass a clean one?
#
# The pint component passes the tool's exit code through: the job runs the
# app's own Pint in test mode, so a non-zero exit fails the job. This script
# checks that the template keeps the pint command as its own script line
# (no pipe, no || true), then runs the two fixtures:
#
#   tests/fixture-app     exit 0, reports PASS (the clean case)
#   tests/pint-fails      non-zero exit, names the unformatted file
#                         (the must-fail case)
#
# It runs inside the template's image (composer:2.10.3, pinned by digest in
# templates/pint/template.yml), where it performs the template's own
# commands from templates/pint/template.yml for each fixture, in a copy in
# a temp dir: composer install --no-interaction --no-progress --prefer-dist,
# then vendor/bin/pint --test --config=pint.json. One result line per case
# goes to stdout; a fixture's output is printed only for a case that went
# wrong. Run it with
#
#   docker run --rm -v "$(pwd):/app" -w /app \
#     composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 \
#     sh tests/check-pint-fails.sh
#
# Its twin, check-pint-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/pint/template.yml"

status=0
fail() {
  echo "check-pint-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/pint/template.yml"
[ -f "$ROOT/tests/fixture-app/composer.json" ] || fail "clean fixture missing: tests/fixture-app"
[ -f "$ROOT/tests/pint-fails/composer.json" ] || fail "must-fail fixture missing: tests/pint-fails"
[ "$status" -eq 0 ] || exit 1

# (a) the job runs the pint command as its own script line, so the exit
# code is the job result: no pipe, no || true.
grep -Fxq -- '    - vendor/bin/pint --test --config=$[[ inputs.config ]]' "$TPL" \
  || fail "pint job does not run the pint command as its own script line (no pipe, no || true)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run <name> <dir>: copy the fixture to a temp dir, run the template's own
# commands there, keep the log and the exit code.
run() {
  name=$1
  dir=$2
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  (cd "$work" && composer install --no-interaction --no-progress --prefer-dist && vendor/bin/pint --test --config=pint.json) > "$tmp/$name.log" 2>&1
  echo $?
}

# clean: Pint exits 0 and reports PASS.
code=$(run clean tests/fixture-app)
ok=1
[ "$code" -eq 0 ] || { fail "pint clean: exit $code, expected 0"; ok=0; }
grep -Fq "PASS" "$tmp/clean.log" || { fail "pint clean: the output does not report PASS"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "pint clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/clean.log" >&2
fi

# must-fail: the fixture fails and names the unformatted file.
code=$(run mustfail tests/pint-fails)
ok=1
[ "$code" -ne 0 ] || { fail "pint must-fail: exit 0, expected non-zero"; ok=0; }
grep -Fq "tests/ExampleTest.php" "$tmp/mustfail.log" || { fail "pint must-fail: the output does not name tests/ExampleTest.php"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "pint must-fail: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/mustfail.log" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "check-pint-fails: ok"
fi
exit "$status"
