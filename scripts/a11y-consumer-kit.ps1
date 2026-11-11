# a11y-consumer-kit.ps1: keep templates/a11y/consumer/ honest.
#
# The consumer kit is the single local a11y runner every stack repo copies
# into tools/a11y/ (D-110): a11y.sh and a11y.ps1 read their image and versions
# from a11y-pin.json at run time, and check.mjs is the component's own checker.
# This script rewrites the pin manifest from the defaults in
# templates/a11y/template.yml and the newest released version in
# CHANGELOG.md, refreshes the two-line "Copied from Preflight" header in both
# runners, and copies the checker over. With -Check it only compares and
# exits 1 when the kit is stale; that is what the contract job runs, so a
# bumped release or a moved pin fails the pipeline until the kit is rewritten.
#
#   pwsh scripts/a11y-consumer-kit.ps1            rewrite the kit
#   pwsh scripts/a11y-consumer-kit.ps1 -Check     exit 1 when the kit is stale
#
# Plain string handling, so it needs no modules, no yq and no Docker. Works on
# Windows PowerShell 5.1 and PowerShell 7. Its twin, a11y-consumer-kit.sh,
# does the same on Linux and macOS.

param(
  [switch]$Check
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Tpl = Join-Path $Root "templates/a11y/template.yml"
$Kit = Join-Path $Root "templates/a11y/consumer"
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# The default of one input in the component's spec, without YAML quotes. The
# same reader as scripts/a11y.sh (default_of), so the kit cannot drift from
# the jobs.
function Get-InputDefault([string]$text, [string]$key) {
  $inBlock = $false
  foreach ($line in ($text -split "`n")) {
    $code = $line.TrimEnd("`r")
    if (-not $inBlock) {
      if ($code -ceq ("    " + $key + ":")) { $inBlock = $true }
      continue
    }
    if ($code -match '^    [A-Za-z_]') { break }
    if ($code -match '^      default:\s*(.*)$') {
      $value = $Matches[1].Trim()
      if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
        $value = $value.Substring(1, $value.Length - 2)
      }
      return $value
    }
  }
  return ""
}

$tplText = [System.IO.File]::ReadAllText($Tpl, $Utf8)
$Image = Get-InputDefault $tplText "image"
$AxeCore = Get-InputDefault $tplText "axe_core_version"
$AxePlaywright = Get-InputDefault $tplText "axe_playwright_version"
$Playwright = ""
if ($Image -match 'playwright:v(\d+\.\d+\.\d+)') { $Playwright = $Matches[1] }

$changelogText = [System.IO.File]::ReadAllText((Join-Path $Root "CHANGELOG.md"), $Utf8)
$Version = ""
foreach ($line in ($changelogText -split "`n")) {
  if ($line.TrimEnd("`r") -match '^## (\d+\.\d+\.\d+)') { $Version = $Matches[1]; break }
}
if ([string]::IsNullOrWhiteSpace($Image) -or [string]::IsNullOrWhiteSpace($AxeCore) -or [string]::IsNullOrWhiteSpace($AxePlaywright) -or [string]::IsNullOrWhiteSpace($Playwright) -or [string]::IsNullOrWhiteSpace($Version)) {
  Write-Host "a11y-consumer-kit: cannot read the image, versions or version from templates/a11y/template.yml and CHANGELOG.md"
  exit 2
}

# The pin manifest: the Preflight release the kit was copied from, and the
# image and versions that release pinned. Fixed key order, LF, trailing
# newline; the runners read it with awk, so no JSON tooling is needed.
$pinLines = @(
  "{",
  ('  "preflight": "' + $Version + '",' ),
  ('  "image": "' + $Image + '",' ),
  ('  "playwright": "' + $Playwright + '",' ),
  ('  "axe_playwright": "' + $AxePlaywright + '",' ),
  ('  "axe_core": "' + $AxeCore + '"'),
  "}"
)
$pinContent = ($pinLines -join "`n") + "`n"

