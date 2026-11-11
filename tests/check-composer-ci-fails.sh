#!/bin/sh
# check-composer-ci-fails.sh: does the composer-ci component still pass a
# project whose composer ci exits 0, and fail one whose composer ci exits
# non-zero, or whose composer install cannot run?
#
# The composer-ci job is the hand-written install-and-ci job nine stack
# repos carry, as one include. Its contract is the project's own ci script:
# composer install fetches the locked dependencies, and composer ci's exit
# code decides the job. There is no allow_failure input, because a failing
# composer ci must fail the pipeline. This script checks that the template
# keeps the job honest (no allow_failure, no --no-scripts or
# --ignore-platform-reqs on the install, no swallowed exit code on the ci
# line, interruptible and a timeout), then renders the template's own
# script lines (its $[[ inputs.working_dir ]] filled in per case, its
# component.* values as stand-ins) and runs them with sh -e, the way the
# runner does, on copies of the fixtures in a temp dir:
#
#   tests/ci-fixtures/pass          composer ci exits 0     exit 0, prints ci-fixture-passed
#   tests/ci-fixtures/fail          composer ci exits 1     non-zero, prints ci-fixture-failed
#   tests/ci-fixtures/pass (broken) install cannot run      non-zero
#
# The fixtures carry no packages, so composer install resolves nothing and
# downloads nothing: the check needs no network. A broken composer.json
# makes the install fail, and sh -e turns that into a non-zero job, so an
# install that cannot run never skips to green. One result line per case
# goes to stdout; a case's output is printed only when it went wrong.
#
# It runs inside the template's image (composer:2.11.1, pinned by digest in
# templates/composer-ci/template.yml). Run it with
#
#   docker run --rm -v "$(pwd):/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-composer-ci-fails.sh
#
# Its twin, check-composer-ci-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/composer-ci/template.yml"

status=0
fail() {
  echo "check-composer-ci-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/composer-ci/template.yml"
for f in tests/ci-fixtures/pass/composer.json \
  tests/ci-fixtures/fail/composer.json
do
  [ -f "$ROOT/$f" ] || fail "fixture missing: $f"
done
[ "$status" -eq 0 ] || exit 1

# The jobs document is everything after the last `---` line.
sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
[ -n "$sep" ] || { fail "no '---' separator between the spec and jobs documents"; exit 1; }
jobs=$(sed -n "$((sep + 1)),\$p" "$TPL")

# (a) the job lets Composer's exit code be the result: no allow_failure,
# no flag that skips the app's scripts or ignores its platform requirements
# on the install, no swallowed exit code on the ci line, and the two lines
# the component promises are still there, with interruptible and a timeout.
printf '%s\n' "$jobs" | grep -Eq '^  allow_failure:' \
  && fail "the composer-ci job has allow_failure; a failing composer ci must fail"
printf '%s\n' "$jobs" | grep -F 'composer install' | grep -Eq -- '--no-scripts|--ignore-platform-reqs' \
  && fail "the composer install line passes --no-scripts or --ignore-platform-reqs; the app's install must run"
printf '%s\n' "$jobs" | grep -F 'composer ci' | grep -Eq '\|\||\| *tee|; *true' \
  && fail "the composer ci line swallows the exit code (||, | tee, ; true)"
printf '%s\n' "$jobs" | grep -Fxq -- '    - composer install --no-interaction --no-progress --prefer-dist' \
  || fail 'the job lost its install line: expected "    - composer install --no-interaction --no-progress --prefer-dist"'
printf '%s\n' "$jobs" | grep -Fxq -- '    - composer ci' \
  || fail 'the job lost its ci line: expected "    - composer ci"'
printf '%s\n' "$jobs" | grep -Fxq -- '  interruptible: true' \
  || fail "the composer-ci job lost interruptible: true"
printf '%s\n' "$jobs" | grep -Eq '^  timeout:' \
  || fail "the composer-ci job lost its timeout"

# (b) the job's script lines, in order, without the "    - " item marker.
# The template's lines are single-line items, so a block scalar here means
# the template grew a shape this check does not render.
script=$(printf '%s\n' "$jobs" | awk '
  /^  script:[ \t]*$/ { inblock = 1; next }
  inblock && /^  [A-Za-z_"]/ { exit }
  inblock && /^    - / { line = $0; sub(/^    - /, "", line); print line }
')
[ -n "$script" ] || { fail "no script lines extracted from the template"; exit 1; }
if printf '%s\n' "$script" | grep -Eq '^[|>][-+]?[[:blank:]]*$'; then
  fail "the template's script has a block scalar; teach this check to render it"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A fresh Composer home and cache, so no global config or cached answer
# from an earlier run can change a verdict.
export COMPOSER_HOME="$tmp/composer-home"
export COMPOSER_CACHE_DIR="$tmp/composer-cache"
mkdir -p "$COMPOSER_HOME" "$COMPOSER_CACHE_DIR"

# run <name> <dir> [brk]: copy the fixture to a temp dir, render the
# template's script with the case's inputs (the component.* values are
# stand-ins: they only feed the banner echo), run it with sh -e from the
# temp dir (working_dir points at the copy), keep the log and exit code.
# With brk, the copy's composer.json is replaced by invalid JSON, so the
# install cannot run.
run() {
  name=$1
  dir=$2
  brk=${3:-}
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  if [ "$brk" = brk ]; then
    printf '{ this is not json\n' > "$work/composer.json"
  fi
  printf '%s\n' "$script" | sed \
    -e 's|\$\[\[ inputs\.working_dir ]]|'"$name"'|g' \
    -e 's|\$\[\[ component\.[a-z]* ]]|check|g' > "$tmp/$name.sh"
  if grep -Fq -- '$[[' "$tmp/$name.sh"; then
    echo "the rendered script still holds an interpolation the check does not fill: $(grep -F -- '$[[' "$tmp/$name.sh" | head -n 1)" > "$tmp/$name.log"
    echo 99
    return
  fi
  (cd "$tmp" && sh -e "$tmp/$name.sh") > "$tmp/$name.log" 2>&1
  echo $?
}

# expect <name> <dir> <zero|nonzero> [pattern] [brk]: one case. A must-fail
# case also needs the pattern (an extended regex) in its output, so a
# Composer crash never passes for the finding.
expect() {
  name=$1
  dir=$2
  want=$3
  pattern=${4:-}
  brk=${5:-}
  label="composer-ci $name"
  code=$(run "$name" "$dir" "$brk")
  ok=1
  if [ "$want" = zero ]; then
    [ "$code" -eq 0 ] || { fail "$label: exit $code, expected 0"; ok=0; }
  else
    [ "$code" -ne 0 ] || { fail "$label: exit 0, expected non-zero"; ok=0; }
  fi
  if [ -n "$pattern" ] && ! grep -Eq -- "$pattern" "$tmp/$name.log"; then
    fail "$label: the output does not name $pattern"
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "$label: exit $code (expected)"
  else
    sed 's/^/  | /' "$tmp/$name.log" >&2
  fi
}

# pass: the fixture's composer ci exits 0, so the job passes.
expect pass tests/ci-fixtures/pass zero 'ci-fixture-passed'

# fail: the fixture's composer ci exits 1, so the job must fail and name
# the finding.
expect fail tests/ci-fixtures/fail nonzero 'ci-fixture-failed'

# install-fails: a broken composer.json stops the install, and sh -e turns
# that into a non-zero job instead of skipping to green.
expect install-fails tests/ci-fixtures/pass nonzero '' brk

if [ "$status" -eq 0 ]; then
  echo "check-composer-ci-fails: ok"
fi
exit "$status"
