#!/bin/sh
# check-a11y-inline.sh: does the a11y template carry templates/a11y/check.mjs
# byte for byte?
#
# A GitLab component ships only its template.yml, so the a11y job writes the
# checker from a heredoc in the template. The readable source is
# templates/a11y/check.mjs, which scripts/a11y.sh and scripts/a11y.ps1 run
# locally. This test fails when the two drift apart, so a local run and a
# pipeline run always check the same way.
#
#   sh tests/check-a11y-inline.sh          check (exit 0 in step, 1 drifted)
#   sh tests/check-a11y-inline.sh --write  copy check.mjs into the heredoc
#
# The heredoc sits in a YAML block scalar indented by six spaces: each line
# of check.mjs is written with six spaces in front, and blank lines stay
# blank. POSIX sh and awk, so it runs in the mikefarah/yq image and on any
# Linux or macOS box. Its twin, check-a11y-inline.ps1, does the same on
# Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TPL="$ROOT/templates/a11y/template.yml"
SRC="$ROOT/templates/a11y/check.mjs"
START="      cat > \"\$A11Y_HOME/check.mjs\" <<'PREFLIGHT_A11Y_CHECK'"
END="      PREFLIGHT_A11Y_CHECK"

for f in "$TPL" "$SRC"; do
  if [ ! -f "$f" ]; then
    echo "check-a11y-inline: missing ${f#"$ROOT"/}" >&2
    exit 1
  fi
done

starts=$(grep -cxF "$START" "$TPL")
ends=$(grep -cxF "$END" "$TPL")
if [ "$starts" -ne 1 ] || [ "$ends" -ne 1 ]; then
  echo "check-a11y-inline: templates/a11y/template.yml needs exactly one heredoc start and end line for check.mjs" >&2
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# The source as the template must carry it: six spaces in front, blank lines
# left blank.
awk '{ if ($0 == "") print ""; else print "      " $0 }' "$SRC" > "$tmpdir/indented"

if [ "${1:-}" = "--write" ]; then
  awk -v start="$START" -v end="$END" -v body="$tmpdir/indented" '
    $0 == start { print; while ((getline line < body) > 0) print line; skip = 1; next }
    $0 == end { skip = 0 }
    !skip { print }
  ' "$TPL" > "$tmpdir/template.yml"
  cat "$tmpdir/template.yml" > "$TPL"
  echo "check-a11y-inline: wrote templates/a11y/check.mjs into templates/a11y/template.yml"
  exit 0
fi

awk -v start="$START" -v end="$END" '
  $0 == end { inside = 0 }
  inside { print }
  $0 == start { inside = 1 }
' "$TPL" > "$tmpdir/inlined"

if ! cmp -s "$tmpdir/indented" "$tmpdir/inlined"; then
  echo "check-a11y-inline: the heredoc in templates/a11y/template.yml differs from templates/a11y/check.mjs; run sh tests/check-a11y-inline.sh --write" >&2
  exit 1
fi

# GitLab interpolates $[[ ... ]] everywhere in a template, heredoc included.
if grep -qF '$[[' "$SRC"; then
  echo "check-a11y-inline: templates/a11y/check.mjs contains \$[[, which GitLab would interpolate" >&2
  exit 1
fi

echo "check-a11y-inline: ok"
exit 0
