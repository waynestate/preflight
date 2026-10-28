#!/bin/sh
# check-github-workflow.sh: are the GitHub Actions workflows safe to run?
#
# A reusable workflow runs with the permissions the caller gives it, and an
# unpinned action can be repointed to run arbitrary code. This script checks
# the two things that keep a workflow honest:
#   1. every `uses:` is pinned to a full 40-hex commit SHA (or is a local
#      `./` action), so a repointed tag cannot change what runs; and
#   2. `permissions` grants nothing beyond `read` or `none`, so the workflow
#      cannot write back to the caller's repository.
#
# POSIX sh, so it runs in the mikefarah/yq image and on any Linux or macOS
# box. Needs yq v4 (mikefarah/yq) for the permissions check; the pinning check
# is plain grep/sed.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WFDIR="$ROOT/.github/workflows"

if [ ! -d "$WFDIR" ]; then
  echo ".github/workflows not found at $WFDIR" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "yq v4 (mikefarah/yq) is required" >&2
  exit 1
fi

status=0
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

for wf in "$WFDIR"/*.yml; do
  [ -f "$wf" ] || continue
  wf_status=0
  rel=${wf#"$ROOT"/}

  # --- 1. every uses: is pinned to a full commit SHA -----------------------
  # Extract each uses: value (owner/repo@ref or ./local), one per line: strip
  # the leading `uses:` (and the list dash when the step is written as
  # `- uses:`) and any trailing comment.
  grep -E '^[[:space:]]*(-[[:space:]]+)?uses:' "$wf" \
    | sed -E 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//; s/[[:space:]]*#.*$//' \
    > "$tmpdir/uses"

  while IFS= read -r value; do
    [ -n "$value" ] || continue
    case "$value" in
      ./*) continue ;;  # a local action lives in the repo; nothing to pin
    esac
    if ! printf '%s\n' "$value" | grep -qE '^[^@]+@[0-9a-f]{40}$'; then
      echo "$rel: unpinned action: $value"
      wf_status=1
    fi
  done < "$tmpdir/uses"

  # --- 2. permissions grant only read or none ------------------------------
  # The permissions key may be a scalar (permissions: read) or a map
  # (permissions: { contents: read }). A reusable workflow must set one, so a
  # missing key is a failure. Extract every value either way, then reject
  # anything that is not read or none.
  perm_tag=$(yq eval '.permissions | tag' "$wf")
  if [ "$perm_tag" = "!!null" ]; then
    echo "$rel: no permissions key (a reusable workflow must set one)"
    wf_status=1
  else
    yq eval '.permissions | if (tag) == "!!map" then to_entries[].value else . end' "$wf" \
      > "$tmpdir/perms"
    while IFS= read -r perm; do
      [ -n "$perm" ] || continue
      case "$perm" in
        read|none) ;;
        *)
          echo "$rel: permission '$perm' is not read or none"
          wf_status=1
          ;;
      esac
    done < "$tmpdir/perms"
  fi

  if [ "$wf_status" -eq 0 ]; then
    echo "$rel: actions pinned, permissions read-only"
  fi
  if [ "$wf_status" -ne 0 ]; then
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "github workflows: all actions pinned, all permissions read-only"
fi
exit "$status"
