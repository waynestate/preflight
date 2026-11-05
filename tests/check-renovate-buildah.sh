#!/bin/sh
# check-renovate-buildah.sh: does the preset keep buildah on -immutable tags?
#
# Red Hat re-pushed buildah v1.43.5 and garbage-collected the old digest,
# which broke an image job. DRAWBRIDGE and SQUIRE now pin the -immutable
# form (v1.43.5-immutable@sha256:...), so the shared preset must only
# match -immutable tags for quay.io/buildah/stable and keep pinning
# digests. This script checks renovate/default.json with plain text
# matching, so it needs no yq and runs in the mikefarah/yq image and on
# any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

RENOVATE="$ROOT/renovate/default.json"

status=0

fail() {
  echo "check-renovate-buildah: $1" >&2
  status=1
}

if [ ! -f "$RENOVATE" ]; then
  fail "renovate/default.json is missing"
  exit "$status"
fi

# No yq in the logic, so "parses as JSON" is checked the cheap way: the
# document opens with { on its first line and closes with } on its last.
if [ "$(head -n 1 "$RENOVATE")" != "{" ]; then
  fail "renovate/default.json does not open with {"
fi
if [ "$(tail -n 1 "$RENOVATE")" != "}" ]; then
  fail "renovate/default.json does not close with }"
fi

# The buildah rule: a matchPackageNames entry for quay.io/buildah/stable
# must sit in a rule whose versioning or allowedVersions mentions
# -immutable, within the same object.
if ! awk '
  /"matchPackageNames".*"quay\.io\/buildah\/stable"/ { key = NR }
  key > 0 && NR >= key && NR - key <= 4 && /("versioning"|"allowedVersions").*-immutable/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$RENOVATE"; then
  fail "the quay.io/buildah/stable rule does not restrict versions to -immutable tags"
fi

# Digests stay pinned: docker:pinDigests must still be in extends.
if ! grep -q '"docker:pinDigests"' "$RENOVATE"; then
  fail "renovate/default.json no longer carries docker:pinDigests in extends"
fi

if [ "$status" -eq 0 ]; then
  echo "check-renovate-buildah: ok"
fi
exit "$status"
