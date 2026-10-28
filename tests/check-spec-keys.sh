#!/bin/sh
# check-spec-keys.sh: does every template keep spec: to the keys GitLab
# accepts (inputs and description)?
#
# GitLab's component spec header rejects unknown keys: a pipeline that
# includes a component carrying version, name, category or tags under
# spec: fails at creation with "header:spec config contains unknown keys".
# The spec may carry only inputs and description, so this test fails on any
# other key directly under spec:.
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
    fail "$name: no `---` separator between the spec and jobs documents"
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
