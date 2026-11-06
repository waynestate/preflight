#!/bin/sh
# check-proctor-install-flags.sh: does the proctor template install the app
# without running its plugins and scripts?
#
# The proctor job only inspects the app, so the app's plugins and scripts must
# not run with the job's access. A hostile composer.json could otherwise use
# them to execute code inside the job, so the composer install line must carry
# both --no-plugins and --no-scripts. Neither the proctor job nor the sbom job
# runs the app, so both install with --ignore-platform-reqs, and the sbom job
# with --no-scripts. This script checks the lines with plain
# grep/sed, so it needs no yq and runs in the mikefarah/yq image and on any
# Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/proctor/template.yml"

status=0

fail() {
  echo "check-proctor-install-flags: $1" >&2
  status=1
}

if [ ! -f "$TPL" ]; then
  fail "proctor: templates/proctor/template.yml is missing"
  exit "$status"
fi

install_line=$(grep -E 'composer[[:blank:]]+install' "$TPL" | head -n 1 || true)
if [ -z "$install_line" ]; then
  fail "proctor: no composer install line found in templates/proctor/template.yml"
  exit "$status"
fi

case $install_line in
  *--no-plugins*) ;;
  *) fail "proctor: the composer install line is missing --no-plugins" ;;
esac
case $install_line in
  *--no-scripts*) ;;
  *) fail "proctor: the composer install line is missing --no-scripts" ;;
esac
# The job never runs the app, so an app locked to an older PHP, or needing an
# extension the image lacks, must still get its report (proof run 2026-11-05).
case $install_line in
  *--ignore-platform-reqs*) ;;
  *) fail "proctor: the composer install line is missing --ignore-platform-reqs" ;;
esac

# The sbom job only lists what the lock installs: no app scripts, no platform
# requirements.
SBOM="$ROOT/templates/sbom/template.yml"
sbom_line=$(grep -E 'composer[[:blank:]]+install' "$SBOM" | head -n 1 || true)
if [ -z "$sbom_line" ]; then
  fail "sbom: no composer install line found in templates/sbom/template.yml"
else
  case $sbom_line in
    *--no-scripts*) ;;
    *) fail "sbom: the composer install line is missing --no-scripts" ;;
  esac
  case $sbom_line in
    *--ignore-platform-reqs*) ;;
    *) fail "sbom: the composer install line is missing --ignore-platform-reqs" ;;
  esac
fi

if [ "$status" -eq 0 ]; then
  echo "check-proctor-install-flags: ok"
fi
exit "$status"
