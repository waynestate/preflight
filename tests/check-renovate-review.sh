#!/bin/sh
# check-renovate-review.sh: do Preflight's own pins wait for a person?
#
# The shared preset renovate/default.json auto-merges digest, pin, patch and
# minor updates by default. That is fine for an app's dependencies, but the
# pins Preflight itself ships (the image digests in the templates, the
# contract and this repo's own pipeline, and the component versions an app
# includes) are what every app pipeline runs, so a change to them must be
# reviewed. This script checks the packageRules that enforce that with
# plain text matching, so it needs no yq and runs in the mikefarah/yq image
# and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

RENOVATE="$ROOT/renovate/default.json"

status=0

fail() {
  echo "check-renovate-review: $1" >&2
  status=1
}

if [ ! -f "$RENOVATE" ]; then
  fail "renovate/default.json is missing"
  exit "$status"
fi

# No yq in the logic, so "parses as JSON" is checked the cheap way: the
# document opens with { on its first line and closes with } on its last.
if [ "$(head -n 1 "$RENOVATE")" != "{" ]; then
  fail "renovate/default.json does not open with {"
fi
if [ "$(tail -n 1 "$RENOVATE")" != "}" ]; then
  fail "renovate/default.json does not close with }"
fi

if ! grep -q '"needs-review"' "$RENOVATE"; then
  fail "renovate/default.json does not carry the needs-review label"
fi

# The templates rule: a matchFileNames entry that lists templates/** must
# sit in a rule that also turns automerge off, within the same object.
if ! awk '
  /"matchFileNames".*"templates\/\*\*/ { key = NR }
  key > 0 && NR >= key && NR - key <= 4 && /"automerge":[[:space:]]*false/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$RENOVATE"; then
  fail "the matchFileNames rule for templates/** does not turn automerge off"
fi

# The same rule must also cover the contract and this repo's own pipeline.
if ! awk '
  /"matchFileNames".*"templates\/\*\*/ { key = NR }
  key > 0 && NR >= key && NR - key <= 4 {
    if (/"contract\/\*\*/) c = 1
    if (/"\.gitlab-ci\.yml"/) p = 1
  }
  END { exit (c && p) ? 0 : 1 }
' "$RENOVATE"; then
  fail "the matchFileNames rule for templates/** does not also cover contract/** and .gitlab-ci.yml"
fi

# The component rule: a gitlabci manager rule must match repository deps and
# turn automerge off, so a Preflight component version bump in an app waits
# for review.
if ! awk '
  /"matchManagers".*"gitlabci"/ { key = NR }
  key > 0 && NR >= key && NR - key <= 4 {
    if (/"matchDepTypes".*"repository"/) d = 1
    if (/"automerge":[[:space:]]*false/) a = 1
  }
  END { exit (d && a) ? 0 : 1 }
' "$RENOVATE"; then
  fail "the gitlabci component rule does not match repository deps and turn automerge off"
fi

# The Squire kit rule: a custom.regex rule for waynestate/squire must turn
# automerge off and carry the squire-kit label, so a kit version bump waits
# for a person to review the refreshed kit. Its postUpgradeTasks and the
# runner's allow-list are checked by tests/check-renovate-squire-kit.sh.
if ! awk '
  /"matchDepNames".*"waynestate\/squire"/ { key = NR }
  key > 0 && NR >= key && NR - key <= 6 {
    if (/"automerge":[[:space:]]*false/) a = 1
    if (/"squire-kit"/) l = 1
  }
  END { exit (a && l) ? 0 : 1 }
' "$RENOVATE"; then
  fail "the waynestate/squire rule does not turn automerge off and carry the squire-kit label"
fi

if [ "$status" -eq 0 ]; then
  echo "check-renovate-review: ok"
fi
exit "$status"
