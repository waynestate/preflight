#!/bin/sh
# a11y-consumer-kit.sh: keep templates/a11y/consumer/ honest.
#
# The consumer kit is the single local a11y runner every stack repo copies
# into tools/a11y/ (D-110): a11y.sh and a11y.ps1 read their image and versions
# from a11y-pin.json at run time, and check.mjs is the component's own checker.
# This script rewrites the pin manifest from the defaults in
# templates/a11y/template.yml and the newest released version in
# CHANGELOG.md, refreshes the two-line "Copied from Preflight" header in both
# runners, and copies the checker over. With --check it only compares and
# exits 1 when the kit is stale; that is what the contract job runs, so a
# bumped release or a moved pin fails the pipeline until the kit is rewritten.
#
#   sh scripts/a11y-consumer-kit.sh            rewrite the kit
#   sh scripts/a11y-consumer-kit.sh --check    exit 1 when the kit is stale
#
# Plain awk, sed, tail and cmp, so it runs in the mikefarah/yq image and on
# any Linux or macOS box. Its twin, a11y-consumer-kit.ps1, does the same on
# Windows.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

CHECK=0
for arg in "$@"; do
  case $arg in
    --check) CHECK=1 ;;
    *)
      echo "usage: sh scripts/a11y-consumer-kit.sh [--check]" >&2
      exit 2
      ;;
  esac
done

TPL=templates/a11y/template.yml
KIT=templates/a11y/consumer

# The default of one input in the component's spec, without YAML quotes. The
# same reader as scripts/a11y.sh, so the kit cannot drift from the jobs.
default_of() {
  awk -v key="    $1:" '
    $0 == key { inblock = 1; next }
    inblock && /^    [A-Za-z_]/ { exit }
    inblock && /^      default:/ { sub(/^      default:[ \t]*/, ""); print; exit }
  ' "$TPL" | sed 's/^"\(.*\)"$/\1/'
}

IMAGE=$(default_of image)
AXE_CORE=$(default_of axe_core_version)
AXE_PW=$(default_of axe_playwright_version)
PW=$(printf '%s\n' "$IMAGE" | sed -n 's/^.*playwright:v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p')
VERSION=$(awk '/^## / && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ { print $2; exit }' CHANGELOG.md)
if [ -z "$IMAGE" ] || [ -z "$AXE_CORE" ] || [ -z "$AXE_PW" ] || [ -z "$PW" ] || [ -z "$VERSION" ]; then
  echo "a11y-consumer-kit: cannot read the image, versions or version from $TPL and CHANGELOG.md" >&2
  exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The pin manifest: the Preflight release the kit was copied from, and the
# image and versions that release pinned. Fixed key order, LF, trailing
# newline; the runners read it with awk, so no JSON tooling is needed.
printf '{\n  "preflight": "%s",\n  "image": "%s",\n  "playwright": "%s",\n  "axe_playwright": "%s",\n  "axe_core": "%s"\n}\n' \
  "$VERSION" "$IMAGE" "$PW" "$AXE_PW" "$AXE_CORE" > "$TMP/a11y-pin.json"

cp templates/a11y/check.mjs "$TMP/check.mjs"

H1="# Copied from Preflight $VERSION; do not edit; refresh with the copy step in"
H2="# docs/guides/component-a11y.md."
CR=$(printf '\r')

# Refresh the two-line "Copied from Preflight" header of a runner, keeping
# its line endings: git checks out .ps1 as CRLF and everything else as LF,
# and the test holds each to that. The .sh keeps its shebang on line 1, so
# its header starts on line 2; the .ps1 has no shebang, so its header starts
# on line 1.
refresh_header() {
  file=$1
  out=$2
  start=$3
  first=$(head -n 1 "$file")
  if [ "$start" -gt 1 ]; then
    head -n "$((start - 1))" "$file" > "$out"
  else
    : > "$out"
  fi
  case $first in
    *"$CR") printf '%s\r\n%s\r\n' "$H1" "$H2" >> "$out" ;;
    *) printf '%s\n%s\n' "$H1" "$H2" >> "$out" ;;
  esac
  tail -n +"$((start + 2))" "$file" >> "$out"
}

for name in a11y.sh a11y.ps1; do
  if [ ! -f "$KIT/$name" ]; then
    echo "a11y-consumer-kit: missing $KIT/$name" >&2
    exit 2
  fi
  if [ "$name" = a11y.sh ]; then
    refresh_header "$KIT/$name" "$TMP/$name" 2
  else
    refresh_header "$KIT/$name" "$TMP/$name" 1
  fi
done

stale=""
if ! cmp -s "$TMP/a11y-pin.json" "$KIT/a11y-pin.json"; then stale="$stale a11y-pin.json"; fi
if ! cmp -s "$TMP/check.mjs" "$KIT/check.mjs"; then stale="$stale check.mjs"; fi
for name in a11y.sh a11y.ps1; do
  if ! cmp -s "$TMP/$name" "$KIT/$name"; then stale="$stale $name"; fi
done

if [ "$CHECK" = 1 ]; then
  if [ -n "$stale" ]; then
    echo "a11y-consumer-kit: stale:$stale; run sh scripts/a11y-consumer-kit.sh" >&2
    exit 1
  fi
  echo "a11y-consumer-kit: ok"
  exit 0
fi

mkdir -p "$KIT"
cp "$TMP/a11y-pin.json" "$KIT/a11y-pin.json"
cp "$TMP/check.mjs" "$KIT/check.mjs"
cp "$TMP/a11y.sh" "$KIT/a11y.sh"
cp "$TMP/a11y.ps1" "$KIT/a11y.ps1"
echo "a11y-consumer-kit: wrote templates/a11y/consumer/ from Preflight $VERSION"
