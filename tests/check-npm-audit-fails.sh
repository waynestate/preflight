#!/bin/sh
# check-npm-audit-fails.sh: does the npm-audit component still fail a lock
# with a known advisory, and pass a clean one, an app with no lock and a
# dev-only finding?
#
# This script checks that the template keeps the job honest (no
# allow_failure, the gate's exit code kept, the one `|| true` on the
# report line only, the .npmrc override flags in place), then renders the
# template's own script lines (its $[[ inputs ]] filled in per case) and
# runs them with sh -e, the way the runner does, on copies of the fixtures
# in a temp dir:
#
#   tests/npm-audit-fixtures/clean     high                 exit 0
#   tests/npm-audit-fails              high                 non-zero, names GHSA-35jh-r3h4-6jhm
#   tests/npm-audit-fails              medium               non-zero, npm is asked for moderate
#   tests/npm-audit-fails              critical             exit 0 (lodash 4.17.20 has no critical advisory)
#   tests/npm-audit-fails + .npmrc     high                 non-zero (audit=false, offline=true are overridden)
#   tests/npm-audit-fixtures/dev-only  high, omit_dev=true  exit 0, the full report names the advisory
#   tests/npm-audit-fixtures/dev-only  high, omit_dev=false non-zero
#   tests/npm-audit-fixtures/no-lock   high                 exit 0, "nothing to audit"
#   tests/npm-audit-fixtures/clean     unreachable registry non-zero, says the endpoint could not be reached
#
# The lodash pin never moves: 4.17.20 sits inside GHSA-35jh-r3h4-6jhm
# (CVE-2021-23337, high), a permanent advisory. The critical case leans on
# lodash having no critical advisory at 4.17.20; if one is ever published,
# that case goes red and the fixture's README is the place to say so.
#
# It needs the network: npm audit posts the lock's tree to the registry's
# audit endpoint on every run, so the CI job (must-fail-npm-audit in
# .gitlab-ci.yml) needs outbound HTTPS to registry.npmjs.org, the same as
# the component itself. A run with no network fails the clean case, and
# the must-fail cases match the advisory id, so an unreachable registry
# never passes as "failed as expected". The unreachable case points npm at
# a closed local port, so it needs no network to fail. Nothing is
# installed. One result line per case goes to stdout; a case's output is
# printed only when it went wrong.
#
# It runs inside the template's image (node:22.13-alpine, pinned by digest
# in templates/npm-audit/template.yml). Run it with
#
#   docker run --rm -v "$(pwd):/app:ro" -v stack-npm-cache:/root/.npm -w /app \
#     node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da \
#     sh tests/check-npm-audit-fails.sh
#
# Its twin, check-npm-audit-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/npm-audit/template.yml"

