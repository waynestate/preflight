#!/bin/sh
# check-a11y-runner.sh: does the local a11y runner keep reading its pins from
# the component?
#
# scripts/a11y.sh and scripts/a11y.ps1 run the a11y component's own checker
# (templates/a11y/check.mjs) locally, in Docker, so no host browser is needed.
# Their whole point is that the Playwright image and the axe versions are NOT
# written in them: they are read at run time from the defaults in
# templates/a11y/template.yml, so a local run and a pipeline run check the
# same way. This test fails when a runner grows its own pin (a hard-coded
# image or version), stops reading an input from the template, drops an option
# a consumer passes, or changes the line endings that make it run on its OS.
#
#   sh tests/check-a11y-runner.sh    check (exit 0 in step, 1 drifted)
#
# Plain grep, awk and sed, so it needs no yq and runs in the mikefarah/yq
# image and on any Linux or macOS box. Its twin, check-a11y-runner.ps1, does
# the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SH="$ROOT/scripts/a11y.sh"
PS="$ROOT/scripts/a11y.ps1"
CON="$ROOT/scripts/a11y-container.sh"

status=0
fail() {
  echo "check-a11y-runner: $1" >&2
  status=1
}

# 1. The three runner files exist.
for f in "$SH" "$PS" "$CON"; do
  if [ ! -f "$f" ]; then
    fail "missing ${f#"$ROOT"/}"
  fi
done
if [ "$status" -ne 0 ]; then
  exit 1
fi

# 2. scripts/a11y.sh reads each input through default_of, from the template.
for name in image axe_core_version axe_playwright_version color_schemes widths; do
  grep -qF "default_of $name" "$SH" || fail "scripts/a11y.sh does not read $name with default_of"
done
grep -qF "templates/a11y/template.yml" "$SH" || fail "scripts/a11y.sh does not read templates/a11y/template.yml"

# 3. scripts/a11y.ps1 reads each input through Get-InputDefault, from the
# template.
for name in image axe_core_version axe_playwright_version color_schemes widths; do
  grep -qF "Get-InputDefault \"$name\"" "$PS" || fail "scripts/a11y.ps1 does not read $name with Get-InputDefault"
done
grep -qF "templates/a11y/template.yml" "$PS" || fail "scripts/a11y.ps1 does not read templates/a11y/template.yml"

# 4. Neither runner hard-codes a pin. A non-comment line must not carry the
# image prefix or a package name followed by a digit; the container script
# installs from the A11Y_* variables its callers pass. Comment lines (first
# non-blank character #) are ignored.
pins=$(awk -v root="$ROOT" '
  {
    sub(/\r$/, "")
    fname = FILENAME
    pre = root "/"
    if (index(fname, pre) == 1) { fname = substr(fname, length(pre) + 1) }
    if ($0 ~ /^[[:space:]]*#/) next
    if ($0 ~ /mcr\.microsoft\.com\/playwright:v/) { print fname ":" FNR ": " $0; next }
    if ($0 ~ /axe-core@[0-9]/) { print fname ":" FNR ": " $0; next }
    if ($0 ~ /@axe-core\/playwright@[0-9]/) { print fname ":" FNR ": " $0; next }
    if ($0 ~ /playwright@[0-9]/) { print fname ":" FNR ": " $0 }
  }
' "$SH" "$PS" "$CON")
if [ -n "$pins" ]; then
  # One prefixed line per offending line; the loop is not a pipe, so fail's
  # status update survives.
  while IFS= read -r pin; do
    [ -n "$pin" ] || continue
    fail "a runner hard-codes a pin instead of reading it from templates/a11y/template.yml: $pin"
  done <<EOF
$pins
EOF
fi

# 5. Both runners pass the five names the container script needs, and the
# container script uses every one of them.
for name in A11Y_CONFIG A11Y_REPORT_DIR A11Y_PLAYWRIGHT_VERSION A11Y_AXE_PLAYWRIGHT_VERSION A11Y_AXE_CORE_VERSION; do
  grep -qF "$name" "$SH" || fail "scripts/a11y.sh does not pass $name to the container"
  grep -qF "$name" "$PS" || fail "scripts/a11y.ps1 does not pass $name to the container"
  grep -qF "$name" "$CON" || fail "scripts/a11y-container.sh does not use $name"
done

# 6. The options a consumer passes are still offered: the usage line of
# scripts/a11y.sh and the parameters of scripts/a11y.ps1.
usage=$(grep -F 'usage:' "$SH" | grep -F -- '--site=' | grep -F -- '--pages=' | grep -F -- '--tags=' | grep -F -- '--report=' | grep -F -- '--base-url=')
if [ -z "$usage" ]; then
  fail "the usage line of scripts/a11y.sh does not offer --site, --pages, --tags, --report and --base-url"
fi
for param in Site Pages Tags Report BaseUrl; do
  grep -qF "[string]\$$param" "$PS" || fail "scripts/a11y.ps1 no longer takes -$param"
done

# 7. Line endings: the .sh files carry no carriage return; the .ps1 has CRLF
# on every line.
if awk '/\r/ { found = 1 } END { exit found ? 0 : 1 }' "$SH"; then
  fail "scripts/a11y.sh contains a carriage return"
fi
if awk '/\r/ { found = 1 } END { exit found ? 0 : 1 }' "$CON"; then
  fail "scripts/a11y-container.sh contains a carriage return"
fi
# Every line ending in scripts/a11y.ps1 is CRLF. A record is a line ending
# when a later record follows it, so check each record against the one before
# it; the final record may lack a terminator.
if awk 'NR > 1 && prev !~ /\r$/ { bad = 1 } { prev = $0 } END { exit bad ? 0 : 1 }' "$PS"; then
  fail "scripts/a11y.ps1 does not have CRLF on every line"
fi

if [ "$status" -eq 0 ]; then
  echo "check-a11y-runner: ok"
fi
exit "$status"
