#!/bin/sh
# check-buildah-pin.sh: does every Buildah image reference pin an immutable tag?
#
# Red Hat re-pushed the plain version tag of the quay.io/buildah/stable image
# and garbage-collected the old digest, so a pipeline pinned to the mutable
# tag broke. Every reference to that image in the repository must now name an
# -immutable tag pinned by digest.
#
# The script lists the files to scan with git ls-files when git is available
# and works in the repository root, and otherwise falls back to a POSIX find
# over the working tree (regular files, skipping the .git, vendor/ and
# node_modules/ directories, paths relative to the root with no leading ./,
# the same form git ls-files uses). It scans each file's text for a reference
# to that image whose tag is missing or does not end in -immutable@sha256:.
# Changelog history is exempt (CHANGELOG.md, docs/changelog.md and
# site/docs/changelog.*), and so is the generated site/ tree, which the lead
# rebuilds from docs/. It needs no yq and runs with or without git, in the
# mikefarah/yq image (which has no git) and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-buildah-pin: $1" >&2
  status=1
}

# Prefer git ls-files. When git is missing (the mikefarah/yq image has
# none) or cannot list $ROOT, fall back to find over the working tree. Both
# list paths relative to $ROOT with no leading ./, so the exemptions below
# match either way. The fallback notices on stderr but does not fail the
# check by itself; command -v keeps the shell quiet when git is absent.
if command -v git >/dev/null 2>&1 && files=$(git -C "$ROOT" ls-files 2>/dev/null); then
  :
else
  echo "check-buildah-pin: git unavailable, scanning files with find" >&2
  files=$(cd -- "$ROOT" && find . \( -name .git -o -name vendor -o -name node_modules \) -prune -o -type f -print | sed 's|^\./||')
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
