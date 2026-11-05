# check-renovate-buildah.ps1: does the preset keep buildah on -immutable tags?
#
# Red Hat re-pushed buildah v1.43.5 and garbage-collected the old digest,
# which broke an image job. DRAWBRIDGE and SQUIRE now pin the -immutable
# form (v1.43.5-immutable@sha256:...), so the shared preset must only
# match -immutable tags for quay.io/buildah/stable and keep pinning
# digests. This script checks renovate/default.json with plain string
# matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-renovate-buildah: $message")
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

# The buildah rule: a matchPackageNames entry for quay.io/buildah/stable
# must sit in a rule whose versioning or allowedVersions mentions
# -immutable, within the same object.
$keyIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '"matchPackageNames".*"quay\.io/buildah/stable"') {
    $keyIndex = $i
  }
}
if ($keyIndex -lt 0) {
  Fail "renovate/default.json has no packageRule for quay.io/buildah/stable"
} else {
  $last = [Math]::Min($keyIndex + 4, $lines.Count - 1)
  $immutable = $false
  for ($j = $keyIndex; $j -le $last; $j++) {
    if ($lines[$j] -match '("versioning"|"allowedVersions").*-immutable') { $immutable = $true }
  }
  if (-not $immutable) {
    Fail "the quay.io/buildah/stable rule does not restrict versions to -immutable tags"
  }
}

# Digests stay pinned: docker:pinDigests must still be in extends.
if (-not ($lines | Where-Object { $_ -match '"docker:pinDigests"' })) {
  Fail "renovate/default.json no longer carries docker:pinDigests in extends"
}

if ($status -eq 0) {
  Write-Output "check-renovate-buildah: ok"
}
exit $status
