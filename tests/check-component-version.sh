#!/bin/sh
# check-component-version.sh: does every template declare spec: component:
# and print the Preflight component line first in every job?
#
# Every component declares `component: [name, version, sha, reference]` under
# spec: so GitLab fills the fields in, and the first command of every job's
# script (or its before_script, when a template uses one) prints one line:
#
#   Preflight component <name> <version> (ref <reference>, sha <sha>)
#
# so a misbehaving job's log says which Preflight release produced it
# (BEST_PRACTICES 2.11). This script checks both halves with plain string
# matching: the spec document (everything before the last `---` line) must
# carry a two-space-indented `component:` key, and the first list item of
# each job's before_script or script must contain `Preflight component`. It
# needs no yq and runs in the mikefarah/yq image and on any Linux or macOS
# box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-component-version: $1" >&2
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
  jobs=$(awk -v n="$sep" 'NR > n' "$tpl")

  # Half one: the spec declares component:.
  if ! printf '%s\n' "$spec" | grep -qE '^  component:[[:blank:]]'; then
    fail "$name: spec: does not declare component:"
    continue
  fi

  # Half two: the first command of every job prints the Preflight component
  # line. Jobs are the top-level keys of the jobs document; their keys are
  # two-space indented, and the first command is the first four-space `- `
  # item of the job's before_script (when present) or script. The awk pass
  # reports one line per problem: NOSCRIPT|<job> or FIRST|<job>|<kind>.
  report=$(printf '%s\n' "$jobs" | awk '
    { line = $0 }
    line ~ /^"[^"]*":[ \t]*$/ || line ~ /^[A-Za-z_][A-Za-z0-9_.-]*:[ \t]*$/ {
      if (job != "" && !haveFirst) print "NOSCRIPT|" job
      job = line
      sub(/:[ \t]*$/, "", job)
      haveFirst = 0
      wantFirst = 0
      scriptKind = ""
      next
    }
    job == "" { next }
    line ~ /^  before_script:[ \t]*$/ {
      if (scriptKind == "") { scriptKind = "before_script"; wantFirst = 1 }
      next
    }
    line ~ /^  script:[ \t]*$/ {
      if (scriptKind == "") { scriptKind = "script"; wantFirst = 1 }
      next
    }
    line ~ /^  [A-Za-z_]/ { wantFirst = 0; next }
    wantFirst && line ~ /^    - / {
      haveFirst = 1
      wantFirst = 0
      if (line !~ /Preflight component/) print "FIRST|" job "|" scriptKind
    }
    END {
      if (job != "" && !haveFirst) print "NOSCRIPT|" job
    }
  ')
  if [ -n "$report" ]; then
    while IFS='|' read -r kind key extra; do
      case $kind in
        NOSCRIPT) fail "$name: job $key has no script or before_script to print the Preflight component line" ;;
        FIRST) fail "$name: job $key does not print the Preflight component line first in its $extra" ;;
      esac
    done <<EOF3
$report
EOF3
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-component-version: ok"
fi
exit "$status"
