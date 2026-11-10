#!/bin/sh
# check-portability-inline.sh: does the portability template carry
# templates/portability/probe.sh byte for byte?
#
# A GitLab component ships only its template.yml, so the portability job
# writes the probe from a heredoc in the template. The readable source is
# templates/portability/probe.sh, which tests/check-portability.sh runs
# against the fixtures. This test fails when the two drift apart, so the
# must-fail fixtures and a consumer's pipeline always probe the same way.
#
#   sh tests/check-portability-inline.sh          check (exit 0 in step, 1 drifted)
#   sh tests/check-portability-inline.sh --write  copy probe.sh into the heredoc
#
# The heredoc sits in a YAML block scalar indented by six spaces: each line
# of probe.sh is written with six spaces in front, and blank lines stay
# blank. POSIX sh and awk, so it runs in the mikefarah/yq image and on any
# Linux or macOS box. Its twin, check-portability-inline.ps1, does the same
# on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TPL="$ROOT/templates/portability/template.yml"
SRC="$ROOT/templates/portability/probe.sh"
START="      cat > /tmp/portability-probe.sh <<'PREFLIGHT_PORTABILITY_PROBE'"
END="      PREFLIGHT_PORTABILITY_PROBE"

for f in "$TPL" "$SRC"; do
  if [ ! -f "$f" ]; then
    echo "check-portability-inline: missing ${f#"$ROOT"/}" >&2
    exit 1
  fi
done

starts=$(grep -cxF "$START" "$TPL")
ends=$(grep -cxF "$END" "$TPL")
if [ "$starts" -ne 1 ] || [ "$ends" -ne 1 ]; then
  echo "check-portability-inline: templates/portability/template.yml needs exactly one heredoc start and end line for probe.sh" >&2
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
  echo "check-portability-inline: wrote templates/portability/probe.sh into templates/portability/template.yml"
  exit 0
fi

awk -v start="$START" -v end="$END" '
  $0 == end { inside = 0 }
  inside { print }
  $0 == start { inside = 1 }
' "$TPL" > "$tmpdir/inlined"

if ! cmp -s "$tmpdir/indented" "$tmpdir/inlined"; then
  echo "check-portability-inline: the heredoc in templates/portability/template.yml differs from templates/portability/probe.sh; run sh tests/check-portability-inline.sh --write" >&2
  exit 1
fi

# GitLab interpolates $[[ ... ]] everywhere in a template, heredoc included.
if grep -qF '$[[' "$SRC"; then
  echo "check-portability-inline: templates/portability/probe.sh contains \$[[, which GitLab would interpolate" >&2
  exit 1
fi

# session_header: declared as an input, passed into the probe, resolved from
# the job environment with printenv, and never through eval.
if ! grep -qxF '    session_header:' "$TPL"; then
  echo "check-portability-inline: templates/portability/template.yml has no session_header input" >&2
  exit 1
fi
if ! grep -qxF '      session_header=$[[ inputs.session_header ]]' "$TPL"; then
  echo "check-portability-inline: the inputs heredoc does not pass session_header to the probe" >&2
  exit 1
fi
if ! grep -qF 'printenv' "$SRC"; then
  echo "check-portability-inline: templates/portability/probe.sh does not resolve session_header with printenv" >&2
  exit 1
fi
if grep -qE '(^|[[:space:];|&(`])eval[[:space:]]' "$SRC"; then
  echo "check-portability-inline: templates/portability/probe.sh uses eval" >&2
  exit 1
fi

echo "check-portability-inline: ok"
exit 0
