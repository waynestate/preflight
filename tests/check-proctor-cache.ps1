# check-proctor-cache.ps1: does the proctor Composer cache stay correct?
#
# The proctor component caches Composer downloads so repeat runs do not
# re-download every package. The cache is only useful if it is invalidated
# when the dependencies change and if it stays pointed at the directory the
# job installs into. This check fails if either guarantee is broken:
#
#   * the cache key stops depending on composer.lock, so a dependency change
#     would silently reuse a stale cache; or
#   * the cache key prefix stops being proctor, so the cache would stop
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

# The cache key must depend on composer.lock, so a lock change invalidates the
# cache.
$hasLock = @($block | Where-Object { $_ -match '^[ \t]*-[ \t]*composer\.lock[ \t]*$' }).Count -gt 0
if (-not $hasLock) {
  [Console]::Error.WriteLine("check-proctor-cache: proctor cache key files do not include composer.lock")
  $status = 1
}

# The cache key prefix must be proctor, so the cache belongs to the proctor
# job.
$prefixLine = @($block | Where-Object { $_ -match '^[ \t]*prefix:' }) | Select-Object -First 1
if (-not $prefixLine) {
  [Console]::Error.WriteLine("check-proctor-cache: proctor cache key has no prefix")
  $status = 1
} else {
  $prefix = ($prefixLine -replace '^[ \t]*prefix:[ \t]*', '')
  if ($prefix -cne 'proctor') {
    [Console]::Error.WriteLine("check-proctor-cache: proctor cache key prefix is not proctor: $prefix")
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
