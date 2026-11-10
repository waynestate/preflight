#!/bin/sh
# check-secret-detection.sh: does Preflight's own pipeline run GitLab's
# pipeline secret detection?
#
# A secret committed to the repo stays in its history, so the repo's own
# pipeline should scan for one before it ships. GitLab's secret detection
# template reports its findings in a job named secret_detection, and the
# template sets allow_failure: true on it, so the repo must override that
# or the job is only advisory. This script checks the include line and the
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

# The job must block: GitLab's template sets allow_failure: true, so the
# repo must override it. Fail when there is no top-level secret_detection:
# key, when allow_failure: true appears within three lines after it, or
# when allow_failure: false does not appear within three lines after it.
verdict=$(awk '
  /^secret_detection:/ { key = NR }
  key > 0 && NR > key && NR - key <= 3 && /allow_failure:[[:space:]]*true/ { t = 1 }
  key > 0 && NR > key && NR - key <= 3 && /allow_failure:[[:space:]]*false/ { f = 1 }
  END {
    if (key == 0) print "none"
    else if (t) print "true"
    else if (f) print "false"
    else print "missing"
  }
' "$CI")
case "$verdict" in
  none)
    fail "secret_detection has no override; GitLab's template makes it advisory, so .gitlab-ci.yml must set allow_failure: false"
    ;;
  true)
    fail "secret_detection is advisory (allow_failure: true within 3 lines after secret_detection:); the job must block"
    ;;
  missing)
    fail "secret_detection does not set allow_failure: false within 3 lines; the job must block"
    ;;
esac

if [ "$status" -eq 0 ]; then
  echo "check-secret-detection: ok"
fi
exit "$status"
