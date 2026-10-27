#!/bin/sh
# check-contract.sh: do the templates still match contract/inputs.json?
#
# The contract is the promise to consumers: inside a major version, an input
# keeps its name, type and default, and a job keeps its name
# (BEST_PRACTICES.md 1.4). This script is the test that catches a rename
# before a consumer does.
#
# POSIX sh, so it runs in the mikefarah/yq image and on any Linux or macOS
# box. Needs yq v4 (mikefarah/yq); it works with yq alone, no jq required.
#
# The comparison is done with small, single-purpose yq calls and `comm` in
# the shell rather than one big yq expression: each call extracts one thing
# (a list of names, or one value), and the shell decides what differs. That
# keeps every step easy to read and easy to debug.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONTRACT="$ROOT/contract/inputs.json"

if [ ! -f "$CONTRACT" ]; then
  echo "contract/inputs.json not found at $CONTRACT" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "yq v4 (mikefarah/yq) is required" >&2
  exit 1
fi

status=0
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Every component in the contract, one name per line. The contract is JSON,
# so yq answers in JSON and the quotes are stripped (names never contain
# quotes).
yq eval '.components | keys | .[]' "$CONTRACT" | tr -d '"' > "$tmpdir/components"

while IFS= read -r name; do
  [ -n "$name" ] || continue
  comp_status=0
  tpl="$ROOT/templates/$name/template.yml"

  if [ ! -f "$tpl" ]; then
    echo "contract entry '$name' has no template at templates/$name/template.yml"
    comp_status=1
  else
    # Compare only name, type and default, so a template may add fields such
    # as regex: without breaking the contract.
    #
    # Name sets, one per line, sorted so comm can diff them. The template is
    # YAML (names come out bare); the contract is JSON (names come out
    # quoted), so the contract side has its quotes stripped to match.
    yq eval 'select(document_index == 0) | .spec.inputs | keys[]' "$tpl" \
      | LC_ALL=C sort > "$tmpdir/tpl-in"
    yq eval ".components.$name.inputs[].name" "$CONTRACT" \
      | tr -d '"' | LC_ALL=C sort > "$tmpdir/c-in"
    yq eval 'select(document_index == 1) | keys[]' "$tpl" \
      | LC_ALL=C sort > "$tmpdir/tpl-jobs"
    yq eval ".components.$name.jobs[]" "$CONTRACT" \
      | tr -d '"' | LC_ALL=C sort > "$tmpdir/c-jobs"

    # Inputs the contract promises but the template does not define.
    missing=$(comm -13 "$tmpdir/tpl-in" "$tmpdir/c-in")
    if [ -n "$missing" ]; then
      printf '%s\n' "$missing" | while IFS= read -r n; do
        [ -n "$n" ] || continue
        echo "component '$name': missing input: $n"
      done
      comp_status=1
    fi

    # Inputs the template defines but the contract does not promise.
    unexpected=$(comm -23 "$tmpdir/tpl-in" "$tmpdir/c-in")
    if [ -n "$unexpected" ]; then
      printf '%s\n' "$unexpected" | while IFS= read -r n; do
        [ -n "$n" ] || continue
        echo "component '$name': unexpected input: $n"
      done
      comp_status=1
    fi

    # Jobs the contract promises but the template does not define.
    missing=$(comm -13 "$tmpdir/tpl-jobs" "$tmpdir/c-jobs")
    if [ -n "$missing" ]; then
      printf '%s\n' "$missing" | while IFS= read -r n; do
        [ -n "$n" ] || continue
        echo "component '$name': missing job: $n"
      done
      comp_status=1
    fi

    # Jobs the template defines but the contract does not promise.
    unexpected=$(comm -23 "$tmpdir/tpl-jobs" "$tmpdir/c-jobs")
    if [ -n "$unexpected" ]; then
      printf '%s\n' "$unexpected" | while IFS= read -r n; do
        [ -n "$n" ] || continue
        echo "component '$name': unexpected job: $n"
      done
      comp_status=1
    fi

    # Type and default for every input present in both. Both sides are read
    # with -o=json so the values are formatted identically before comparing.
    # The type is always a plain string, so its JSON quotes are stripped for a
    # readable message; the default keeps its JSON form (it may be an array).
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      tpl_type=$(yq eval -o=json "select(document_index == 0) | .spec.inputs[\"$n\"].type" "$tpl" | tr -d '"')
      c_type=$(yq eval -o=json ".components.$name.inputs[] | select(.name == \"$n\") | .type" "$CONTRACT" | tr -d '"')
      if [ "$tpl_type" != "$c_type" ]; then
        echo "component '$name': input $n: type is $tpl_type, contract says $c_type"
        comp_status=1
      fi
      tpl_def=$(yq eval -o=json "select(document_index == 0) | .spec.inputs[\"$n\"].default" "$tpl")
      c_def=$(yq eval -o=json ".components.$name.inputs[] | select(.name == \"$n\") | .default" "$CONTRACT")
      if [ "$tpl_def" != "$c_def" ]; then
        echo "component '$name': input $n: default is $tpl_def, contract says $c_def"
        comp_status=1
      fi
    done <<EOF
$(comm -12 "$tmpdir/tpl-in" "$tmpdir/c-in")
EOF
  fi

  if [ "$comp_status" -eq 0 ]; then
    echo "component '$name' matches the contract"
  fi
  if [ "$comp_status" -ne 0 ]; then
    status=1
  fi
done < "$tmpdir/components"

# A template that is not in the contract is drift too.
for tpl in "$ROOT"/templates/*/template.yml; do
  [ -f "$tpl" ] || continue
  dir=$(basename "$(dirname "$tpl")")
  if ! grep -qxF "$dir" "$tmpdir/components"; then
    echo "template '$dir' has no entry in contract/inputs.json"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "contract: all components match contract/inputs.json"
fi
exit "$status"
