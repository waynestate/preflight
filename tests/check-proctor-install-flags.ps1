# check-proctor-install-flags.ps1: does the proctor template install the app
# without running its plugins and scripts?
#
# The proctor job only inspects the app, so the app's plugins and scripts must
# not run with the job's access. A hostile composer.json could otherwise use
# them to execute code inside the job, so the composer install line must carry
# both --no-plugins and --no-scripts. Neither the proctor job nor the sbom job
# runs the app, so both install with --ignore-platform-reqs, and the sbom job
# with --no-scripts. This script checks the lines with plain
# string matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-proctor-install-flags: $message")
  $script:status = 1
}

$tpl = Join-Path $Root "templates\proctor\template.yml"
if (-not (Test-Path -LiteralPath $tpl)) {
  Fail "proctor: templates/proctor/template.yml is missing"
  exit $status
}

$lines = @(Get-Content -LiteralPath $tpl)
$installLine = $lines | Where-Object { $_ -match 'composer\s+install' } | Select-Object -First 1
if ($null -eq $installLine) {
  Fail "proctor: no composer install line found in templates/proctor/template.yml"
  exit $status
}

if ($installLine -notmatch '--no-plugins') {
  Fail "proctor: the composer install line is missing --no-plugins"
}
if ($installLine -notmatch '--no-scripts') {
  Fail "proctor: the composer install line is missing --no-scripts"
}
# The job never runs the app, so an app locked to an older PHP, or needing an
# extension the image lacks, must still get its report (proof run 2026-11-05).
if ($installLine -notmatch '--ignore-platform-reqs') {
  Fail "proctor: the composer install line is missing --ignore-platform-reqs"
}

# The sbom job only lists what the lock installs: no app scripts, no platform
# requirements.
$sbom = Join-Path $Root "templates\sbom\template.yml"
$sbomLine = @(Get-Content -LiteralPath $sbom) | Where-Object { $_ -match 'composer\s+install' } | Select-Object -First 1
if ($null -eq $sbomLine) {
  Fail "sbom: no composer install line found in templates/sbom/template.yml"
} else {
  if ($sbomLine -notmatch '--no-scripts') {
    Fail "sbom: the composer install line is missing --no-scripts"
  }
  if ($sbomLine -notmatch '--ignore-platform-reqs') {
    Fail "sbom: the composer install line is missing --ignore-platform-reqs"
  }
}

if ($status -eq 0) {
  Write-Output "check-proctor-install-flags: ok"
}
exit $status
