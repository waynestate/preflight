#!/bin/sh
# check-secret-detection.sh: does Preflight's own pipeline run GitLab's
# pipeline secret detection?
#
# A secret committed to the repo stays in its history, so the repo's own
# pipeline should scan for one before it ships. GitLab's secret detection
# template reports its findings in a job named secret_detection; the job
# blocked after a week of green runs (2026-11-02 to 2026-11-10), and this
# check keeps anyone from quietly making it advisory again. This script
# checks the include line and that the job blocks with plain text matching,
# so it needs no yq and runs in the mikefarah/yq image and on any Linux or
# macOS box.

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

# The job must block: fail when a top-level secret_detection: key is followed
# within three lines by allow_failure: true. No key at all is fine: the
# included template's job blocks by default.
if awk '
  /^secret_detection:/ { key = NR }
  key > 0 && NR > key && NR - key <= 3 && /allow_failure:[[:space:]]*true/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$CI"; then
  fail "secret_detection is advisory (allow_failure: true within 3 lines after secret_detection:); the job must block"
fi

if [ "$status" -eq 0 ]; then
  echo "check-secret-detection: ok"
fi
exit "$status"
