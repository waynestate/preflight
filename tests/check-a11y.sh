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
#   good, the root page ""         exit 0: "" is the site root, 1 page x 4 modes
#   good, the root page "/"        exit 0: "/" is the site root, 1 page x 4 modes
#   routes, the unit test          exit 0: the coverage logic, no Docker, no
#                                  browser
#   routes, the file is missing    exit 2: a configuration error
#   routes, a route off the list   exit 1: the message names the route and the
#                                  file; the browser never runs
#   routes, every route covered    exit 0: the check proceeds, 2 pages x 4 modes
#
# One result line per case goes to stdout; the checker's own output is kept
# in a temp folder and printed only for a case that went wrong. POSIX sh, so
# it runs on any Linux or macOS box and in Git Bash. Needs Docker and node;
# with A11Y_IN_IMAGE=1 (the must-fail-a11y job) it runs inside the Playwright
# image with no Docker. Its twin, check-a11y.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

if [ "${A11Y_IN_IMAGE:-}" != "1" ] && ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node is required" >&2
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

# The pins, read from the template the same way scripts/a11y.sh does. The
# routes cases below drive the container themselves, because scripts/a11y.sh
# predates required_routes_file and cannot forward it to the checker.
default_of() {
  awk -v key="    $1:" '
    $0 == key { inblock = 1; next }
    inblock && /^    [A-Za-z_]/ { exit }
    inblock && /^      default:/ { sub(/^      default:[ \t]*/, ""); print; exit }
  ' templates/a11y/template.yml | sed 's/^"\(.*\)"$/\1/'
}
IMAGE=$(default_of image)
AXE_CORE=$(default_of axe_core_version)
AXE_PW=$(default_of axe_playwright_version)
SCHEMES=$(default_of color_schemes)
WIDTHS=$(default_of widths)
PW=$(printf '%s\n' "$IMAGE" | sed -n 's/^.*playwright:v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p')
if [ -z "$IMAGE" ] || [ -z "$AXE_CORE" ] || [ -z "$AXE_PW" ] || [ -z "$PW" ]; then
  echo "check-a11y: cannot read the image and versions from templates/a11y/template.yml" >&2
  exit 1
fi

# run_routes <case> <site> <pages json> <routes file>: like run, but sets
# A11Y_REQUIRED_ROUTES_FILE for the checker. In Docker mode this drives the
# same container scripts/a11y.sh would start; in-image, the export flows
# through scripts/a11y.sh as is.
run_routes() {
  case_name=$1
  site=$2
  pages=$3
  routes_file=$4
  mkdir -p "$tmp/$case_name"
  if [ "${A11Y_IN_IMAGE:-}" = "1" ]; then
    A11Y_REQUIRED_ROUTES_FILE="$routes_file" \
      sh scripts/a11y.sh --tags="$TAGS" --report="$tmp/$case_name" --site="$site" --pages="$pages" > "$tmp/$case_name.log" 2>&1
  else
    CONFIG=$(printf '{"siteDir": "%s", "pages": %s, "tags": %s, "colorSchemes": %s, "widths": %s, "axeCoreVersion": "%s"}' \
      "$site" "$pages" "$TAGS" "$SCHEMES" "$WIDTHS" "$AXE_CORE")
    # Git Bash on Windows rewrites absolute-looking arguments for native
    # programs; turn that off and pass the Windows form of the host paths.
    if [ -n "${MSYSTEM:-}" ]; then
      export MSYS_NO_PATHCONV=1
      REPO="$(pwd -W)"
    else
      REPO="$PWD"
    fi
    if [ -n "${MSYSTEM:-}" ]; then
      REPORT_HOST="$(cd "$tmp/$case_name" && pwd -W)"
    else
      REPORT_HOST="$(cd "$tmp/$case_name" && pwd)"
    fi
    docker run --rm --label task=preflight-a11y-routes-1124 \
      -v "${REPO}:/work:ro" -v preflight-a11y-npm-cache:/root/.npm -v "${REPORT_HOST}:/report" \
      -w /work \
      -e "A11Y_CONFIG=$CONFIG" \
      -e "A11Y_REPORT_DIR=/report" \
      -e "A11Y_PLAYWRIGHT_VERSION=$PW" \
      -e "A11Y_AXE_PLAYWRIGHT_VERSION=$AXE_PW" \
      -e "A11Y_AXE_CORE_VERSION=$AXE_CORE" \
      -e "A11Y_REQUIRED_ROUTES_FILE=$routes_file" \
      "$IMAGE" sh scripts/a11y-container.sh > "$tmp/$case_name.log" 2>&1
  fi
  echo $?
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

# root: the empty string is the site root, reported as "/".
code=$(run root --site=tests/a11y-fixtures/good --pages='[""]')
expect root 0 "$code"
if ! grep -q 'tests="4" failures="0"' "$tmp/root/gl-a11y-junit.xml" 2>/dev/null; then
  fail "root: the JUnit report does not show 4 checks and 0 failures"
fi
if ! grep -q 'name="/ light 320px"' "$tmp/root/gl-a11y-junit.xml" 2>/dev/null; then
  fail "root: the JUnit report does not name the root /"
fi

# rootslash: "/" is the other spelling of the site root.
code=$(run rootslash --site=tests/a11y-fixtures/good --pages='["/"]')
expect rootslash 0 "$code"
if ! grep -q 'tests="4" failures="0"' "$tmp/rootslash/gl-a11y-junit.xml" 2>/dev/null; then
  fail "rootslash: the JUnit report does not show 4 checks and 0 failures"
fi
if ! grep -q 'name="/ light 320px"' "$tmp/rootslash/gl-a11y-junit.xml" 2>/dev/null; then
  fail "rootslash: the JUnit report does not name the root /"
fi

# routes-unit: the coverage logic as pure functions, no Docker, no browser.
node tests/check-a11y-routes.mjs > "$tmp/routes-unit.log" 2>&1
code=$?
expect routes-unit 0 "$code"

# routes-missing: the file is set but not there: a tool error, not a check failure.
code=$(run_routes routes-missing tests/a11y-fixtures/routes '["**/*.html"]' tests/a11y-fixtures/routes/nope.txt)
expect routes-missing 2 "$code"
if ! grep -qF 'a11y: required_routes_file tests/a11y-fixtures/routes/nope.txt was not found.' "$tmp/routes-missing.log"; then
  fail "routes-missing: the log does not name the missing file"
fi

# routes-fail: a route the page list does not cover fails the check before
# any page is opened.
code=$(run_routes routes-fail tests/a11y-fixtures/routes '["**/*.html"]' tests/a11y-fixtures/routes/routes.txt)
expect routes-fail 1 "$code"
if ! grep -qF 'a11y: 1 required route(s) are not on the page list: /about. Add them to pages, or drop them from tests/a11y-fixtures/routes/routes.txt.' "$tmp/routes-fail.log"; then
  fail "routes-fail: the log does not name the uncovered route"
fi

# routes-ok: every route covered: the check proceeds and passes.
code=$(run_routes routes-ok tests/a11y-fixtures/routes '["**/*.html"]' tests/a11y-fixtures/routes/routes-ok.txt)
expect routes-ok 0 "$code"
if ! grep -q 'tests="8" failures="0"' "$tmp/routes-ok/gl-a11y-junit.xml" 2>/dev/null; then
  fail "routes-ok: the JUnit report does not show 8 checks and 0 failures"
fi

if [ "$status" -eq 0 ]; then
  echo "check-a11y: ok"
fi
exit "$status"
