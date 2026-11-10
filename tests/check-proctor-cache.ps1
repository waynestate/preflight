# check-proctor-cache.ps1: does the proctor Composer cache stay correct?
#
# The proctor component caches Composer downloads so repeat runs do not
# re-download every package. The key is fixed: Composer's cache is
# additive, so a lock change downloads only the packages that changed. This
# check fails if either guarantee is broken:
#
#   * the cache key goes back to a lock-file hash (a files: line), so every
#     lock bump would miss the cache and refetch everything; or
#   * the cache key stops being preflight-proctor, so the cache would stop
#     belonging to the proctor job.
#
# The cache block lives directly on the proctor job. The template is two
# YAML documents separated by `---`; the jobs live in the second. This script
# reads the second document and checks the cache block with plain string
# matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$TplPath = Join-Path $Root "templates/proctor/template.yml"

if (-not (Test-Path -LiteralPath $TplPath)) {
  [Console]::Error.WriteLine("templates/proctor/template.yml not found at $TplPath")
  exit 1
}

$lines = @(Get-Content -LiteralPath $TplPath)

# The jobs document is everything after the first `---` line.
$sepIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^---[ \t]*$') { $sepIndex = $i; break }
}
if ($sepIndex -lt 0 -or $sepIndex + 1 -ge $lines.Count) {
  [Console]::Error.WriteLine("check-proctor-cache: no jobs document after the `---` separator")
  exit 1
}
$jobs = @($lines[($sepIndex + 1)..($lines.Count - 1)])

# The cache block is a `cache:` key at two-space indent (a direct child of a
# job); it runs until the next two-space key or a zero-indent line. Capture
# it so the checks below look only inside the block.
$block = @()
$inBlock = $false
foreach ($line in $jobs) {
  if (-not $inBlock) {
    if ($line -match '^  cache:[ \t]*$') {
      $inBlock = $true
      $block += $line
    }
    continue
  }
  if ($line -match '^  [A-Za-z_]' -or $line -match '^[^ ]') {
    break
  }
  $block += $line
}

$status = 0

# There must be exactly one cache block, on the proctor job.
$cacheCount = @($block | Where-Object { $_ -match '^  cache:[ \t]*$' }).Count
if ($cacheCount -ne 1) {
  [Console]::Error.WriteLine("check-proctor-cache: expected exactly one job with a cache: block, found $cacheCount")
  $status = 1
}

# The key must be fixed, not a lock-file hash: no files: line.
$hasFiles = @($block | Where-Object { $_ -match '^[ \t]*files:' }).Count -gt 0
if ($hasFiles) {
  [Console]::Error.WriteLine("check-proctor-cache: proctor cache key is a lock-file hash; use a fixed key")
  $status = 1
}

# The key must be exactly preflight-proctor, so the cache belongs to the
# proctor job.
$keyLine = @($block | Where-Object { $_ -match '^[ \t]*key:' }) | Select-Object -First 1
if (-not $keyLine) {
  [Console]::Error.WriteLine("check-proctor-cache: proctor cache key is not preflight-proctor")
  $status = 1
} else {
  $key = ($keyLine -replace '^[ \t]*key:[ \t]*', '')
  if ($key -cne 'preflight-proctor') {
    [Console]::Error.WriteLine("check-proctor-cache: proctor cache key is not preflight-proctor: $key")
    $status = 1
  }
}

# The cache must cover the directory the job points Composer at.
$hasPath = @($block | Where-Object { $_ -match '^[ \t]*-[ \t]*\.composer-cache/[ \t]*$' }).Count -gt 0
if (-not $hasPath) {
  [Console]::Error.WriteLine("check-proctor-cache: proctor cache paths do not include .composer-cache/")
  $status = 1
}

# The job must point Composer at the cached directory.
$varLine = @($jobs | Where-Object { $_ -match '^[ \t]*COMPOSER_CACHE_DIR:' }) | Select-Object -First 1
if (-not $varLine) {
  [Console]::Error.WriteLine("check-proctor-cache: proctor job does not set COMPOSER_CACHE_DIR")
  $status = 1
} else {
  $varValue = ($varLine -replace '.*COMPOSER_CACHE_DIR:[ \t]*', '').Trim().Trim('"')
  if ($varValue -ne '$CI_PROJECT_DIR/.composer-cache') {
    [Console]::Error.WriteLine("check-proctor-cache: proctor COMPOSER_CACHE_DIR does not point at the cached directory: $varValue")
    $status = 1
  }
}

if ($status -eq 0) {
  Write-Output "check-proctor-cache: ok"
}
exit $status
