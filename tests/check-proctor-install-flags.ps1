# check-proctor-install-flags.ps1: does the proctor template install the app
# without running its plugins and scripts?
#
# The proctor job only inspects the app, so the app's plugins and scripts must
# not run with the job's access. A hostile composer.json could otherwise use
# them to execute code inside the job, so the composer install line must carry
# both --no-plugins and --no-scripts. This script checks the line with plain
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

if ($status -eq 0) {
  Write-Output "check-proctor-install-flags: ok"
}
exit $status
