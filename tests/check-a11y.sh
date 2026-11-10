#!/bin/sh
# check-a11y.sh: does the a11y component's checker still pass a clean site
# and fail a bad one?
#
# Runs scripts/a11y.sh, which runs templates/a11y/check.mjs with the image
# and versions pinned in templates/a11y/template.yml, against the fixtures in
# tests/a11y-fixtures with the component's default tags (WCAG 2.1 AA), light
# and dark, 320 px and 1280 px:
#
#   good, every page by glob       exit 0: 2 pages x 4 modes, no failure
#   bad, every page by glob        exit 1: the report names html-has-lang,
#                                  image-alt, label, color-contrast and
#                                  preflight-reflow (at 320 px only), and
#                                  dark.html fails in dark mode only
#   good, a page that is missing   exit 1: HTTP 404
#   good, a glob matching nothing  exit 2: a configuration error
#
# One result line per case goes to stdout; the checker's own output is kept
# in a temp folder and printed only for a case that went wrong. POSIX sh, so
# it runs on any Linux or macOS box and in Git Bash. Needs Docker; with
# A11Y_IN_IMAGE=1 (the must-fail-a11y job) it runs inside the Playwright
# image with no Docker. Its twin, check-a11y.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

if [ "${A11Y_IN_IMAGE:-}" != "1" ] && ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

TAGS='["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0

fail() {
  echo "check-a11y: $1" >&2
  status=1
}

# run <case> <args...>: run the gate, keep its log and reports, print its exit code.
run() {
  case_name=$1
  shift
  mkdir -p "$tmp/$case_name"
  sh scripts/a11y.sh --tags="$TAGS" --report="$tmp/$case_name" "$@" > "$tmp/$case_name.log" 2>&1
  echo $?
}

# expect <case> <wanted exit> <got exit>
expect() {
  if [ "$3" = "$2" ]; then
    echo "$1: exit $3 (expected)"
  else
    fail "$1: exit $3, expected $2"
    sed 's/^/  | /' "$tmp/$1.log" >&2
  fi
}

# failed_case <case> <testcase name>: does that JUnit test case carry a failure?
failed_case() {
  grep -A1 -F "name=\"$2\"" "$tmp/$1/gl-a11y-junit.xml" | grep -q '<failure'
}

# good: every page by glob, clean.
code=$(run good --site=tests/a11y-fixtures/good)
expect good 0 "$code"
if ! grep -q 'tests="8" failures="0"' "$tmp/good/gl-a11y-junit.xml" 2>/dev/null; then
  fail "good: the JUnit report does not show 8 checks and 0 failures"
fi

# bad: every page by glob, each known flaw named.
code=$(run bad --site=tests/a11y-fixtures/bad)
expect bad 1 "$code"
for rule in html-has-lang image-alt label color-contrast preflight-reflow; do
  if ! grep -q "\"id\": \"$rule\"" "$tmp/bad/gl-a11y-report.json" 2>/dev/null; then
    fail "bad: the report does not name $rule"
  fi
done
if ! grep -A1 -F 'name="index.html light 320px"' "$tmp/bad/gl-a11y-junit.xml" | grep -q 'preflight-reflow'; then
  fail "bad: index.html at 320 px is not reported for reflow"
fi
if grep -A1 -F 'name="index.html light 1280px"' "$tmp/bad/gl-a11y-junit.xml" | grep -q 'preflight-reflow'; then
  fail "bad: reflow is reported at 1280 px, where it does not apply"
fi
for mode in "light 320px" "light 1280px"; do
  if failed_case bad "dark.html $mode"; then
    fail "bad: dark.html fails in $mode, where it is clean"
  fi
done
for mode in "dark 320px" "dark 1280px"; do
  if ! failed_case bad "dark.html $mode"; then
    fail "bad: dark.html passes in $mode, where its contrast fails"
  fi
done
echo "bad: rules and modes checked"

# missing: a literal page that is not there fails the check, not the tool.
code=$(run missing --site=tests/a11y-fixtures/good --pages='["missing.html"]')
expect missing 1 "$code"
if ! grep -q 'HTTP 404' "$tmp/missing.log"; then
  fail "missing: the log does not say HTTP 404"
fi

# nomatch: a glob that matches nothing is a configuration error.
code=$(run nomatch --site=tests/a11y-fixtures/good --pages='["nope/**/*.html"]')
expect nomatch 2 "$code"

if [ "$status" -eq 0 ]; then
  echo "check-a11y: ok"
fi
exit "$status"
