# check-renovate-review.ps1: do Preflight's own pins wait for a person?
#
# The shared preset renovate/default.json auto-merges digest, pin, patch and
# minor updates by default. That is fine for an app's dependencies, but the
# pins Preflight itself ships (the image digests in the templates, the
# contract and this repo's own pipeline, and the component versions an app
# includes) are what every app pipeline runs, so a change to them must be
# reviewed. This script checks the packageRules that enforce that with
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
    if ($lines[$j] -match '"automerge":\s*false') { $automergeOff = $true }
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

# The component rule: a gitlabci manager rule must match repository deps and
# turn automerge off, so a Preflight component version bump in an app waits
# for review.
$managerIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '"matchManagers".*"gitlabci"') {
    $managerIndex = $i
  }
}
if ($managerIndex -lt 0) {
  Fail "renovate/default.json has no gitlabci component rule"
} else {
  $last = [Math]::Min($managerIndex + 4, $lines.Count - 1)
  $repoDep = $false
  $componentAutomergeOff = $false
  for ($j = $managerIndex; $j -le $last; $j++) {
    if ($lines[$j] -match '"matchDepTypes".*"repository"') { $repoDep = $true }
    if ($lines[$j] -match '"automerge":\s*false') { $componentAutomergeOff = $true }
  }
  if (-not $repoDep) {
    Fail "the gitlabci component rule does not match repository deps"
  }
  if (-not $componentAutomergeOff) {
    Fail "the gitlabci component rule does not turn automerge off"
  }
}

# The Squire kit rule: a custom.regex rule for waynestate/squire must turn
# automerge off and carry the squire-kit label, so a kit version bump waits
# for a person to review the refreshed kit. Its postUpgradeTasks and the
# runner's allow-list are checked by tests/check-renovate-squire-kit.ps1.
$squireIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '"matchDepNames".*"waynestate/squire"') {
    $squireIndex = $i
  }
}
if ($squireIndex -lt 0) {
  Fail "renovate/default.json has no waynestate/squire rule"
} else {
  $last = [Math]::Min($squireIndex + 6, $lines.Count - 1)
  $squireAutomergeOff = $false
  $squireKitLabel = $false
  for ($j = $squireIndex; $j -le $last; $j++) {
    if ($lines[$j] -match '"automerge":\s*false') { $squireAutomergeOff = $true }
    if ($lines[$j] -match '"squire-kit"') { $squireKitLabel = $true }
  }
  if (-not $squireAutomergeOff) {
    Fail "the waynestate/squire rule does not turn automerge off"
  }
  if (-not $squireKitLabel) {
    Fail "the waynestate/squire rule does not carry the squire-kit label"
  }
}

if ($status -eq 0) {
  Write-Output "check-renovate-review: ok"
}
exit $status
