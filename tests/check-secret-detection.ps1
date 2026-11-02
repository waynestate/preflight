# check-secret-detection.ps1: does Preflight's own pipeline run GitLab's
# pipeline secret detection?
#
# A secret committed to the repo stays in its history, so the repo's own
# pipeline should scan for one before it ships. GitLab's secret detection
# template reports its findings in a job named secret_detection; until it has
# a week of green pipelines the job is advisory (allow_failure: true), so it
# warns without blocking. This script checks the include line and the job
# override with plain string matching, so it needs no modules, no yq and no
# Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-secret-detection: $message")
  $script:status = 1
}

$ci = Join-Path $Root ".gitlab-ci.yml"
if (-not (Test-Path -LiteralPath $ci)) {
  Fail ".gitlab-ci.yml is missing"
  exit $status
}

$lines = @(Get-Content -LiteralPath $ci)

if (-not ($lines | Where-Object { $_ -match 'Jobs/Secret-Detection\.gitlab-ci\.yml' })) {
  Fail ".gitlab-ci.yml does not include Jobs/Secret-Detection.gitlab-ci.yml"
}

# The override job must carry allow_failure: true within three lines after
# the top-level secret_detection: key.
$keyIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^secret_detection:') {
    $keyIndex = $i
  }
}

$advisoryFound = $false
if ($keyIndex -ge 0) {
  $last = [Math]::Min($keyIndex + 3, $lines.Count - 1)
  for ($j = $keyIndex + 1; $j -le $last; $j++) {
    if ($lines[$j] -match 'allow_failure:\s*true') {
      $advisoryFound = $true
      break
    }
  }
}
if (-not $advisoryFound) {
  Fail "secret_detection: is not followed within 3 lines by allow_failure: true"
}

if ($status -eq 0) {
  Write-Output "check-secret-detection: ok"
}
exit $status
