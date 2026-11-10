# check-secret-detection.ps1: does Preflight's own pipeline run GitLab's
# pipeline secret detection?
#
# A secret committed to the repo stays in its history, so the repo's own
# pipeline should scan for one before it ships. GitLab's secret detection
# template reports its findings in a job named secret_detection; the job
# blocked after a week of green runs (2026-11-02 to 2026-11-10), and this
# check keeps anyone from quietly making it advisory again. This script
# checks the include line and that the job blocks with plain string matching,
# so it needs no modules, no yq and no Docker.

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

# The job must block: fail when a top-level secret_detection: key is followed
# within three lines by allow_failure: true. No key at all is fine: the
# included template's job blocks by default.
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
if ($advisoryFound) {
  Fail "secret_detection is advisory (allow_failure: true within 3 lines after secret_detection:); the job must block"
}

if ($status -eq 0) {
  Write-Output "check-secret-detection: ok"
}
exit $status
