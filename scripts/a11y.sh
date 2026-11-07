#!/bin/sh
# Accessibility gate (axe-core in Playwright), run in Docker so no host
# browser is needed. It runs the a11y component's own checker
# (templates/a11y/check.mjs) with the image and versions pinned in
# templates/a11y/template.yml, so a local run and a pipeline run check the
# same way. Linux and macOS; on Windows use scripts/a11y.ps1, or this script
# from Git Bash (the MSYSTEM block below handles its path conversion).
#
#   sh scripts/a11y.sh                    Preflight's front page and docs, WCAG 2.2 AA
#   sh scripts/a11y.sh --site=DIR --pages='["index.html", "docs/**/*.html"]' \
#     --tags='["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]' --report=DIR
#
# --site is relative to the repo root; --pages and --tags are JSON lists;
# --report keeps gl-a11y-junit.xml and gl-a11y-report.json in DIR. The color
# schemes and widths are the component's defaults. Exit 0 clean, 1 a
# violation or a page that did not load, 2 a tool or configuration error.
#
# The repo is mounted read-only; npm's cache lives in a named volume, so
# later runs install from it.
set -eu

cd "$(dirname "$0")/.."

SITE=site
PAGES='["**/*.html"]'
TAGS='["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]'
REPORT=""
for arg in "$@"; do
  case $arg in
    --site=*) SITE=${arg#--site=} ;;
    --pages=*) PAGES=${arg#--pages=} ;;
    --tags=*) TAGS=${arg#--tags=} ;;
    --report=*) REPORT=${arg#--report=} ;;
    *)
      echo "usage: sh scripts/a11y.sh [--site=DIR] [--pages=JSON] [--tags=JSON] [--report=DIR]" >&2
      exit 2
      ;;
  esac
done

# The default of one input in the component's spec, without YAML quotes.
TPL=templates/a11y/template.yml
default_of() {
  awk -v key="    $1:" '
    $0 == key { inblock = 1; next }
    inblock && /^    [A-Za-z_]/ { exit }
    inblock && /^      default:/ { sub(/^      default:[ \t]*/, ""); print; exit }
  ' "$TPL" | sed 's/^"\(.*\)"$/\1/'
}

IMAGE=$(default_of image)
AXE_CORE=$(default_of axe_core_version)
AXE_PW=$(default_of axe_playwright_version)
SCHEMES=$(default_of color_schemes)
WIDTHS=$(default_of widths)
PW=$(printf '%s\n' "$IMAGE" | sed -n 's/^.*playwright:v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p')
if [ -z "$IMAGE" ] || [ -z "$AXE_CORE" ] || [ -z "$AXE_PW" ] || [ -z "$PW" ]; then
  echo "a11y: cannot read the image and versions from $TPL" >&2
  exit 2
fi

CONFIG=$(printf '{"siteDir": "%s", "pages": %s, "tags": %s, "colorSchemes": %s, "widths": %s, "axeCoreVersion": "%s"}' \
  "$SITE" "$PAGES" "$TAGS" "$SCHEMES" "$WIDTHS" "$AXE_CORE")

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
# space survives. The options above are already parsed.
set -- -v "${REPO}:/work:ro" -v preflight-a11y-npm-cache:/root/.npm
REPORT_DIR=/tmp/preflight-a11y/out
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

# scripts/a11y-container.sh runs the component job's steps inside the image.
docker run --rm "$@" \
  -w /work \
  -e "A11Y_CONFIG=$CONFIG" \
  -e "A11Y_REPORT_DIR=$REPORT_DIR" \
  -e "A11Y_PLAYWRIGHT_VERSION=$PW" \
  -e "A11Y_AXE_PLAYWRIGHT_VERSION=$AXE_PW" \
  -e "A11Y_AXE_CORE_VERSION=$AXE_CORE" \
  "$IMAGE" \
  sh scripts/a11y-container.sh
