#!/bin/sh
# check-buildah-pin.sh: does every Buildah image reference pin an immutable tag?
#
# Red Hat re-pushed the plain version tag of the quay.io/buildah/stable image
# and garbage-collected the old digest, so a pipeline pinned to the mutable
# tag broke. Every reference to that image in the repository must now name an
# -immutable tag pinned by digest.
#
# The script lists the tracked files with git ls-files and scans their text
# for a reference to that image whose tag is missing or does not end in
# -immutable@sha256:. Changelog history is exempt (CHANGELOG.md,
# docs/changelog.md and site/docs/changelog.*), and so is the generated site/
# tree, which the lead rebuilds from docs/. It needs no yq and runs in the
# mikefarah/yq image and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-buildah-pin: $1" >&2
  status=1
}

if ! files=$(git -C "$ROOT" ls-files 2>/dev/null); then
  fail "git ls-files failed in $ROOT"
  exit 1
fi

# An acceptable tag ends in -immutable@sha256:<hex>. The image name is built
# in two pieces so this script does not carry a reference of its own.
ok_tag='-immutable@sha256:[0-9a-fA-F]+$'
prefix='quay.io/buildah/stable'
prefix="$prefix:"

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  # Changelog history may quote the old tag; the generated site/ tree is
  # rebuilt from docs/, so neither is checked.
  case $rel in
    CHANGELOG.md|docs/changelog.md|site/*) continue ;;
  esac
  [ -f "$ROOT/$rel" ] || continue
  # grep -I skips binary files (images, fonts); the check is about text.
  grep -qIE 'quay\.io/buildah/stable:' "$ROOT/$rel" || continue
  report=$(awk -v rel="$rel" -v okre="$ok_tag" -v pre="$prefix" '
    {
      rest = $0
      while (match(rest, /quay\.io\/buildah\/stable:/)) {
        rest = substr(rest, RSTART + RLENGTH)
        tag = rest
        sub(/[^A-Za-z0-9._~:+@-].*$/, "", tag)
        if (tag !~ okre) {
          print rel ":" FNR ": buildah tag is not an -immutable digest pin: " pre tag
        }
      }
    }' "$ROOT/$rel")
  if [ -n "$report" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      fail "$line"
    done <<EOF
$report
EOF
  fi
done <<EOF
$files
EOF

if [ "$status" -eq 0 ]; then
  echo "check-buildah-pin: ok"
fi
exit "$status"
