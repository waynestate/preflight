# Accessibility gate (axe-core in Playwright), run in Docker so no host
# browser is needed. It runs the a11y component's own checker
# (templates/a11y/check.mjs) with the image and versions pinned in
# templates/a11y/template.yml, so a local run and a pipeline run check the
# same way. Windows PowerShell 5.1 and PowerShell 7; on Linux and macOS use
# scripts/a11y.sh.
#
#   scripts\a11y.ps1                      Preflight's front page and docs, WCAG 2.2 AA
#   scripts\a11y.ps1 -Site DIR -Pages '["index.html", "docs/**/*.html"]' `
#     -Tags '["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]' -Report DIR
#
# -Site is relative to the repo root; -Pages and -Tags are JSON lists;
# -Report keeps gl-a11y-junit.xml and gl-a11y-report.json in DIR. The color
# schemes and widths are the component's defaults. Exit 0 clean, 1 a
# violation or a page that did not load, 2 a tool or configuration error.
#
# The repo is mounted read-only; npm's cache lives in a named volume, so
# later runs install from it.
param(
  [string]$Site = "site",
  [string]$Pages = '["**/*.html"]',
  [string]$Tags = '["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]',
  [string]$Report = ""
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)

# The default of one input in the component's spec, without YAML quotes.
$tplLines = Get-Content -LiteralPath "templates/a11y/template.yml"
function Get-InputDefault([string]$name) {
  $inBlock = $false
  foreach ($line in $tplLines) {
    if ($line -ceq "    ${name}:") { $inBlock = $true; continue }
    if ($inBlock -and $line -match '^    [A-Za-z_]') { break }
    if ($inBlock -and $line -match '^      default:\s*(.*)$') {
      $value = $Matches[1].Trim()
      if ($value -match '^"(.*)"$') { $value = $Matches[1] }
      return $value
    }
  }
  return ""
}

$image = Get-InputDefault "image"
$axeCore = Get-InputDefault "axe_core_version"
$axePw = Get-InputDefault "axe_playwright_version"
$schemes = Get-InputDefault "color_schemes"
$widths = Get-InputDefault "widths"
$pw = ""
if ($image -match 'playwright:v([0-9]+\.[0-9]+\.[0-9]+)') { $pw = $Matches[1] }
if (-not $image -or -not $axeCore -or -not $axePw -or -not $pw) {
  [Console]::Error.WriteLine("a11y: cannot read the image and versions from templates/a11y/template.yml")
  exit 2
}

$config = '{{"siteDir": "{0}", "pages": {1}, "tags": {2}, "colorSchemes": {3}, "widths": {4}, "axeCoreVersion": "{5}"}}' -f $Site, $Pages, $Tags, $schemes, $widths, $axeCore

$dockerArgs = @("run", "--rm", "-v", "$((Get-Location).Path):/work:ro", "-v", "preflight-a11y-npm-cache:/root/.npm")
$reportDir = "/tmp/preflight-a11y/out"
if ($Report) {
  New-Item -ItemType Directory -Force -Path $Report | Out-Null
  $dockerArgs += @("-v", "$((Resolve-Path -LiteralPath $Report).Path):/report")
  $reportDir = "/report"
}

# The values go to the container through an env file, not -e: Windows
# PowerShell 5.1 drops the double quotes inside a native argument, and the
# config is JSON. An env file line is read literally.
$envFile = Join-Path ([IO.Path]::GetTempPath()) "preflight-a11y-$PID.env"
$envLines = @(
  "A11Y_CONFIG=$config",
  "A11Y_REPORT_DIR=$reportDir",
  "A11Y_PLAYWRIGHT_VERSION=$pw",
  "A11Y_AXE_PLAYWRIGHT_VERSION=$axePw",
  "A11Y_AXE_CORE_VERSION=$axeCore"
)
[IO.File]::WriteAllText($envFile, (($envLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

# scripts/a11y-container.sh runs the component job's steps inside the image.
$dockerArgs += @("-w", "/work", "--env-file", $envFile, $image, "sh", "scripts/a11y-container.sh")
# Windows PowerShell 5.1 turns a native program's redirected stderr into
# error records, which Stop would make fatal; the exit code is the verdict.
$ErrorActionPreference = "Continue"
try {
  & docker @dockerArgs
  $code = $LASTEXITCODE
} finally {
  [IO.File]::Delete($envFile)
}
exit $code