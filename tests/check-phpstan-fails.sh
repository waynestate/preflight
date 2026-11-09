#!/bin/sh
# check-phpstan-fails.sh: does the phpstan component still fail a bad app
# and pass a clean one?
#
# The phpstan component passes the tool's exit code through: the job runs
# the app's own PHPStan with a plain redirect to phpstan-report.json, so a
# non-zero exit fails the job and the JSON is only the Code Quality report.
# This script checks that the template keeps that plain redirect (no tee,
# no pipe), then runs the two fixtures:
#
#   tests/fixture-app     exit 0, writes an empty report [] (the clean case)
#   tests/phpstan-fails   non-zero exit, the report names the type error
#                         (the must-fail case)
#
# It runs inside the template's image (composer:2.10.3, pinned by digest in
# templates/phpstan/template.yml), where it performs the template's own
# commands from templates/phpstan/template.yml for each fixture, in a copy
# in a temp dir: composer install --no-interaction --no-progress
# --prefer-dist, then vendor/bin/phpstan analyse --no-progress
# --error-format=gitlab --memory-limit=1G -c phpstan.neon >
# phpstan-report.json. One result line per case goes to stdout; a fixture's
# output is printed only for a case that went wrong. Run it with
#
#   docker run --rm -v "$(pwd):/app" -w /app \
#     composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 \
#     sh tests/check-phpstan-fails.sh
#
# Its twin, check-phpstan-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/phpstan/template.yml"

status=0
fail() {
  echo "check-phpstan-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/phpstan/template.yml"
[ -f "$ROOT/tests/fixture-app/composer.json" ] || fail "clean fixture missing: tests/fixture-app"
[ -f "$ROOT/tests/phpstan-fails/composer.json" ] || fail "must-fail fixture missing: tests/phpstan-fails"
[ "$status" -eq 0 ] || exit 1

# (a) the job keeps a plain redirect of the command to the report, so the
# exit code is the job result: no tee, no pipe.
grep -Fxq -- '    - vendor/bin/phpstan analyse --no-progress --error-format=gitlab --memory-limit=$[[ inputs.memory_limit ]] -c $[[ inputs.config ]] > "$CI_PROJECT_DIR/phpstan-report.json"' "$TPL" \
  || fail "phpstan job does not redirect the command plainly to phpstan-report.json (no tee, no pipe)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run <name> <dir>: copy the fixture to a temp dir, run the template's own
# commands there, keep the log and the exit code.
run() {
  name=$1
  dir=$2
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  (cd "$work" && composer install --no-interaction --no-progress --prefer-dist && vendor/bin/phpstan analyse --no-progress --error-format=gitlab --memory-limit=1G -c phpstan.neon > phpstan-report.json) > "$tmp/$name.log" 2>&1
  echo $?
}

# clean: PHPStan exits 0 and writes an empty report.
code=$(run clean tests/fixture-app)
ok=1
[ "$code" -eq 0 ] || { fail "phpstan clean: exit $code, expected 0"; ok=0; }
[ "$(cat "$tmp/clean/phpstan-report.json")" = "[]" ] || { fail "phpstan clean: the report is not []"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "phpstan clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/clean.log" >&2
fi

# must-fail: the report carries the type error and PHPStan exits non-zero.
code=$(run mustfail tests/phpstan-fails)
ok=1
[ "$code" -ne 0 ] || { fail "phpstan must-fail: exit 0, expected non-zero"; ok=0; }
grep -Fq "expects int, string given" "$tmp/mustfail/phpstan-report.json" || { fail "phpstan must-fail: the report does not carry the type error"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "phpstan must-fail: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/mustfail.log" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "check-phpstan-fails: ok"
fi
exit "$status"
