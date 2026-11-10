#!/bin/sh
# check-squire-kit-fails.sh: does the squire-kit component still fail a
# drifted kit and pass a clean one?
#
# The squire-kit component installs the Squire release a kit records in
# .squire.json and runs `squire init --check` on the kit folder, letting
# Squire's exit code be the job result (0 the kit matches, 1 it drifted,
# 2 the check could not run). This script renders the template's own
# script, taken from templates/squire-kit/template.yml with its $[[ inputs ]]
# filled in per case (not retyped, so a change to the template is what gets
# tested), and runs it with sh -e, the way the runner does, on copies of
# the fixture kit in a temp dir:
#
#   tests/squire-kit-fixture                 exit 0 (the clean case)
#   the same copy plus a line appended to    non-zero, names .squire/php-web.ini
#   .squire/php-web.ini                      (the drifted case)
#   the same copy minus .squire.json         exit 2, the no .squire.json message
#
# The broken copies are built at run time, so no broken kit is committed.
# It needs the network: the script installs the Squire release the kit
# records from Packagist, like the component. In CI the job points
# COMPOSER_CACHE_DIR at the project's .composer-cache/ (the job's cache),
# so repeat pipelines reuse the release; locally the check keeps its own
# Composer home and cache in a temp dir, so the checkout stays clean. One
# result line per case goes to stdout; a case's log is printed only for a
# case that went wrong. Run it with
#
#   docker run --rm -v "$(pwd):/app" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-squire-kit-fails.sh
#
# Its twin, check-squire-kit-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/squire-kit/template.yml"
FIXTURE="$ROOT/tests/squire-kit-fixture"

status=0
fail() {
  echo "check-squire-kit-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/squire-kit/template.yml"
[ -f "$FIXTURE/.squire.json" ] || fail "clean fixture missing: tests/squire-kit-fixture"
[ -f "$FIXTURE/.squire/php-web.ini" ] || fail "fixture kit file missing: tests/squire-kit-fixture/.squire/php-web.ini"
[ "$status" -eq 0 ] || exit 1

# The jobs document is everything after the last `---` line.
sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
[ -n "$sep" ] || { fail "no '---' separator between the spec and jobs documents"; exit 1; }
jobs=$(sed -n "$((sep + 1)),\$p" "$TPL")

# The job's script, in order, rendered to shell: a single-line item loses
# its "    - " marker, and a block scalar (the compare step) keeps its
# lines with the six-space indent stripped. YAML comments are dropped.
script=$(printf '%s\n' "$jobs" | awk '
  /^  script:[ \t]*$/ { inblock = 1; next }
  inblock && /^  [A-Za-z_"]/ { exit }
  inblock && /^    #/ { next }
  inblock && /^    - / {
    line = $0
    sub(/^    - /, "", line)
    if (line ~ /^[|>][-+]?[ \t]*$/) { mode = 1; next }
    mode = 0
    print line
    next
  }
  inblock && mode == 1 && /^      / {
    line = $0
    sub(/^      /, "", line)
    print line
    next
  }
  inblock && mode == 1 && /^[ \t]*$/ { print ""; next }
  inblock && mode == 1 { mode = 0 }
')
[ -n "$script" ] || { fail "no script extracted from the template"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A fresh Composer home. COMPOSER_CACHE_DIR: in CI the job points it at
# the project's .composer-cache/ (the job's cache); unset, the check keeps
# its own in a temp dir, so a local run leaves the checkout clean.
export COMPOSER_HOME="$tmp/composer-home"
if [ -z "${COMPOSER_CACHE_DIR:-}" ]; then
  COMPOSER_CACHE_DIR="$tmp/composer-cache"
fi
export COMPOSER_CACHE_DIR
mkdir -p "$COMPOSER_HOME" "$COMPOSER_CACHE_DIR"

# render <name>: fill the template's interpolations for one case
# (working_dir points at the copy, squire_version stays empty so the
# recorded version wins, the component.* values are stand-ins: they only
# feed the banner echo) and run the result with sh -e from $tmp. Prints
# the exit code.
render() {
  name=$1
  printf '%s\n' "$script" | sed \
    -e 's|\$\[\[ inputs\.working_dir \]\]|'"$name"'|g' \
    -e 's|\$\[\[ inputs\.squire_version \]\]||g' \
    -e 's|\$\[\[ component\.[a-z]* \]\]|check|g' > "$tmp/$name.sh"
  if grep -Fq -- '$[[' "$tmp/$name.sh"; then
    echo "the rendered script still holds an interpolation the check does not fill: $(grep -F -- '$[[' "$tmp/$name.sh" | head -n 1)" > "$tmp/$name.log"
    echo 99
    return
  fi
  (cd "$tmp" && sh -e "$tmp/$name.sh") > "$tmp/$name.log" 2>&1
  echo $?
}

# expect <name> <zero|nonzero|two> [pattern]: one case. A must-fail case
# also needs the pattern (an extended regex) in its output, so a network
# error never passes for a finding.
expect() {
  name=$1
  want=$2
  pattern=${3:-}
  label="squire-kit $name"
  code=$(render "$name")
  ok=1
  case $want in
    zero) [ "$code" -eq 0 ] || { fail "$label: exit $code, expected 0"; ok=0; } ;;
    nonzero) [ "$code" -ne 0 ] || { fail "$label: exit 0, expected non-zero"; ok=0; } ;;
    two) [ "$code" -eq 2 ] || { fail "$label: exit $code, expected 2"; ok=0; } ;;
  esac
  if [ -n "$pattern" ] && ! grep -Eq -- "$pattern" "$tmp/$name.log"; then
    fail "$label: the output does not name $pattern"
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "$label: exit $code (expected)"
  else
    sed 's/^/  | /' "$tmp/$name.log" >&2
  fi
}

# (a) clean: the kit Squire wrote in tests/squire-kit-fixture matches the
# release it records.
cp -R "$FIXTURE" "$tmp/clean"
expect clean zero

# (b) drifted: one kit file changed (a line appended to
# .squire/php-web.ini) must fail, naming the file.
cp -R "$FIXTURE" "$tmp/drifted"
printf '\n; check-squire-kit-fails: this line drifts the kit\n' >> "$tmp/drifted/.squire/php-web.ini"
expect drifted nonzero 'php-web\.ini'

# (c) no manifest: a folder with no .squire.json stops with exit 2 and the
# template's message.
cp -R "$FIXTURE" "$tmp/no-manifest"
rm -f "$tmp/no-manifest/.squire.json"
expect no-manifest two 'no \.squire\.json'

if [ "$status" -eq 0 ]; then
  echo "check-squire-kit-fails: ok"
fi
exit "$status"
