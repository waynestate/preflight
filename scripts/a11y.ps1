# Front page accessibility gate (axe-core in Playwright), run in Docker so no
# host browser is needed. Windows PowerShell 5.1 and PowerShell 7; on Linux
# and macOS use scripts/a11y.sh.
#
# The repo is mounted read-only; only tools/a11y/node_modules lives in a named
# volume, so npm installs once and later runs reuse it.
$ErrorActionPreference = "Stop"

Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)

# The read-only repo mount cannot create the named volume's mount point.
New-Item -ItemType Directory -Force -Path "tools\a11y\node_modules" | Out-Null

$image = "mcr.microsoft.com/playwright:v1.49.1-noble"

# Every page the gate checks: the front page plus every docs page, each
# relative to the site root (check.mjs takes --root=site).
$site = Join-Path (Get-Location).Path "site"
$pages = @("index.html")
$pages += Get-ChildItem -Recurse -Filter *.html -Path (Join-Path $site "docs") | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($site.Length + 1).Replace("\", "/") }
$pageArgs = ($pages | ForEach-Object { "--page={0}" -f $_ }) -join " "

$inner = "if [ ! -d tools/a11y/node_modules/playwright ]; then if [ -f tools/a11y/package-lock.json ]; then (cd tools/a11y && npm ci --no-audit --no-fund); else (cd tools/a11y && npm install --no-audit --no-fund); fi; fi && node tools/a11y/check.mjs --root=site $pageArgs"

docker run --rm `
  -v "${PWD}:/work:ro" `
  -v preflight-a11y-node-modules:/work/tools/a11y/node_modules `
  -w /work `
  $image `
  sh -c $inner

exit $LASTEXITCODE