status=0
fail() {
  echo "check-npm-audit-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/npm-audit/template.yml"
for f in tests/npm-audit-fails/package-lock.json \
  tests/npm-audit-fixtures/clean/package-lock.json \
  tests/npm-audit-fixtures/dev-only/package-lock.json \
  tests/npm-audit-fixtures/no-lock/package.json
do
  [ -f "$ROOT/$f" ] || fail "fixture missing: $f"
done
[ -f "$ROOT/tests/npm-audit-fixtures/no-lock/package-lock.json" ] \
  && fail "tests/npm-audit-fixtures/no-lock must have no package-lock.json"
[ "$status" -eq 0 ] || exit 1

# The jobs document is everything after the last `---` line.
sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
[ -n "$sep" ] || { fail "no '---' separator between the spec and jobs documents"; exit 1; }
jobs=$(sed -n "$((sep + 1)),\$p" "$TPL")

# (a) the job lets npm's exit code be the result.
printf '%s\n' "$jobs" | grep -Eq '^  allow_failure:' \
  && fail "the npm-audit job has allow_failure; advisories must fail"
printf '%s\n' "$jobs" | grep -Fxq -- '      if npm audit $omit --audit-level="$level" --audit=true --offline=false >"$log" 2>&1; then status=0; else status=$?; fi' \
  || fail 'the job lost its gate line: npm audit $omit --audit-level="$level" --audit=true --offline=false, exit code kept in $status'
printf '%s\n' "$jobs" | grep -Fxq -- '      if [ "$status" -ne 0 ]; then exit "$status"; fi' \
  || fail "the job no longer exits with the gate's exit code"
# The one || true is the report line, which never fails by design.
others=$(printf '%s\n' "$jobs" | grep -v '^[[:blank:]]*#' | grep -E '\|\||; *true' \
  | grep -Fxv -- '        npm audit --audit=true --offline=false || true')
[ -z "$others" ] || fail "a line swallows an exit code (only the full report may): $others"
printf '%s\n' "$jobs" | grep -v '^[[:blank:]]*#' | grep -Eq -- '--audit=false|--offline=true|--audit-level=(none|info)|--dry-run' \
  && fail "the job turns the audit off (--audit=false, --offline=true, --audit-level=none or info, --dry-run)"

# (b) the job's script, in order, without the "    - " item markers. A
# block scalar item (`    - |`) is unindented by six spaces.
script=$(printf '%s\n' "$jobs" | awk '
  /^  script:[ \t]*$/ { inblock = 1; next }
  inblock && /^  [A-Za-z_"]/ { exit }
  inblock && /^    - [|>][-+]?[ \t]*$/ { blk = 1; next }
  inblock && /^    - / { blk = 0; line = $0; sub(/^    - /, "", line); print line; next }
  inblock && blk { line = $0; sub(/^      /, "", line); print line }
')
[ -n "$script" ] || { fail "no script lines extracted from the template"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# No npm setting from the caller may change a verdict.
unset npm_config_audit npm_config_offline npm_config_registry npm_config_audit_level \
  NPM_CONFIG_AUDIT NPM_CONFIG_OFFLINE NPM_CONFIG_REGISTRY NPM_CONFIG_AUDIT_LEVEL 2>/dev/null || true
export NPM_CONFIG_UPDATE_NOTIFIER=false

# run <name> <dir> <audit_level> <omit_dev> [registry]: copy the fixture to
# a temp dir, render the template's script with the case's inputs (the
# component.* values are stand-ins: they only feed the banner echo), run it
# with sh -e from the temp dir (working_dir points at the copy), keep the
# log and exit code. A name ending in -npmrc gets an .npmrc that turns the
# audit off, the way an app's own file could.
run() {
  name=$1
  dir=$2
  level=$3
  omit=$4
  registry=${5:-}
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  case $name in
    *-npmrc) printf 'audit=false\noffline=true\n' > "$work/.npmrc" ;;
  esac
  printf '%s\n' "$script" | sed \
    -e 's|\$\[\[ inputs\.working_dir ]]|'"$name"'|g' \
    -e 's|\$\[\[ inputs\.audit_level ]]|'"$level"'|g' \
    -e 's|\$\[\[ inputs\.omit_dev ]]|'"$omit"'|g' \
    -e 's|\$\[\[ component\.[a-z]* ]]|check|g' > "$tmp/$name.sh"
  if grep -Fq -- '$[[' "$tmp/$name.sh"; then
    echo "the rendered script still holds an interpolation the check does not fill: $(grep -F -- '$[[' "$tmp/$name.sh" | head -n 1)" > "$tmp/$name.log"
    echo 99
    return
  fi
  if [ -n "$registry" ]; then
    (cd "$tmp" && npm_config_registry="$registry" sh -e "$tmp/$name.sh") > "$tmp/$name.log" 2>&1
  else
    (cd "$tmp" && sh -e "$tmp/$name.sh") > "$tmp/$name.log" 2>&1
  fi
  echo $?
}

# expect <name> <dir> <level> <omit_dev> <zero|nonzero> <registry> [pattern...]:
# one case. Every pattern (an extended regex) must be in the output, so a
# network error never passes for a finding.
expect() {
  name=$1
  dir=$2
  level=$3
  omit=$4
  want=$5
  registry=$6
  shift 6
  label="npm-audit $name (audit_level=$level, omit_dev=$omit)"
  code=$(run "$name" "$dir" "$level" "$omit" "$registry")
  ok=1
  if [ "$want" = zero ]; then
    [ "$code" -eq 0 ] || { fail "$label: exit $code, expected 0"; ok=0; }
  else
    [ "$code" -ne 0 ] || { fail "$label: exit 0, expected non-zero"; ok=0; }
  fi
  for pattern in "$@"; do
    if ! grep -Eq -- "$pattern" "$tmp/$name.log"; then
      fail "$label: the output does not carry $pattern"
      ok=0
    fi
  done
  if [ "$ok" -eq 1 ]; then
    echo "$label: exit $code (expected)"
  else
    sed 's/^/  | /' "$tmp/$name.log" >&2
  fi
}

ADVISORY='GHSA-35jh-r3h4-6jhm'

# clean: a runtime package with no advisory; the audit really ran.
expect clean tests/npm-audit-fixtures/clean high true zero '' 'found 0 vulnerabilities'

# must-fail: a high advisory in a runtime dependency.
expect runtime-high tests/npm-audit-fails high true nonzero '' "$ADVISORY"
expect runtime-medium tests/npm-audit-fails medium true nonzero '' 'failing on moderate or higher' "$ADVISORY"
expect runtime-critical tests/npm-audit-fails critical true zero '' 'failing on critical or higher' "$ADVISORY"
expect runtime-high-npmrc tests/npm-audit-fails high true nonzero '' "$ADVISORY"

# dev-only: the gate leaves dev dependencies out, the report still lists them.
expect dev-only-omit tests/npm-audit-fixtures/dev-only high true zero '' 'found 0 vulnerabilities' 'full report' "$ADVISORY"
expect dev-only-all tests/npm-audit-fixtures/dev-only high false nonzero '' "$ADVISORY"

# no lock: an app with no front end stays green.
expect no-lock tests/npm-audit-fixtures/no-lock high true zero '' 'no lock file .*nothing to audit'

# unreachable registry: a clean lock still fails, with the reason.
expect unreachable tests/npm-audit-fixtures/clean high true nonzero 'http://127.0.0.1:9/' 'audit endpoint returned an error' 'could not be reached'

if [ "$status" -eq 0 ]; then
  echo "check-npm-audit-fails: ok"
fi
exit "$status"
