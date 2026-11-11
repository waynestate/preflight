# Copied from Preflight 0.8.0; do not edit; refresh with the copy step in
# docs/guides/component-a11y.md.
#
# The local accessibility gate (axe-core in Playwright), run in Docker so no
# host browser is needed. It runs the checker next to this script
# (tools/a11y/check.mjs) in the Playwright image named by
# tools/a11y/a11y-pin.json, so a local run checks the same way as the
# pipeline's a11y job. The Windows twin of a11y.sh: same defaults, same
# options, same exit codes (0 clean, 1 a violation or a page that did not
# load, 2 a tool or configuration error). Works on Windows PowerShell 5.1
# and PowerShell 7.
#
#   pwsh tools/a11y/a11y.ps1
#   pwsh tools/a11y/a11y.ps1 -Site DIR -Pages '["index.html"]' -Report DIR
#   pwsh tools/a11y/a11y.ps1 -BaseUrl http://host.docker.internal:8000 -Pages '["/", "/apps"]'
#
# -Site is relative to the repo root; -Pages and -Tags are JSON lists;
# -Report keeps gl-a11y-junit.xml and gl-a11y-report.json in DIR (default
# build/a11y). -BaseUrl checks a running site instead of a folder of HTML
# (default: the A11Y_BASE_URL environment variable, or empty). The color
# schemes and widths are light and dark at 320 px and 1280 px.
#
# localhost inside the container is the container itself, so a site on the
# host is reached as host.docker.internal.
#
# The repo is mounted read-only; npm's cache lives in the shared
# stack-npm-cache volume, so later runs install from it.
#
# Windows PowerShell 5.1 mangles double quotes in native arguments, so the
# JSON config and the shell program travel in files (a11y.env and run.sh) in
# a temp folder that is mounted read-only at /a11y-run, never as arguments.

param(
  [string]$Site = "site",
  [string]$Pages = '["**/*.html"]',
  [string]$Tags = '["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]',
  [string]$Report = "build/a11y",
  [string]$BaseUrl = ${env:A11Y_BASE_URL}
)

$ErrorActionPreference = "Stop"

$KitDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent (Split-Path -Parent $KitDir)
Set-Location $RepoRoot

# The pin manifest next to this script: the Preflight release the kit was
# copied from, and the image and versions that release pinned. Nothing here
# is hard-coded; the manifest is the single source.
$PinPath = Join-Path $KitDir "a11y-pin.json"
if (-not (Test-Path -LiteralPath $PinPath)) {
  Write-Host "a11y: missing $PinPath; copy the kit from the pinned Preflight tag (docs/guides/component-a11y.md)"
  exit 2
}
$Pin = Get-Content -LiteralPath $PinPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$Pin.image) -or [string]::IsNullOrWhiteSpace([string]$Pin.playwright) -or [string]::IsNullOrWhiteSpace([string]$Pin.axe_playwright) -or [string]::IsNullOrWhiteSpace([string]$Pin.axe_core)) {
  Write-Host "a11y: cannot read the image and versions from $PinPath"
  exit 2
}
$Image = [string]$Pin.image
$Playwright = [string]$Pin.playwright
$AxePlaywright = [string]$Pin.axe_playwright
$AxeCore = [string]$Pin.axe_core

# One line of JSON, so it survives the docker --env-file format.
$Config = '{"siteDir": "' + $Site + '", "pages": ' + $Pages + ', "tags": ' + $Tags + ', "colorSchemes": ["light", "dark"], "widths": [320, 1280], "axeCoreVersion": "' + $AxeCore + '"}'

$RunDir = Join-Path ([System.IO.Path]::GetTempPath()) ("preflight-a11y-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $RunDir | Out-Null
try {
  # The container steps, the same as scripts/a11y-container.sh in Preflight:
  # exact versions, no install scripts, then the checker with the inputs as
  # JSON. The checker comes from the kit folder on the read-only mount.
  $Program = @'
set -eu
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
exec node "$H/check.mjs" "$H/config.json"
'@
  [System.IO.File]::WriteAllText((Join-Path $RunDir "run.sh"), ($Program -replace "`r", ""), (New-Object System.Text.UTF8Encoding($false)))

  $EnvLines = @(
    ("A11Y_CONFIG=" + $Config),
    ("A11Y_PLAYWRIGHT_VERSION=" + $Playwright),
    ("A11Y_AXE_PLAYWRIGHT_VERSION=" + $AxePlaywright),
    ("A11Y_AXE_CORE_VERSION=" + $AxeCore),
    "NPM_CONFIG_CACHE=/npm-cache"
  )
  if ($Report) {
    New-Item -ItemType Directory -Path $Report -Force | Out-Null
    $ReportFull = (Resolve-Path -LiteralPath $Report).Path
    $EnvLines += "A11Y_REPORT_DIR=/report"
  }
  else {
    $EnvLines += "A11Y_REPORT_DIR=/tmp/a11y/out"
  }
  if ($BaseUrl) {
    $EnvLines += ("A11Y_BASE_URL=" + $BaseUrl)
  }
  [System.IO.File]::WriteAllText((Join-Path $RunDir "a11y.env"), (($EnvLines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

  $DockerArgs = @(
    "run", "--rm",
    "--add-host=host.docker.internal:host-gateway",
    "-v", ($RepoRoot + ":/work:ro"),
    "-v", "stack-npm-cache:/npm-cache",
    "-v", ($RunDir + ":/a11y-run:ro"),
    "--env-file", (Join-Path $RunDir "a11y.env"),
    "-w", "/work"
  )
  if ($Report) {
    $DockerArgs += @("-v", ($ReportFull + ":/report"))
  }
  $DockerArgs += @($Image, "sh", "/a11y-run/run.sh")
  & docker @DockerArgs
  exit $LASTEXITCODE
}
finally {
  Remove-Item -LiteralPath $RunDir -Recurse -Force -ErrorAction SilentlyContinue
}
