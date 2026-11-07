#!/bin/sh
# Runs inside the Playwright image for scripts/a11y.sh and scripts/a11y.ps1,
# from the read-only repo mount: the same steps as the a11y component's job.
# Not a developer script; run one of those two instead.
#
# Exact versions, no install scripts, then the checker with the inputs as
# JSON. The callers pass:
#   A11Y_CONFIG                  the checker's config (JSON)
#   A11Y_REPORT_DIR              where the reports go
#   A11Y_PLAYWRIGHT_VERSION      read from the image tag
#   A11Y_AXE_PLAYWRIGHT_VERSION  @axe-core/playwright
#   A11Y_AXE_CORE_VERSION        axe-core
set -eu

export NPM_CONFIG_UPDATE_NOTIFIER=false
H=/tmp/preflight-a11y
mkdir -p "$H"
printf '{"private": true}\n' > "$H/package.json"
(cd "$H" && npm install --no-audit --no-fund --ignore-scripts --loglevel=error \
  "playwright@$A11Y_PLAYWRIGHT_VERSION" \
  "@axe-core/playwright@$A11Y_AXE_PLAYWRIGHT_VERSION" \
  "axe-core@$A11Y_AXE_CORE_VERSION")
cp templates/a11y/check.mjs "$H/check.mjs"
printf '%s\n' "$A11Y_CONFIG" > "$H/config.json"
exec node "$H/check.mjs" "$H/config.json"
