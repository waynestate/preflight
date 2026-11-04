#!/bin/sh
# check-spec-keys.sh: does every template keep spec: to the keys GitLab
# accepts (component, inputs and description)?
#
# GitLab's component spec header rejects unknown keys: a pipeline that
# includes a component carrying version, name, category or tags under
# spec: fails at creation with "header:spec config contains unknown keys".
# The spec may carry only component, inputs and description, so this test
# fails on any other key directly under spec:. component must be a flow
# list drawn from name, version, sha and reference, because that is the
# shape GitLab fills in for the job's log line.
#
# The template is two YAML documents separated by `---`: the spec before the
# last separator, the jobs after it. Some templates start with a comment
# header, so the spec document is everything before the last `---` line, not
# the first. The keys directly under spec: are the two-space-indented keys of
# that document. This script reads the documents with awk and checks them with
# plain grep/sed, so it needs no yq and runs in the mikefarah/yq image and on
# any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-spec-keys: $1" >&2
  status=1
}

for tpl in "$ROOT"/templates/*/template.yml; do
  [ -f "$tpl" ] || continue
  name=$(basename "$(dirname "$tpl")")

  # The spec document is everything before the last `---` line.
  sep=$(grep -nE '^---[[:blank:]]*$' "$tpl" | tail -n 1 | cut -d: -f1)
  if [ -z "$sep" ]; then
    fail "$name: no '---' separator between the spec and jobs documents"
    continue
  fi
  spec=$(awk -v n="$sep" 'NR < n' "$tpl")

  # The keys directly under spec: are the two-space-indented keys.
  keys=$(printf '%s\n' "$spec" | grep -E '^  [A-Za-z_][A-Za-z0-9_-]*:' \
    | sed -E 's/^  ([A-Za-z_][A-Za-z0-9_-]*):.*/\1/' || true)

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case $key in
      inputs|description) ;;
      component)
        # component must be a flow list of the fields GitLab fills in:
        # [name, version, sha, reference], in any order.
        value=$(printf '%s\n' "$spec" | grep -E "^  component:[[:blank:]]" \
          | head -n 1 | sed -E 's/^  component:[[:blank:]]*//')
        if ! printf '%s\n' "$value" | grep -qE '^\[[[:blank:]]*[A-Za-z_][A-Za-z0-9_-]*([[:blank:]]*,[[:blank:]]*[A-Za-z_][A-Za-z0-9_-]*)*[[:blank:]]*\]$'; then
          fail "$name: spec: component must be a flow list such as [name, version, sha, reference]"
          continue
        fi
        items=$(printf '%s\n' "$value" | sed -E 's/^\[[[:blank:]]*//; s/[[:blank:]]*\]$//' | tr ',' '\n' | sed -E 's/^[[:blank:]]+//; s/[[:blank:]]+$//' | grep -v '^$')
        while IFS= read -r item; do
          [ -n "$item" ] || continue
          case $item in
            name|version|sha|reference) ;;
            *) fail "$name: spec: component lists an unknown field: $item" ;;
          esac
        done <<EOF2
$items
EOF2
        ;;
      *) fail "$name: spec: has an unknown key: $key" ;;
    esac
  done <<EOF
$keys
EOF
done

if [ "$status" -eq 0 ]; then
  echo "check-spec-keys: ok"
fi
exit "$status"
