#!/bin/sh
# check-abandoned-input.sh: does composer-audit expose the abandoned input,
# and does the flag behave the way the docs promise?
#
# An abandoned package fails the job by default (Composer's own default),
# and the abandoned input lets an app relax it on purpose: fail (default),
# report (list them, do not fail) or ignore. This script checks that the
# template and contract/inputs.json carry the input with its default and
# regex and that the job passes --abandoned, then runs composer audit in
# the composer:2.10.3 Docker image on two fixtures under
# tests/audit-fixtures: a lock whose only package is abandoned (fail exits
# non-zero, report and ignore exit 0) and a lock with a known advisory
# (all three modes exit non-zero). It needs POSIX tools and Docker.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/composer-audit/template.yml"
CONTRACT="$ROOT/contract/inputs.json"

status=0
fail() {
  echo "check-abandoned-input: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/composer-audit/template.yml"
[ -f "$CONTRACT" ] || fail "contract missing: contract/inputs.json"

# (a) the template carries the input with its default, regex and flag.
block=$(awk '/^    abandoned:$/{f=1; next} f && /^    [^ ]/{exit} f{print}' "$TPL")
[ -n "$block" ] || fail "template has no abandoned input in spec.inputs"
for want in \
  '      description: "How composer audit treats abandoned packages: fail (default), report (list them, do not fail) or ignore."' \
  '      type: string' \
  '      default: fail' \
  "      regex: '^(fail|report|ignore)\$'"
do
  printf '%s\n' "$block" | grep -Fxq -- "$want" || fail "template abandoned input is missing or wrong: $want"
done
grep -Fxq -- '    - composer audit --locked --abandoned=$[[ inputs.abandoned ]]' "$TPL" \
  || fail 'template script does not pass the input: expected "composer audit --locked --abandoned=$[[ inputs.abandoned ]]"'

# (b) the contract lists the input with the same shape.
grep -Fq '{ "name": "abandoned", "type": "string", "default": "fail", "regex": "^(fail|report|ignore)$" }' "$CONTRACT" \
  || fail "contract/inputs.json composer-audit entry has no abandoned input with name, type, default and regex"

# (c) and (d) the flag behaves: the abandoned fixture fails only in fail
# mode, the advisory fixture fails in every mode.
command -v docker >/dev/null 2>&1 || fail "docker is required: this script runs composer audit in the composer:2.10.3 image"

audit() {
  AUDIT_OUT=$(docker run --rm -v "$ROOT/tests/audit-fixtures/$1:/w" -w /w composer:2.10.3 \
    composer audit --locked "--abandoned=$2" 2>&1)
  AUDIT_EXIT=$?
}

expect() {
  audit "$1" "$2"
  if [ "$3" = nonzero ]; then
    [ "$AUDIT_EXIT" -ne 0 ] && return 0
    fail "composer audit --abandoned=$2 on $1 exited 0, expected non-zero"
  else
    [ "$AUDIT_EXIT" -eq 0 ] && return 0
    fail "composer audit --abandoned=$2 on $1 exited $AUDIT_EXIT, expected 0"
  fi
  printf '%s\n' "$AUDIT_OUT" >&2
}

for f in abandoned/composer.json abandoned/composer.lock advisory/composer.json advisory/composer.lock; do
  [ -f "$ROOT/tests/audit-fixtures/$f" ] || fail "fixture missing: tests/audit-fixtures/$f"
done

expect abandoned fail nonzero
expect abandoned report zero
expect abandoned ignore zero
expect advisory fail nonzero
expect advisory report nonzero
expect advisory ignore nonzero

if [ "$status" -eq 0 ]; then
  echo "check-abandoned-input: ok"
fi
exit "$status"
