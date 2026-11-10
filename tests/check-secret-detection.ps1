# check-secret-detection.ps1: does Preflight's own pipeline run GitLab's
# pipeline secret detection?
#
# A secret committed to the repo stays in its history, so the repo's own
# pipeline should scan for one before it ships. GitLab's secret detection
# template reports its findings in a job named secret_detection, and the
# template sets allow_failure: true on it, so the repo must override that
# or the job is only advisory. This script checks the include line and the
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

# The job must block: GitLab's template sets allow_failure: true, so the
# repo must override it. Fail when there is no top-level secret_detection:
# key, when allow_failure: true appears within three lines after it, or
# when allow_failure: false does not appear within three lines after it.
$keyIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^secret_detection:') {
    $keyIndex = $i
  }
}

if ($keyIndex -lt 0) {
  Fail "secret_detection has no override; GitLab's template makes it advisory, so .gitlab-ci.yml must set allow_failure: false"
} else {
  $advisoryFound = $false
  $blockingFound = $false
  $last = [Math]::Min($keyIndex + 3, $lines.Count - 1)
  for ($j = $keyIndex + 1; $j -le $last; $j++) {
    if ($lines[$j] -match 'allow_failure:\s*true') {
      $advisoryFound = $true
      break
    }
    if ($lines[$j] -match 'allow_failure:\s*false') {
      $blockingFound = $true
    }
  }
  if ($advisoryFound) {
    Fail "secret_detection is advisory (allow_failure: true within 3 lines after secret_detection:); the job must block"
  } elseif (-not $blockingFound) {
    Fail "secret_detection does not set allow_failure: false within 3 lines; the job must block"
  }
}

if ($status -eq 0) {
  Write-Output "check-secret-detection: ok"
}
exit $status
