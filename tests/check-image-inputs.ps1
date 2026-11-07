# check-image-inputs.ps1: is every job image an input, and do the php: defaults
# name a Debian release?
#
# Two practices from BEST_PRACTICES.md, checked in one pass:
#
#   * 2.10: every job's image: is an input. A hard-coded image means the
#     component cannot move to WSU-controlled or Citadel-matching images
#     without a new major version.
#   * 4.10: a default php: tag names the Debian release (for example
#     -cli-trixie). The bare cli tag silently follows whichever Debian
#     release the image maintainers choose.
#
# The templates are YAML documents separated by `---`: the spec (inputs)
# before the last separator, the jobs after it. Some templates start with a
# comment header, so the jobs document is everything after the last `---`
# line, not the first. This script reads the documents and checks them with
# plain string matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-image-inputs: $message")
  $script:status = 1
}

# Debian release names the official php images use in their tags.
$debianReleases = 'stretch|buster|bullseye|bookworm|trixie|forky'

Get-ChildItem -Path (Join-Path $Root "templates") -Directory | ForEach-Object {
  $tpl = Join-Path $_.FullName "template.yml"
  if (-not (Test-Path -LiteralPath $tpl)) { return }
  $name = $_.Name

  $lines = @(Get-Content -LiteralPath $tpl)

  # The jobs document is everything after the last `---` line; the spec
  # document is everything before it.
  $sepIndex = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^---[ \t]*$') { $sepIndex = $i }
  }
  if ($sepIndex -lt 0) {
    Fail "${name}: no `---` separator between the spec and jobs documents"
    return
  }
  $spec = @($lines[0..($sepIndex - 1)])
  $jobs = @($lines[($sepIndex + 1)..($lines.Count - 1)])

  # 2.10: every job image: is the image input. The job a line belongs to is
  # the most recent top-level key before it in the jobs document. An image
  # may be written inline (`image: $[[ inputs.image ]]`) or as a block
  # (`image:` then `name:`, as secret-detection does to also override the
  # entrypoint); either way the reference must be the input. No exemptions:
  # every job and value that is not the image input fails. The image input
  # may follow the image_prefix input (`$[[ inputs.image_prefix ]]/...`),
  # which check-dependency-cache requires for Docker Hub images.
  $imageValues = @('$[[ inputs.image ]]', '$[[ inputs.image_prefix ]]/$[[ inputs.image ]]')
  $jobName = $null
  $imageCount = 0
  $pendingJob = $null
  foreach ($line in $jobs) {
    if ($line -match '^[A-Za-z0-9_-]+:') {
      if ($null -ne $pendingJob) { Fail "${name}: job image block has no name: ($pendingJob)" }
      $pendingJob = $null
      $jobName = ($line -replace ':.*$', '')
    }
    if ($line -match '^  image:[ \t]*$') {
      $imageCount++
      $pendingJob = $jobName
      continue
    }
    if ($null -ne $pendingJob) {
      if ($line -match '^    name:[ \t]*(.*)$') {
        $value = $Matches[1]
        if ($imageValues -contains $value) { $pendingJob = $null; continue }
        Fail "${name}: job image is not the image input ($jobName): $value"
      } else {
        Fail "${name}: job image block must start with name: ($jobName): $line"
      }
      $pendingJob = $null
      continue
    }
    if ($line -match '^  image:[ \t]+') {
      $imageCount++
      $value = ($line -replace '^  image:[ \t]*', '')
      if ($imageValues -contains $value) { continue }
      Fail "${name}: job image is not the image input ($jobName): $value"
    }
  }
  if ($imageCount -eq 0) {
    Fail "${name}: no job image: line found"
  }
  if ($null -ne $pendingJob) {
    Fail "${name}: job image block has no name: ($pendingJob)"
  }

  # The spec must define the image input with a default.
  $default = $null
  $inBlock = $false
  foreach ($line in $spec) {
    if (-not $inBlock) {
      if ($line -match '^    image:[ \t]*$') { $inBlock = $true }
      continue
    }
    if ($line -match '^    [A-Za-z_]' -or $line -match '^[^ ]') { break }
    if ($line -match '^      default:[ \t]*(.*)$') {
      $default = $Matches[1]
      break
    }
  }
  if ([string]::IsNullOrWhiteSpace($default)) {
    Fail "${name}: the image input has no default"
  } else {
    $default = $default.Trim()
    if ($default.Length -ge 2 -and $default.StartsWith('"') -and $default.EndsWith('"')) {
      $default = $default.Substring(1, $default.Length - 2)
    }
    # 4.10: a default php: tag names the Debian release.
    if ($default -like 'php:*') {
      $tag = $default.Split('@')[0]
      $tag = $tag.Substring(4) # strip php:
      if ($tag -notmatch "(^|[-])($debianReleases)([-.]|$)") {
        Fail "${name}: default php: tag does not name a Debian release: $default"
      }
    }
  }
}

if ($status -eq 0) {
  Write-Output "check-image-inputs: ok"
}
exit $status
