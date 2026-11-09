#!/bin/sh
# check-abandoned-input.sh: does composer-audit expose the abandoned input
# the way the docs promise?
#
# An abandoned package fails the job by default (Composer's own default),
# and the abandoned input lets an app relax it on purpose: fail (default),
# report (list them, do not fail) or ignore. This script checks that the
# template and contract/inputs.json carry the input with its default and
# regex and that the job passes --abandoned. Plain grep and awk, so it
# runs in the contract job's yq image. How the flag behaves on real locks
# (abandoned fails only in fail mode, an advisory or a malware-flagged
# version fails in every mode) is check-composer-audit-fails.sh's job: it
# runs composer audit and needs the network.

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

if [ "$status" -eq 0 ]; then
  echo "check-abandoned-input: ok"
fi
exit "$status"