$h1 = "# Copied from Preflight $Version; do not edit; refresh with the copy step in"
$h2 = "# docs/guides/component-a11y.md."

# Refresh the two-line "Copied from Preflight" header of a runner, keeping
# its line endings: git checks out .ps1 as CRLF and everything else as LF,
# and the test holds each to that. The .sh keeps its shebang on line 1, so
# its header starts on line 2; the .ps1 has no shebang, so its header starts
# on line 1. Returns the expected full text without writing.
function Get-RunnerExpected([string]$path, [string]$h1, [string]$h2, [int]$start) {
  $text = [System.IO.File]::ReadAllText($path, $Utf8)
  $nl = "`n"
  if ($text.Contains("`r`n")) { $nl = "`r`n" }
  $lines = @($text -split "`r?`n")
  if ($lines.Count -lt ($start + 1)) { throw "too short: $path" }
  $prefix = @()
  if ($start -gt 1) { $prefix = $lines[0..($start - 2)] }
  $rest = $lines[($start + 1)..($lines.Count - 1)]
  $out = ""
  if ($prefix.Count -gt 0) { $out += ($prefix -join $nl) + $nl }
  $out += $h1 + $nl + $h2 + $nl
  $out += ($rest -join $nl)
  return $out
}

$runnerStarts = @{ "a11y.sh" = 2; "a11y.ps1" = 1 }

$stale = @()

$kitPin = Join-Path $Kit "a11y-pin.json"
if (-not (Test-Path -LiteralPath $kitPin)) {
  $stale += "a11y-pin.json"
}
elseif (-not ([System.IO.File]::ReadAllText($kitPin, $Utf8) -ceq $pinContent)) {
  $stale += "a11y-pin.json"
}

$kitCheck = Join-Path $Kit "check.mjs"
$srcCheck = [System.IO.File]::ReadAllBytes((Join-Path $Root "templates/a11y/check.mjs"))
if (-not (Test-Path -LiteralPath $kitCheck)) {
  $stale += "check.mjs"
}
else {
  $dstCheck = [System.IO.File]::ReadAllBytes($kitCheck)
  $same = $srcCheck.Length -eq $dstCheck.Length
  if ($same) {
    for ($i = 0; $i -lt $srcCheck.Length; $i++) {
      if ($srcCheck[$i] -ne $dstCheck[$i]) { $same = $false; break }
    }
  }
  if (-not $same) { $stale += "check.mjs" }
}

foreach ($name in @("a11y.sh", "a11y.ps1")) {
  $path = Join-Path $Kit $name
  if (-not (Test-Path -LiteralPath $path)) {
    $stale += $name
    continue
  }
  if (-not ((Get-RunnerExpected $path $h1 $h2 $runnerStarts[$name]) -ceq ([System.IO.File]::ReadAllText($path, $Utf8)))) {
    $stale += $name
  }
}

if ($Check) {
  if ($stale.Count -gt 0) {
    Write-Host "a11y-consumer-kit: stale: $($stale -join " "); run pwsh scripts/a11y-consumer-kit.ps1"
    exit 1
  }
  Write-Output "a11y-consumer-kit: ok"
  exit 0
}

New-Item -ItemType Directory -Path $Kit -Force | Out-Null
[System.IO.File]::WriteAllText($kitPin, $pinContent, $Utf8)
Copy-Item -LiteralPath (Join-Path $Root "templates/a11y/check.mjs") -Destination $kitCheck -Force
foreach ($name in @("a11y.sh", "a11y.ps1")) {
  $path = Join-Path $Kit $name
  [System.IO.File]::WriteAllText($path, (Get-RunnerExpected $path $h1 $h2 $runnerStarts[$name]), $Utf8)
}
Write-Output "a11y-consumer-kit: wrote templates/a11y/consumer/ from Preflight $Version"
