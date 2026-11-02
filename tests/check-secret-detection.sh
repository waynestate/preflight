#!/bin/sh
# check-secret-detection.sh: does Preflight's own pipeline run GitLab's
# pipeline secret detection?
#
# A secret committed to the repo stays in its history, so the repo's own
# pipeline should scan for one before it ships. GitLab's secret detection
# template reports its findings in a job named secret_detection; until it has
# a week of green pipelines the job is advisory (allow_failure: true), so it
# warns without blocking. This script checks the include line and the job
# override with plain text matching, so it needs no yq and runs in the
# mikefarah/yq image and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

CI="$ROOT/.gitlab-ci.yml"

status=0

fail() {
  echo "check-secret-detection: $1" >&2
  status=1
}

if [ ! -f "$CI" ]; then
  fail ".gitlab-ci.yml is missing"
  exit "$status"
fi

if ! grep -q 'Jobs/Secret-Detection.gitlab-ci.yml' "$CI"; then
  fail ".gitlab-ci.yml does not include Jobs/Secret-Detection.gitlab-ci.yml"
fi

# The override job must carry allow_failure: true within three lines after
# the top-level secret_detection: key.
if ! awk '
  /^secret_detection:/ { key = NR }
  key > 0 && NR > key && NR - key <= 3 && /allow_failure:[[:space:]]*true/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$CI"; then
  fail "secret_detection: is not followed within 3 lines by allow_failure: true"
fi

if [ "$status" -eq 0 ]; then
  echo "check-secret-detection: ok"
fi
exit "$status"
