#!/bin/sh
# Copied from Preflight 0.8.0; do not edit; refresh with the copy step in
# docs/guides/component-a11y.md.
#
# The local accessibility gate (axe-core in Playwright), run in Docker so no
# host browser is needed. It runs the checker next to this script
# (tools/a11y/check.mjs) in the Playwright image named by
# tools/a11y/a11y-pin.json, so a local run checks the same way as the
# pipeline's a11y job. Linux and macOS; on Windows use a11y.ps1, or this
# script from Git Bash (the MSYSTEM block below handles its path conversion).
#
#   sh tools/a11y/a11y.sh                    the site folder, WCAG 2.2 AA
#   sh tools/a11y/a11y.sh --site=DIR --pages='["index.html", "docs/**/*.html"]' \
#     --tags='["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]' --report=DIR
#   sh tools/a11y/a11y.sh --base-url=http://host.docker.internal:8000 --pages='["/", "/apps"]'
#
# --site is relative to the repo root; --pages and --tags are JSON lists;
# --report keeps gl-a11y-junit.xml and gl-a11y-report.json in DIR (default
# build/a11y). --base-url checks a running site instead of a folder of HTML
# (default: the A11Y_BASE_URL environment variable, or empty). The color
# schemes and widths are light and dark at 320 px and 1280 px. Exit 0 clean,
# 1 a violation or a page that did not load, 2 a tool or configuration error.
#
# localhost inside the container is the container itself, so a site on the
# host is reached as host.docker.internal.
#
# The repo is mounted read-only; npm's cache lives in the shared
# stack-npm-cache volume, so later runs install from it.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$DIR/../.."

SITE=site
PAGES='["**/*.html"]'
TAGS='["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]'
REPORT="build/a11y"
BASE_URL="${A11Y_BASE_URL:-}"
for arg in "$@"; do
  case $arg in
    --site=*) SITE=${arg#--site=} ;;
    --pages=*) PAGES=${arg#--pages=} ;;
    --tags=*) TAGS=${arg#--tags=} ;;
    --report=*) REPORT=${arg#--report=} ;;
    --base-url=*) BASE_URL=${arg#--base-url=} ;;
    *)
      echo "usage: sh tools/a11y/a11y.sh [--site=DIR] [--pages=JSON] [--tags=JSON] [--report=DIR] [--base-url=URL]" >&2
      exit 2
      ;;
  esac
done

# The pin manifest next to this script: the Preflight release the kit was
# copied from, and the image and versions that release pinned. Nothing here
# is hard-coded; the manifest is the single source.
PIN="$DIR/a11y-pin.json"
if [ ! -f "$PIN" ]; then
  echo "a11y: missing $PIN; copy the kit from the pinned Preflight tag (docs/guides/component-a11y.md)" >&2
  exit 2
fi
pin_of() {
  awk -F'"' -v k="$1" '$2 == k { print $4 }' "$PIN" | head -n 1
}
IMAGE=$(pin_of image)
PW=$(pin_of playwright)
AXE_PW=$(pin_of axe_playwright)
AXE_CORE=$(pin_of axe_core)
if [ -z "$IMAGE" ] || [ -z "$PW" ] || [ -z "$AXE_PW" ] || [ -z "$AXE_CORE" ]; then
  echo "a11y: cannot read the image and versions from $PIN" >&2
  exit 2
fi

CONFIG=$(printf '{"siteDir": "%s", "pages": %s, "tags": %s, "colorSchemes": ["light", "dark"], "widths": [320, 1280], "axeCoreVersion": "%s"}' \
  "$SITE" "$PAGES" "$TAGS" "$AXE_CORE")

# Git Bash on Windows rewrites absolute-looking arguments for native programs
# (docker would turn -w /work into a Windows path). Turn that off and pass the
# Windows form of the host paths instead.
if [ -n "${MSYSTEM:-}" ]; then
  export MSYS_NO_PATHCONV=1
  REPO="$(pwd -W)"
else
  REPO="$PWD"
fi

# The docker mounts, collected as positional parameters so a path with a
# space survives. --add-host makes host.docker.internal reach the host on
# Linux too; Docker Desktop already has it. The npm cache is the shared
# stack-npm-cache volume, per the stack's download-cache rule.
set -- --add-host=host.docker.internal:host-gateway -v "${REPO}:/work:ro" -v stack-npm-cache:/npm-cache -e NPM_CONFIG_CACHE=/npm-cache
REPORT_DIR=/tmp/a11y/out
if [ -n "$REPORT" ]; then
  mkdir -p "$REPORT"
  if [ -n "${MSYSTEM:-}" ]; then
    REPORT_HOST="$(cd "$REPORT" && pwd -W)"
  else
    REPORT_HOST="$(cd "$REPORT" && pwd)"
  fi
  set -- "$@" -v "${REPORT_HOST}:/report"
  REPORT_DIR=/report
fi

# A non-empty base URL goes to the checker as the component's base_url input;
# the checker refuses anything that is not http or https (exit 2), so no
# validation here.
if [ -n "$BASE_URL" ]; then
  set -- "$@" -e "A11Y_BASE_URL=$BASE_URL"
fi

# The container steps, the same as scripts/a11y-container.sh in Preflight:
# exact versions, no install scripts, then the checker with the inputs as
# JSON. The checker comes from the kit folder on the read-only mount.
docker run --rm "$@" \
  -w /work \
  -e "A11Y_CONFIG=$CONFIG" \
  -e "A11Y_REPORT_DIR=$REPORT_DIR" \
  -e "A11Y_PLAYWRIGHT_VERSION=$PW" \
  -e "A11Y_AXE_PLAYWRIGHT_VERSION=$AXE_PW" \
  -e "A11Y_AXE_CORE_VERSION=$AXE_CORE" \
  "$IMAGE" \
  sh -c 'set -eu
export NPM_CONFIG_UPDATE_NOTIFIER=false
H=/tmp/a11y
mkdir -p "$H"
printf "{\"private\": true}\n" > "$H/package.json"
(cd "$H" && npm install --no-audit --no-fund --ignore-scripts --loglevel=error \
  "playwright@$A11Y_PLAYWRIGHT_VERSION" \
  "@axe-core/playwright@$A11Y_AXE_PLAYWRIGHT_VERSION" \
  "axe-core@$A11Y_AXE_CORE_VERSION")
cp /work/tools/a11y/check.mjs "$H/check.mjs"
printf "%s\n" "$A11Y_CONFIG" > "$H/config.json"
exec node "$H/check.mjs" "$H/config.json"'
