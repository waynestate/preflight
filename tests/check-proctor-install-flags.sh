#!/bin/sh
# check-proctor-install-flags.sh: does the proctor template install the app
# without running its plugins and scripts?
#
# The proctor job only inspects the app, so the app's plugins and scripts must
# not run with the job's access. A hostile composer.json could otherwise use
# them to execute code inside the job, so the composer install line must carry
# both --no-plugins and --no-scripts. This script checks the line with plain
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

if [ "$status" -eq 0 ]; then
  echo "check-proctor-install-flags: ok"
fi
exit "$status"
