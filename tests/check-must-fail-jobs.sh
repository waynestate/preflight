#!/bin/sh
# check-must-fail-jobs.sh: does every must-fail check have a job in the
# repository's own pipeline?
#
# Preflight's own .gitlab-ci.yml carries a job for every
# tests/check-*-fails.sh script: either a must-fail-* job that runs the
# script directly, or a line in the contract job's script list. This check
# fails when the wiring breaks in either direction:
#
#   * a script tests/check-*-fails.sh exists but its file name is not
#     mentioned anywhere in .gitlab-ci.yml, so the check never runs; or
#   * a top-level must-fail-* job names a tests/check-*.sh file in its
#     script that does not exist, so the job fails for the wrong reason.
#
# It reads .gitlab-ci.yml with plain grep and awk, so it needs no yq and
# runs in the mikefarah/yq image and on any Linux or macOS box. Point it at
# a copy with CI_FILE=/path/to/copy. With --self-test it copies
# .gitlab-ci.yml to a temp file with every line that mentions
# check-composer-ci-fails removed, runs itself against that copy, and
# passes only when that run fails and names check-composer-ci-fails.sh.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CI_FILE="${CI_FILE:-$ROOT/.gitlab-ci.yml}"

status=0
fail() {
  echo "check-must-fail-jobs: $1" >&2
  status=1
}

if [ ! -f "$CI_FILE" ]; then
  fail ".gitlab-ci.yml is missing at $CI_FILE"
  exit 1
fi

# Case A: every tests/check-*-fails.sh script must be mentioned somewhere
# in the CI file. This covers both the must-fail-* jobs and the contract
# job's script list.
for f in "$ROOT"/tests/check-*-fails.sh; do
  [ -e "$f" ] || continue
  base=$(basename "$f")
  if ! grep -qF -- "$base" "$CI_FILE"; then
    fail "tests/$base exists but $CI_FILE never mentions it"
  fi
done

# Case B: every top-level must-fail-* job's script lines must name test
# scripts that exist. Extract the script lines of each must-fail-* job
# block and check each tests/check-*.sh reference.
refs=$(awk '
  /^must-fail-[A-Za-z0-9_-]*:[ \t]*$/ { injob = 1; inscript = 0; next }
  injob && /^[^ ]/ { injob = 0; inscript = 0; next }
  injob && /^  script:[ \t]*$/ { inscript = 1; next }
  injob && inscript && /^  [A-Za-z_]/ { inscript = 0 }
  injob && inscript { print }
' "$CI_FILE" | grep -oE 'tests/check-[A-Za-z0-9_.-]+\.sh' | sort -u)

if [ -n "$refs" ]; then
  for ref in $refs; do
    if [ ! -f "$ROOT/$ref" ]; then
      fail "must-fail job names $ref but that file does not exist"
    fi
  done
fi

# Self-test: copy the CI file with every line that mentions
# check-composer-ci-fails removed, run this script against that copy, and
# pass only when that run fails and names check-composer-ci-fails.sh.
if [ "${1:-}" = "--self-test" ]; then
  tmp=$(mktemp "${TMPDIR:-/tmp}/check-must-fail-jobs.XXXXXX") || {
    fail "cannot create a temp file for the self-test"
    exit 1
  }
  trap 'rm -f "$tmp"' EXIT
  grep -vF 'check-composer-ci-fails' "$CI_FILE" > "$tmp" || true

  out=$(CI_FILE="$tmp" sh "$0" 2>&1)
  code=$?
  if [ "$code" -ne 0 ] && printf '%s\n' "$out" | grep -qF 'check-composer-ci-fails.sh'; then
    echo "check-must-fail-jobs: self-test ok (stripped run failed and named check-composer-ci-fails.sh)"
  else
    fail "self-test: the stripped run did not fail as expected (exit $code); output:"
    printf '%s\n' "$out" | sed 's/^/  | /' >&2
  fi
  exit "$status"
fi

if [ "$status" -eq 0 ]; then
  echo "check-must-fail-jobs: ok"
fi
exit "$status"
