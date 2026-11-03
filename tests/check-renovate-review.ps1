# check-renovate-review.ps1: do Preflight's own pins wait for a person?
#
# The shared preset renovate/default.json auto-merges digest, pin, patch and
# minor updates by default. That is fine for an app's dependencies, but the
# pins Preflight itself ships (the image digests in the templates, the
# contract and this repo's own pipeline, and the component versions an app
# includes) are what every app pipeline runs, so a change to them must be
# reviewed. This script checks the two packageRules that enforce that with
# plain string matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-renovate-review: $message")
  $script:status = 1
}

$renovate = Join-Path $Root "renovate\default.json"
if (-not (Test-Path -LiteralPath $renovate)) {
  Fail "renovate/default.json is missing"
  exit $status
}

$lines = @(Get-Content -LiteralPath $renovate)

# No yq in the logic, so "parses as JSON" is checked the cheap way: the
# document opens with { on its first line and closes with } on its last.
if ($lines[0] -ne "{") {
  Fail "renovate/default.json does not open with {"
}
if ($lines[-1] -ne "}") {
  Fail "renovate/default.json does not close with }"
}

if (-not ($lines | Where-Object { $_ -match '"needs-review"' })) {
  Fail "renovate/default.json does not carry the needs-review label"
}

# The templates rule: a matchFileNames entry that lists templates/** must
# sit in a rule that also turns automerge off, within the same object.
$keyIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '"matchFileNames".*"templates/\*\*"') {
    $keyIndex = $i
  }
}
if ($keyIndex -lt 0) {
  Fail "renovate/default.json has no matchFileNames rule for templates/**"
} else {
  $last = [Math]::Min($keyIndex + 4, $lines.Count - 1)
  $automergeOff = $false
  $coversContract = $false
  $coversPipeline = $false
  for ($j = $keyIndex; $j -le $last; $j++) {
    if ($lines[$j] -match '"automerge":s*false') { $automergeOff = $true }
    if ($lines[$j] -match '"contract/\*\*"') { $coversContract = $true }
    if ($lines[$j] -match '".gitlab-ci.yml"') { $coversPipeline = $true }
  }
  if (-not $automergeOff) {
    Fail "the matchFileNames rule for templates/** does not turn automerge off"
  }
  if (-not ($coversContract -and $coversPipeline)) {
    Fail "the matchFileNames rule for templates/** does not also cover contract/** and .gitlab-ci.yml"
  }
}

# The component rule: a gitlab-ci-include manager rule must turn automerge
# off too, so a Preflight component version bump in an app waits for review.
$managerIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '"matchManagers".*"gitlab-ci-include"') {
    $managerIndex = $i
  }
}
if ($managerIndex -lt 0) {
  Fail "renovate/default.json has no gitlab-ci-include rule"
} else {
  $last = [Math]::Min($managerIndex + 4, $lines.Count - 1)
  $found = $false
  for ($j = $managerIndex; $j -le $last; $j++) {
    if ($lines[$j] -match '"automerge":s*false') {
      $found = $true
      break
    }
  }
  if (-not $found) {
    Fail "the gitlab-ci-include rule does not turn automerge off"
  }
}

if ($status -eq 0) {
  Write-Output "check-renovate-review: ok"
}
exit $status
