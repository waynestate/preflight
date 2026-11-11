# check-a11y-runner.ps1: do the local a11y runners still read their pins from
# templates/a11y/template.yml?
#
# scripts/a11y.sh and scripts/a11y.ps1 (with scripts/a11y-container.sh) run the
# a11y component's own checker with the image and versions read at run time
# from the defaults in templates/a11y/template.yml, so a local run and a
# pipeline run check the same way. The consumer kit (templates/a11y/consumer/)
# is the single local runner every stack repo copies into tools/a11y/ (D-110);
# its runners read the same pins from a11y-pin.json instead of the template,
# and this test holds that manifest to the template's own defaults through the
# generator. This test fails when a runner grows its own pin or stops passing
# the container script its inputs. Plain string handling, so it needs no
# modules, no yq and no Docker. Its twin, check-a11y-runner.sh, does the same
# on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Sh = Join-Path $Root "scripts/a11y.sh"
$Ps = Join-Path $Root "scripts/a11y.ps1"
$Container = Join-Path $Root "scripts/a11y-container.sh"
$names = @("image", "axe_core_version", "axe_playwright_version", "color_schemes", "widths")
$envNames = @("A11Y_CONFIG", "A11Y_REPORT_DIR", "A11Y_PLAYWRIGHT_VERSION", "A11Y_AXE_PLAYWRIGHT_VERSION", "A11Y_AXE_CORE_VERSION")
$problems = @()

# A pin is a package prefix directly followed by a digit; the container script
# keeps its versions in $A11Y_ variables, so none of these match there.
function Has-Pinned([string]$text, [string]$prefix) {
  $idx = 0
  while (($idx = $text.IndexOf($prefix, $idx)) -ge 0) {
    $after = $idx + $prefix.Length
    if ($after -lt $text.Length -and $text[$after] -ge [char]"0" -and $text[$after] -le [char]"9") { return $true }
    $idx = $after
  }
  return $false
}

foreach ($f in @($Sh, $Ps, $Container)) {
  if (-not (Test-Path -LiteralPath $f)) {
    $problems += "missing $f"
  }
}

if ($problems.Count -eq 0) {
  $shText = [System.IO.File]::ReadAllText($Sh, [System.Text.UTF8Encoding]::new($false))
  $psText = [System.IO.File]::ReadAllText($Ps, [System.Text.UTF8Encoding]::new($false))
  $containerText = [System.IO.File]::ReadAllText($Container, [System.Text.UTF8Encoding]::new($false))

  # scripts/a11y.sh reads each input through default_of, from the template.
  foreach ($name in $names) {
    if (-not $shText.Contains("default_of $name")) {
      $problems += "scripts/a11y.sh no longer reads $name with default_of"
    }
  }
  if (-not $shText.Contains("templates/a11y/template.yml")) {
    $problems += "scripts/a11y.sh no longer names templates/a11y/template.yml"
  }

  # scripts/a11y.ps1 reads each input through Get-InputDefault, from the template.
  foreach ($name in $names) {
    if (-not $psText.Contains(('Get-InputDefault "' + $name + '"'))) {
      $problems += "scripts/a11y.ps1 no longer reads $name with Get-InputDefault"
    }
  }
  if (-not $psText.Contains("templates/a11y/template.yml")) {
    $problems += "scripts/a11y.ps1 no longer names templates/a11y/template.yml"
  }

  # No runner hard-codes a pin outside a comment line.
  $scan = @(@("scripts/a11y.sh", $shText), @("scripts/a11y.ps1", $psText), @("scripts/a11y-container.sh", $containerText))
  foreach ($entry in $scan) {
    $label = $entry[0]
    foreach ($line in ($entry[1] -split "`n")) {
      $code = $line.TrimEnd("`r")
      if ($code.TrimStart().StartsWith("#")) { continue }
      if ($code.Contains("mcr.microsoft.com/playwright:v") -or (Has-Pinned $code "axe-core@") -or (Has-Pinned $code "@axe-core/playwright@") -or (Has-Pinned $code "playwright@")) {
        $problems += "$label hard-codes a pin: $($code.Trim())"
      }
    }
  }

  # Both runners pass every variable the container script needs, and the
  # container uses them.
  foreach ($envName in $envNames) {
    if (-not $shText.Contains($envName)) { $problems += "scripts/a11y.sh no longer passes $envName" }
    if (-not $psText.Contains($envName)) { $problems += "scripts/a11y.ps1 no longer passes $envName" }
    if (-not $containerText.Contains($envName)) { $problems += "scripts/a11y-container.sh no longer uses $envName" }
  }

  # The consumer-facing options stay.
  $usageLine = $null
  foreach ($line in ($shText -split "`n")) {
    if ($line.Contains("usage:") -and $line.Contains("--site=") -and $line.Contains("--pages=") -and $line.Contains("--tags=") -and $line.Contains("--report=") -and $line.Contains("--base-url=")) {
      $usageLine = $line
    }
  }
  if ($null -eq $usageLine) {
    $problems += "scripts/a11y.sh usage line no longer offers --site, --pages, --tags, --report and --base-url"
  }
  foreach ($param in @("Site", "Pages", "Tags", "Report", "BaseUrl")) {
    if (-not $psText.Contains(('[string]$' + $param))) {
      $problems += "scripts/a11y.ps1 no longer takes -$param"
    }
  }

  # Line endings.
  if ($shText.Contains("`r")) { $problems += "scripts/a11y.sh contains a carriage return" }
  if ($containerText.Contains("`r")) { $problems += "scripts/a11y-container.sh contains a carriage return" }
  $psLines = $psText -split "`n"
  for ($i = 0; $i -lt $psLines.Count - 1; $i++) {
    if (-not $psLines[$i].EndsWith("`r")) {
      $problems += "scripts/a11y.ps1 does not have CRLF on every line"
      break
    }
  }
}

