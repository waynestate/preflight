#!/bin/sh
# check-proctor-fails.sh: does the proctor component still fail a bad app
# and pass a clean one, and keep proctor.json only when PROCTOR can write it?
#
# The proctor component passes the tool's exit code through: the job runs
# the proctor_command with a plain redirect to gl-code-quality-report.json,
# so a non-zero exit fails the job and the JSON is only the Code Quality
# report. When the app's PROCTOR has `check --record` (0.11.0 and later),
# a guard in the job adds --record "$CI_PROJECT_DIR/proctor.json", the JSON
# report Rollcall reads from the job's artifact. This script checks that
# the template keeps the plain redirect (no tee, no pipe), the guard, the
# variable the guard reads and the artifact block, then renders the
# template's own guard and command line (the command filled in per case)
# and runs them with sh -e, the way the runner does, on fake PROCTORs:
#
#   tests/fixture-app     0.10.0 or older (no --record)   exit 0, [], no proctor.json
#   tests/proctor-record  0.11.0 or later, clean          exit 0, [], proctor.json
#   tests/proctor-fails   0.11.0 or later, one blocker    non-zero, blocker, proctor.json
#   tests/proctor-record  a gate command                  no proctor.json
#   tests/proctor-record  a command with quotes           no proctor.json
#
# One result line per case goes to stdout; a case's log is printed only for
# a case that went wrong. Needs no Docker and no Composer, so it runs in the
# contract job's image and on any Linux or macOS box and in Git Bash. Its
# twin, check-proctor-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/proctor/template.yml"

status=0
fail() {
  echo "check-proctor-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || { fail "template missing: templates/proctor/template.yml"; exit 1; }
for dir in tests/fixture-app tests/proctor-record tests/proctor-fails; do
  [ -f "$ROOT/$dir/bin/proctor" ] || fail "fixture missing: $dir/bin/proctor"
done
[ "$status" -eq 0 ] || exit 1

# The command line the job runs. Only the --record guard's ${...:+...} sits
# between the command and the plain redirect.
CMD_LINE='    - $[[ inputs.proctor_command ]] ${PREFLIGHT_PROCTOR_RECORD:+--record "$CI_PROJECT_DIR/proctor.json"} > "$CI_PROJECT_DIR/gl-code-quality-report.json"'

# (a) the job keeps a plain redirect of the command to the report, so the
# exit code is the job result: no tee, no pipe.
grep -Fxq -- "$CMD_LINE" "$TPL" \
  || fail "proctor job does not run the command, plus the guarded --record, with a plain redirect to gl-code-quality-report.json (no tee, no pipe)"

# (b) the guard reads the command as text from a job variable.
grep -Fxq -- '    PREFLIGHT_PROCTOR_COMMAND: $[[ inputs.proctor_command ]]' "$TPL" \
  || fail "proctor job does not set PREFLIGHT_PROCTOR_COMMAND from the proctor_command input"

# (c) the artifact block: kept on failure too, for 30 days, with
# proctor.json next to the Code Quality report.
block=$(awk '
  /^  artifacts:[[:blank:]]*$/ { inblock = 1; next }
  inblock && /^  [^ ]/ { exit }
  inblock && /^[^ ]/ { exit }
  inblock { print }
' "$TPL")
for want in '    when: always' '    expire_in: 30 days' '      - proctor.json' '      codequality: gl-code-quality-report.json'; do
  printf '%s\n' "$block" | grep -Fxq -- "$want" || fail "proctor artifacts block lacks: $(printf '%s' "$want" | sed 's/^ *//')"
done

# (d) the guard: the block-scalar script item that sets
# PREFLIGHT_PROCTOR_RECORD, without its six-space indent.
guard=$(awk '
  /^    - \|[[:blank:]]*$/ { if (found) exit; inblock = 1; buf = ""; next }
  inblock && /^      / { line = $0; sub(/^      /, "", line); buf = buf line "\n"; if (line ~ /^PREFLIGHT_PROCTOR_RECORD=/) found = 1; next }
  inblock { inblock = 0; if (found) exit }
  END { if (found) printf "%s", buf }
' "$TPL")
[ -n "$guard" ] || { fail "no --record guard (a script block that sets PREFLIGHT_PROCTOR_RECORD) in the template"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run <name> <dir> <command>: render the guard and the command line with the
# case's command, run them with sh -e from the fixture, CI_PROJECT_DIR set
# to a fresh temp dir. Prints the exit code; the log is $tmp/<name>.log.
run() {
  name=$1
  dir=$2
  cmd=$3
  project="$tmp/$name"
  mkdir -p "$project"
  line=$(printf '%s\n' "$CMD_LINE" | sed 's/^    - //')
  {
    printf '%s\n' "$guard"
    printf '%s\n' "$line" | awk -v cmd="$cmd" '{ i = index($0, "$[[ inputs.proctor_command ]]"); print substr($0, 1, i - 1) cmd substr($0, i + 29) }'
  } > "$tmp/$name.sh"
  (cd "$ROOT/$dir" && PREFLIGHT_PROCTOR_COMMAND=$cmd CI_PROJECT_DIR=$project sh -e "$tmp/$name.sh") > "$tmp/$name.log" 2>&1
  echo $?
}

# expect <name> <dir> <command> <zero|nonzero> <record|norecord> [pattern]:
# one case. The report must hold the pattern (fixed text) when one is given.
expect() {
  name=$1
  dir=$2
  cmd=$3
  want_exit=$4
  want_record=$5
  pattern=${6:-}
  code=$(run "$name" "$dir" "$cmd")
  project="$tmp/$name"
  ok=1
  if [ "$want_exit" = zero ] && [ "$code" -ne 0 ]; then fail "$name: exit $code, expected 0"; ok=0; fi
  if [ "$want_exit" = nonzero ] && [ "$code" -eq 0 ]; then fail "$name: exit 0, expected non-zero"; ok=0; fi
  if [ "$want_record" = record ]; then
    if [ ! -s "$project/proctor.json" ]; then
      fail "$name: proctor.json was not written"; ok=0
    elif ! grep -Fq '"tool":"proctor"' "$project/proctor.json"; then
      fail "$name: proctor.json is not the stub's JSON report"; ok=0
    fi
  elif [ -e "$project/proctor.json" ]; then
    fail "$name: proctor.json was written, expected none"; ok=0
  fi
  if [ -n "$pattern" ] && ! grep -Fq -- "$pattern" "$project/gl-code-quality-report.json" 2>/dev/null; then
    fail "$name: the Code Quality report does not hold $pattern"; ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    if [ -e "$project/proctor.json" ]; then kept="proctor.json kept"; else kept="no proctor.json"; fi
    echo "proctor $name: exit $code, $kept (expected)"
  else
    sed 's/^/  | /' "$tmp/$name.log" >&2
  fi
}

DEFAULT='sh bin/proctor check --format=codequality'

expect clean-old  tests/fixture-app    "$DEFAULT" zero    norecord '[]'
expect clean-new  tests/proctor-record "$DEFAULT" zero    record   '[]'
expect must-fail  tests/proctor-fails  "$DEFAULT" nonzero record   '"severity":"blocker"'
expect gate       tests/proctor-record 'sh bin/proctor gate --format=json' zero norecord
expect quoted     tests/proctor-record 'sh bin/proctor check --format=codequality --path="."' zero norecord '[]'

if [ "$status" -eq 0 ]; then
  echo "check-proctor-fails: ok"
fi
exit "$status"
