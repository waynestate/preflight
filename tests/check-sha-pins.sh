#!/bin/sh
# check-sha-pins.sh: do the published examples pin Preflight by commit SHA?
#
# A tag can move, a SHA cannot, so every example in the README, the front
# page and examples/ pins each component and the GitHub workflow at the full
# commit SHA of the release tag, with the tag kept in a trailing comment.
# This script greps those files for a component or workflow ref whose version
# starts with a digit but is not a full 40-character SHA, so it needs no yq
# and runs in the mikefarah/yq image and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "check-sha-pins: $1" >&2
  status=1
}

# A ref is bare when its version starts with a digit and is not a full
# 40-character SHA: preflight/<component>@0.1.1 or php-package.yml@0.1.1.
BARE_RE='(preflight/[a-z-]*|php-package\.yml)@[0-9]'
SHA_RE='(preflight/[a-z-]*|php-package\.yml)@[0-9a-f]{40}'

{
  echo "$ROOT/README.md"
  echo "$ROOT/site/index.md"
  find "$ROOT/examples" -type f | LC_ALL=C sort
} > "$tmpdir/files"

while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel=${f#"$ROOT"/}
  if [ ! -f "$f" ]; then
    fail "$rel is missing"
    continue
  fi
  hits=$(grep -nE "$BARE_RE" "$f" | grep -vE "$SHA_RE" || true)
  if [ -n "$hits" ]; then
    fail "$rel carries a bare version ref:"
    printf '%s\n' "$hits" >&2
  fi
done < "$tmpdir/files"

if [ "$status" -eq 0 ]; then
  echo "check-sha-pins: ok"
fi
exit "$status"
