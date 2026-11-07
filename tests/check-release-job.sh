#!/bin/sh
# check-release-job.sh: does the repository's own pipeline create the
# GitLab Release from a tag?
#
# Preflight's own .gitlab-ci.yml carries a release job that runs only on a
# tag and posts to the Releases API with curl, because the runner is
# arm64 and the official image for creating releases has no arm64 build.
# The release notes must carry the tag's commit SHA so consumers can pin
# it (BEST_PRACTICES 1.6). This check fails if any part of that contract
# is broken:
#
#   * the top-level release: job disappears;
#   * the job stops running only on a tag (if: $CI_COMMIT_TAG);
#   * the job stops posting to /releases with the JOB-TOKEN header and the
#     commit SHA;
#   * the job starts using the release-cli image again;
#   * the release stage leaves the stage list or moves before audit; or
#   * the job image loses its digest pin.
#
# The script greps the release job block of .gitlab-ci.yml, so it needs no
# yq and runs in the mikefarah/yq image and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CI_FILE="$ROOT/.gitlab-ci.yml"

status=0
fail() {
  echo "check-release-job: $1" >&2
  status=1
}

if [ ! -f "$CI_FILE" ]; then
  fail ".gitlab-ci.yml is missing"
  exit 1
fi

# The top-level release: job must exist.
if ! grep -qE '^release:[ ]*$' "$CI_FILE"; then
  fail "no top-level release: job in .gitlab-ci.yml"
  exit 1
fi

# The job block runs from release: until the next zero-indent line.
block=$(awk '
  /^release:[ ]*$/ { inblock = 1 }
  inblock {
    if (started && /^[^ ]/) exit
    print
    started = 1
  }
' "$CI_FILE")

has() {
  printf '%s\n' "$block" | grep -qF "$1"
}

# The job runs only on a tag, never on branches or merge requests.
if ! has 'if: $CI_COMMIT_TAG'; then
  fail 'release job has no "if: $CI_COMMIT_TAG" rule'
fi

# The job posts to the Releases API with the job token and the commit SHA.
if ! has 'JOB-TOKEN'; then
  fail 'release job does not send the JOB-TOKEN header'
fi
if ! has '$CI_COMMIT_SHA'; then
  fail 'release job does not carry $CI_COMMIT_SHA'
fi
if ! has '/releases'; then
  fail 'release job does not post to /releases'
fi

# The job stays on curl: the release-cli image has no arm64 build.
if has 'release-cli'; then
  fail 'release job references the release-cli image'
fi

# The job image keeps its digest pin.
if ! printf '%s\n' "$block" | grep -qE '(image|name):.*@sha256:'; then
  fail 'release job image is not pinned by digest'
fi

# The release stage stays in the stage list, after audit.
stages=$(awk '
  /^stages:[ ]*$/ { instages = 1; next }
  instages {
    if ($0 ~ /^[ ]*-[ ]/) { sub(/^[ ]*-[ ]+/, ""); print; next }
    exit
  }
' "$CI_FILE")
order=$(printf '%s\n' "$stages" | awk '
  $0 == "audit" { audit = NR }
  $0 == "release" { release = NR }
  END { if (audit > 0 && release > 0 && release > audit) print "ok"; else print "bad" }
')
if [ "$order" != "ok" ]; then
  fail 'stages: must list release after audit'
fi

if [ "$status" -eq 0 ]; then
  echo "check-release-job: ok"
fi
exit "$status"
