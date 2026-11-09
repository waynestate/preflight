#!/bin/sh
# check-package-publish-fails.sh: do the package-publish component's
# offline guards still stop a bad release?
#
# The package-publish component checks the tag and the package name before
# it touches the registry: a tag that is not a semantic version and a
# project root without a composer.json must both fail the job. This script
# checks that the template keeps those guards (the semver grep -Eq line,
# the "is not a semantic version" message with its exit 1, and the
# "composer.json not found" message), then extracts the template's first
# two script blocks (the tag guard and the composer.json guard; they hold
# no $[[ inputs ]] and so run as plain sh) and performs them on copies of
# the fixtures in a temp dir:
#
#   tests/package-publish-badtag, CI_COMMIT_TAG=not-a-version
#       exit 1, the output names "is not a semantic version"
#       (the must-fail case)
#   tests/package-publish-nocomposer, CI_COMMIT_TAG=1.2.3
#       exit 1, the output names "composer.json not found"
#       (the must-fail case)
#   tests/package-publish-badtag, CI_COMMIT_TAG=v1.2.3
#       exit 0 (the clean case)
#
# It runs inside the template's image (composer:2.10.3, pinned by digest in
# templates/package-publish/template.yml), which ships the php the name
# guard needs. The moved-version path talks to the registry and stays
# untested here. One result line per case goes to stdout; a fixture's
# output is printed only for a case that went wrong.
# Run it with
#
#   docker run --rm -v "$(pwd):/app" -w /app \
#     composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 \
#     sh tests/check-package-publish-fails.sh
#
# Its twin, check-package-publish-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/package-publish/template.yml"

status=0
fail() {
  echo "check-package-publish-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/package-publish/template.yml"
[ -f "$ROOT/tests/package-publish-badtag/composer.json" ] || fail "fixture missing: tests/package-publish-badtag"
[ -f "$ROOT/tests/package-publish-nocomposer/README.md" ] || fail "fixture missing: tests/package-publish-nocomposer"
[ "$status" -eq 0 ] || exit 1

# (a) the template keeps the offline guards: the semver grep -Eq line, the
# two failure messages, and an exit 1 right after the semver message.
want_semver=$(cat <<'EOF'
      if ! printf '%s\n' "$tag" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'; then
EOF
)
grep -Fxq -- "$want_semver" "$TPL" \
  || fail "the template dropped the semver guard's grep -Eq line"
msg_line=$(grep -nF -- 'is not a semantic version' "$TPL" | head -n 1 | cut -d: -f1)
if [ -z "$msg_line" ]; then
  fail "the template dropped the semver guard's message"
else
  [ "$(sed -n "$((msg_line + 1))p" "$TPL")" = "        exit 1" ] \
    || fail "the semver guard no longer exits 1 after its message"
fi
grep -Fq -- 'composer.json not found in the project root.' "$TPL" \
  || fail "the template dropped the composer.json guard's message"

# (b) the jobs document is everything after the last `---` line; its first
# two `|` script blocks are the tag guard and the composer.json guard.
# Strip their six-space block indent so they run as plain sh.
sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
[ -n "$sep" ] || { fail "no '---' separator between the spec and jobs documents"; exit 1; }
guards=$(awk -v n="$sep" '
  NR > n && /^    - \|$/ { blocks++; if (blocks > 2) exit }
  NR > n && blocks >= 1 && blocks <= 2 {
    if ($0 ~ /^    - /) next
    if ($0 ~ /^  [A-Za-z"]/) exit
    line = $0
    sub(/^      /, "", line)
    print line
  }
' "$TPL")
[ -n "$guards" ] || { fail "no script blocks extracted from the template"; exit 1; }
printf '%s\n' "$guards" | grep -Fq -- 'is not a semantic version' \
  || { fail "the extracted guards lost the tag guard"; exit 1; }
printf '%s\n' "$guards" | grep -Fq -- 'composer.json not found' \
  || { fail "the extracted guards lost the composer.json guard"; exit 1; }
if printf '%s\n' "$guards" | grep -Fq -- '$[['; then
  fail "the extracted guards hold an input interpolation; they no longer run as plain sh"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$guards" > "$tmp/guards.sh"

# run <name> <dir> <tag>: copy the fixture to a temp dir, run the
# template's own guards there, keep the log and the exit code.
run() {
  name=$1
  dir=$2
  tag=$3
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  (cd "$work" && CI_COMMIT_TAG="$tag" sh "$tmp/guards.sh") > "$tmp/$name.log" 2>&1
  echo $?
}

# must-fail: a tag that is not a semantic version stops the release.
code=$(run badtag tests/package-publish-badtag not-a-version)
ok=1
[ "$code" -ne 0 ] || { fail "package-publish badtag: exit 0, expected non-zero"; ok=0; }
grep -Fq "is not a semantic version" "$tmp/badtag.log" || { fail "package-publish badtag: the output does not name the semver guard"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "package-publish badtag: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/badtag.log" >&2
fi

# must-fail: a project root without a composer.json stops the release.
code=$(run nocomposer tests/package-publish-nocomposer 1.2.3)
ok=1
[ "$code" -ne 0 ] || { fail "package-publish nocomposer: exit 0, expected non-zero"; ok=0; }
grep -Fq "composer.json not found in the project root." "$tmp/nocomposer.log" || { fail "package-publish nocomposer: the output does not name the composer.json guard"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "package-publish nocomposer: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/nocomposer.log" >&2
fi

# clean: a semantic tag and a usable composer.json pass the offline guards.
code=$(run clean tests/package-publish-badtag v1.2.3)
ok=1
[ "$code" -eq 0 ] || { fail "package-publish clean: exit $code, expected 0"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "package-publish clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/clean.log" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "check-package-publish-fails: ok"
fi
exit "$status"