# 8. The consumer kit (templates/a11y/consumer/) is fresh and shaped like the
# component: the generator twin agrees with the committed files, the pin names
# the newest released version, the checker is the component's checker, and the
# runners keep their options and line endings.
$KitDir = Join-Path $Root "templates/a11y/consumer"
$kitSh = Join-Path $KitDir "a11y.sh"
$kitPs = Join-Path $KitDir "a11y.ps1"
$kitPin = Join-Path $KitDir "a11y-pin.json"
$kitCheck = Join-Path $KitDir "check.mjs"
foreach ($f in @($kitSh, $kitPs, $kitPin, $kitCheck)) {
  if (-not (Test-Path -LiteralPath $f)) {
    $problems += "missing $f"
  }
}

if ($problems.Count -eq 0) {
  # 8a. The generator twin reports the kit fresh: the pin manifest, the
  # checker copy and both runner headers match the component's own pins.
  $null = & (Join-Path $Root "scripts/a11y-consumer-kit.ps1") -Check
  if ($LASTEXITCODE -ne 0) {
    $problems += "templates/a11y/consumer/ is stale; run scripts\a11y-consumer-kit.ps1"
  }

  # 8b. The pin names the newest released version in CHANGELOG.md.
  $changelogText = [System.IO.File]::ReadAllText((Join-Path $Root "CHANGELOG.md"), [System.Text.UTF8Encoding]::new($false))
  $wantVersion = $null
  foreach ($line in ($changelogText -split "`n")) {
    if ($line.TrimEnd("`r") -match '^## (\d+\.\d+\.\d+)') { $wantVersion = $Matches[1]; break }
  }
  $pinJson = [System.IO.File]::ReadAllText($kitPin, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
  if ("$($pinJson.preflight)" -cne "$wantVersion") {
    $problems += "the consumer pin says Preflight $($pinJson.preflight), but the changelog releases $wantVersion"
  }

  # 8c. The checker is the component's checker, byte for byte.
  $srcBytes = [System.IO.File]::ReadAllBytes((Join-Path $Root "templates/a11y/check.mjs"))
  $dstBytes = [System.IO.File]::ReadAllBytes($kitCheck)
  $same = $srcBytes.Length -eq $dstBytes.Length
  if ($same) {
    for ($i = 0; $i -lt $srcBytes.Length; $i++) {
      if ($srcBytes[$i] -ne $dstBytes[$i]) { $same = $false; break }
    }
  }
  if (-not $same) {
    $problems += "templates/a11y/consumer/check.mjs differs from templates/a11y/check.mjs"
  }

  $kitShText = [System.IO.File]::ReadAllText($kitSh, [System.Text.UTF8Encoding]::new($false))
  $kitPsText = [System.IO.File]::ReadAllText($kitPs, [System.Text.UTF8Encoding]::new($false))

  # 8d. A consumer runner grows no pin of its own.
  foreach ($entry in @(@("templates/a11y/consumer/a11y.sh", $kitShText), @("templates/a11y/consumer/a11y.ps1", $kitPsText))) {
    $label = $entry[0]
    foreach ($line in ($entry[1] -split "`n")) {
      $code = $line.TrimEnd("`r")
      if ($code.TrimStart().StartsWith("#")) { continue }
      if ($code.Contains("mcr.microsoft.com/playwright:v") -or (Has-Pinned $code "axe-core@") -or (Has-Pinned $code "@axe-core/playwright@") -or (Has-Pinned $code "playwright@")) {
        $problems += "$label hard-codes a pin instead of reading it from a11y-pin.json: $($code.Trim())"
      }
    }
  }

  # 8e. The consumer runners read the manifest and still offer the five
  # options, with the .sh on LF and the .ps1 on CRLF.
  if (-not $kitShText.Contains("a11y-pin.json")) { $problems += "consumer a11y.sh does not read a11y-pin.json" }
  if (-not $kitPsText.Contains("a11y-pin.json")) { $problems += "consumer a11y.ps1 does not read a11y-pin.json" }
  $cusageLine = $null
  foreach ($line in ($kitShText -split "`n")) {
    if ($line.Contains("usage:") -and $line.Contains("--site=") -and $line.Contains("--pages=") -and $line.Contains("--tags=") -and $line.Contains("--report=") -and $line.Contains("--base-url=")) {
      $cusageLine = $line
    }
  }
  if ($null -eq $cusageLine) {
    $problems += "consumer a11y.sh usage line no longer offers --site, --pages, --tags, --report and --base-url"
  }
  foreach ($param in @("Site", "Pages", "Tags", "Report", "BaseUrl")) {
    if (-not $kitPsText.Contains(('[string]$' + $param))) {
      $problems += "consumer a11y.ps1 no longer takes -$param"
    }
  }
  if ($kitShText.Contains("`r")) { $problems += "consumer a11y.sh contains a carriage return" }
  $kitPsLines = $kitPsText -split "`n"
  for ($i = 0; $i -lt $kitPsLines.Count - 1; $i++) {
    if (-not $kitPsLines[$i].EndsWith("`r")) {
      $problems += "consumer a11y.ps1 does not have CRLF on every line"
      break
    }
  }
}

if ($problems.Count -gt 0) {
  foreach ($problem in $problems) {
    [Console]::Error.WriteLine("check-a11y-runner: $problem")
  }
  exit 1
}
Write-Output "check-a11y-runner: ok"
exit 0
