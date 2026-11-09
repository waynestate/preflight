#!/bin/sh
# check-composer-audit-fails.sh: does the composer-audit component still
# fail a lock with a known advisory, a malware-flagged version or an
# abandoned package, and pass a clean one?
#
# Composer 2.10's `composer audit --locked` blocks on three things, each
# with its own rule: security advisories (always fail), versions on a
# repository's filter lists (Packagist publishes one, `malware`, fed by
# Aikido; fail by default through Composer's `policy.malware.audit`), and
# abandoned packages (fail by default; the component's abandoned input can
# relax only this one). This script checks that the template keeps the job
# honest (no allow_failure, no --ignore-unreachable, no --ignore-severity,
# no swallowed exit code), then renders the template's own script lines
# (its $[[ inputs ]] filled in per case) and runs them with sh -e, the way
# the runner does, on copies of the fixtures in a temp dir:
#
#   tests/fixture-app                 abandoned=fail          exit 0 (the clean case)
#   tests/audit-fixtures/advisory     fail, report, ignore    non-zero, names CVE-2024-52301
#   tests/audit-fixtures/malware      fail, report, ignore    non-zero, names aikido/endpoint-test on the malware list
#   tests/audit-fixtures/abandoned    fail                    non-zero, names phpunit/php-token-stream
#   tests/audit-fixtures/abandoned    report, ignore          exit 0
#
# The fixtures are pinned so the answers never move: laravel/framework
# v9.0.0 sits inside CVE-2024-52301 (GHSA-gv7v-rgg6-548h, fixed in
# 9.52.17), a permanent advisory; aikido/endpoint-test 0.0.1 is Aikido's
# own harmless package, published to be flagged so scanners can be tested
# (the EICAR file of Packagist); phpunit/php-token-stream is abandoned
# upstream. Nothing is installed: audit --locked reads only the lock.
#
# It needs the network: composer audit asks Packagist for advisories and
# filter lists on every run, so the CI job (must-fail-composer-audit in
# .gitlab-ci.yml) needs outbound HTTPS to packagist.org, the same as the
# component itself. A run with no network fails the clean case, and the
# must-fail cases match the advisory and package names, so an unreachable
# Packagist never passes as "failed as expected". It downloads no packages,
# so it keeps no cache. One result line per case goes to stdout; a case's
# output is printed only when it went wrong.
#
# It runs inside the template's image (composer:2.10.3, pinned by digest in
# templates/composer-audit/template.yml). Run it with
#
#   docker run --rm -v "$(pwd):/app:ro" -w /app \
#     composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 \
#     sh tests/check-composer-audit-fails.sh
#
# Its twin, check-composer-audit-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/composer-audit/template.yml"

status=0
fail() {
  echo "check-composer-audit-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/composer-audit/template.yml"
for f in tests/fixture-app/composer.lock \
  tests/audit-fixtures/advisory/composer.lock \
  tests/audit-fixtures/malware/composer.lock \
  tests/audit-fixtures/abandoned/composer.lock
do
  [ -f "$ROOT/$f" ] || fail "fixture missing: $f"
done
[ "$status" -eq 0 ] || exit 1

# The jobs document is everything after the last `---` line.
sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
[ -n "$sep" ] || { fail "no '---' separator between the spec and jobs documents"; exit 1; }
jobs=$(sed -n "$((sep + 1)),\$p" "$TPL")

# (a) the job lets Composer's exit code be the result: no allow_failure,
# no flag that hides an unreachable advisory source or a severity, no
# variable that turns the audit or a policy off, no swallowed exit code.
printf '%s\n' "$jobs" | grep -Eq '^  allow_failure:' \
  && fail "the composer-audit job has allow_failure; advisories must fail"
printf '%s\n' "$jobs" | grep -Fq -- '--ignore-unreachable' \
  && fail "the composer-audit job passes --ignore-unreachable; an unreachable advisory source must fail"
printf '%s\n' "$jobs" | grep -Fq -- '--ignore-severity' \
  && fail "the composer-audit job passes --ignore-severity"
printf '%s\n' "$jobs" | grep -Eq 'COMPOSER_(NO_AUDIT|AUDIT_ABANDONED|POLICY)' \
  && fail "the composer-audit job sets a COMPOSER_ audit variable; use the abandoned input"
printf '%s\n' "$jobs" | grep -F 'composer audit' | grep -Eq '\|\||\| *tee|; *true|--format' \
  && fail "the composer audit line swallows the exit code or changes the format (||, | tee, ; true, --format)"
printf '%s\n' "$jobs" | grep -Fxq -- '    - composer audit --locked --abandoned=$[[ inputs.abandoned ]]' \
  || fail 'the job lost its audit line: expected "composer audit --locked --abandoned=$[[ inputs.abandoned ]]"'

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
unset COMPOSER_AUDIT_ABANDONED COMPOSER_NO_AUDIT 2>/dev/null || true

# run <name> <dir> <abandoned>: copy the fixture to a temp dir, render the
# template's script with the case's inputs (the component.* values are
# stand-ins: they only feed the banner echo), run it with sh -e from the
# temp dir (working_dir points at the copy), keep the log and exit code.
run() {
  name=$1
  dir=$2
  mode=$3
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  printf '%s\n' "$script" | sed \
    -e 's|\$\[\[ inputs\.working_dir ]]|'"$name"'|g' \
    -e 's|\$\[\[ inputs\.abandoned ]]|'"$mode"'|g' \
    -e 's|\$\[\[ component\.[a-z]* ]]|check|g' > "$tmp/$name.sh"
  if grep -Fq -- '$[[' "$tmp/$name.sh"; then
    echo "the rendered script still holds an interpolation the check does not fill: $(grep -F -- '$[[' "$tmp/$name.sh" | head -n 1)" > "$tmp/$name.log"
    echo 99
    return
  fi
  (cd "$tmp" && sh -e "$tmp/$name.sh") > "$tmp/$name.log" 2>&1
  echo $?
}

# expect <name> <dir> <abandoned> <zero|nonzero> [pattern]: one case. A
# must-fail case also needs the pattern (an extended regex) in its output,
# so a network error never passes for a finding.
expect() {
  name=$1
  dir=$2
  mode=$3
  want=$4
  pattern=${5:-}
  label="composer-audit $name (abandoned=$mode)"
  code=$(run "$name" "$dir" "$mode")
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

# clean: the fixture app's lock has no advisory, no flagged version and no
# abandoned package.
expect clean tests/fixture-app fail zero 'No security vulnerability advisories found'

# must-fail: an advisory fails in every abandoned mode.
for mode in fail report ignore; do
  expect "advisory-$mode" tests/audit-fixtures/advisory "$mode" nonzero 'CVE-2024-52301'
done

# must-fail: a malware-flagged version fails in every abandoned mode.
for mode in fail report ignore; do
  expect "malware-$mode" tests/audit-fixtures/malware "$mode" nonzero 'aikido/endpoint-test.*malware'
done

# abandoned: fails by default, and the input relaxes only this rule.
expect abandoned-fail tests/audit-fixtures/abandoned fail nonzero 'phpunit/php-token-stream'
expect abandoned-report tests/audit-fixtures/abandoned report zero 'phpunit/php-token-stream'
expect abandoned-ignore tests/audit-fixtures/abandoned ignore zero

if [ "$status" -eq 0 ]; then
  echo "check-composer-audit-fails: ok"
fi
exit "$status"
