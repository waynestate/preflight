# check-release-job.ps1: does the repository's own pipeline create the
# GitLab Release from a tag?
#
# Preflight's own .gitlab-ci.yml carries a release job that runs only on a
# tag and posts to the Releases API with curl, because the nougat runner is
# arm64 and the official image for creating releases has no arm64 build.
# The release notes must carry the tag's commit SHA so consumers can pin
# it (BEST_PRACTICES 1.6). This check fails if any part of that contract
# is broken:
#
#   * the top-level release: job disappears;
#   * the job stops running only on a tag (if: $CI_COMMIT_TAG);
#   * the job stops posting to /releases with the JOB-TOKEN header and the
#     commit SHA;
#   * the job starts using the release-cli image again;
#   * the release stage leaves the stage list or moves before audit; or
#   * the job image loses its digest pin.
#
# The script reads .gitlab-ci.yml and checks the release job block with
# plain string matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$CiPath = Join-Path $Root ".gitlab-ci.yml"

if (-not (Test-Path -LiteralPath $CiPath)) {
  [Console]::Error.WriteLine("check-release-job: .gitlab-ci.yml not found at $CiPath")
  exit 1
}

$lines = @(Get-Content -LiteralPath $CiPath)

$status = 0

# The top-level release: job is a zero-indent `release:` line; its block
# runs until the next zero-indent line.
$jobStart = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^release:[ \t]*$') { $jobStart = $i; break }
}
if ($jobStart -lt 0) {
  [Console]::Error.WriteLine("check-release-job: no top-level release: job in .gitlab-ci.yml")
  exit 1
}

$block = @()
for ($i = $jobStart; $i -lt $lines.Count; $i++) {
  if ($i -gt $jobStart -and $lines[$i] -match '^[^ ]') { break }
  $block += $lines[$i]
}

# The job runs only on a tag, never on branches or merge requests.
if (@($block | Where-Object { $_ -match 'if:[ \t]*\$CI_COMMIT_TAG' }).Count -eq 0) {
  [Console]::Error.WriteLine('check-release-job: release job has no "if: $CI_COMMIT_TAG" rule')
  $status = 1
}

# The job posts to the Releases API with the job token and the commit SHA.
if (@($block | Where-Object { $_ -like '*JOB-TOKEN*' }).Count -eq 0) {
  [Console]::Error.WriteLine('check-release-job: release job does not send the JOB-TOKEN header')
  $status = 1
}
if (@($block | Where-Object { $_ -like '*$CI_COMMIT_SHA*' }).Count -eq 0) {
  [Console]::Error.WriteLine('check-release-job: release job does not carry $CI_COMMIT_SHA')
  $status = 1
}
if (@($block | Where-Object { $_ -like '*/releases*' }).Count -eq 0) {
  [Console]::Error.WriteLine('check-release-job: release job does not post to /releases')
  $status = 1
}

# The job stays on curl: the release-cli image has no arm64 build.
if (@($block | Where-Object { $_ -like '*release-cli*' }).Count -gt 0) {
  [Console]::Error.WriteLine('check-release-job: release job references the release-cli image')
  $status = 1
}

# The job image keeps its digest pin.
if (@($block | Where-Object { $_ -match '(image|name):[ \t]*\S*@sha256:' }).Count -eq 0) {
  [Console]::Error.WriteLine('check-release-job: release job image is not pinned by digest')
  $status = 1
}

# The release stage stays in the stage list, after audit.
$stageStart = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^stages:[ \t]*$') { $stageStart = $i; break }
}
$stages = @()
if ($stageStart -ge 0) {
  for ($i = $stageStart + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^[ \t]*-[ \t]+(.+)$') {
      $stages += $Matches[1].Trim()
      continue
    }
    break
  }
}
$auditIndex = -1
$releaseIndex = -1
for ($i = 0; $i -lt $stages.Count; $i++) {
  if ($stages[$i] -eq 'audit') { $auditIndex = $i }
  if ($stages[$i] -eq 'release') { $releaseIndex = $i }
}
if ($auditIndex -lt 0 -or $releaseIndex -lt 0 -or $releaseIndex -le $auditIndex) {
  [Console]::Error.WriteLine('check-release-job: stages: must list release after audit')
  $status = 1
}

if ($status -eq 0) {
  Write-Output "check-release-job: ok"
}
exit $status
