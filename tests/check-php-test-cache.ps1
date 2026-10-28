# check-php-test-cache.ps1: does the php-test Composer cache stay correct?
#
# The php-test component caches Composer downloads so repeat runs do not
# re-download every package. The cache is only useful if it is invalidated
# when the dependencies change and if each PHP version gets its own cache.
# This check fails if either guarantee is broken:
#
#   * the cache key stops depending on composer.lock, so a dependency change
#     would silently reuse a stale cache; or
#   * the cache key prefix stops including the PHP version, so the 8.4 and
#     8.5 jobs would share a cache and clobber each other's downloads.
#
# The cache block lives directly on the php-test job. The template is two
# YAML documents separated by `---`; the jobs live in the second. This script
# reads the second document and checks the cache block with plain string
# matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$TplPath = Join-Path $Root "templates/php-test/template.yml"

if (-not (Test-Path -LiteralPath $TplPath)) {
  [Console]::Error.WriteLine("templates/php-test/template.yml not found at $TplPath")
  exit 1
}

$lines = @(Get-Content -LiteralPath $TplPath)

# The jobs document is everything after the first `---` line.
$sepIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^---[ \t]*$') { $sepIndex = $i; break }
}
if ($sepIndex -lt 0 -or $sepIndex + 1 -ge $lines.Count) {
  [Console]::Error.WriteLine("check-php-test-cache: no jobs document after the `---` separator")
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

# There must be exactly one cache block, on the php-test job.
$cacheCount = @($block | Where-Object { $_ -match '^  cache:[ \t]*$' }).Count
if ($cacheCount -ne 1) {
  [Console]::Error.WriteLine("check-php-test-cache: expected exactly one job with a cache: block, found $cacheCount")
  $status = 1
}

# The cache key must depend on composer.lock, so a lock change invalidates the
# cache.
$hasLock = @($block | Where-Object { $_ -match '^[ \t]*-[ \t]*composer\.lock[ \t]*$' }).Count -gt 0
if (-not $hasLock) {
  [Console]::Error.WriteLine("check-php-test-cache: php-test cache key files do not include composer.lock")
  $status = 1
}

# The cache key prefix must include the PHP version, so 8.4 and 8.5 jobs do
# not share a cache.
$prefixLine = @($block | Where-Object { $_ -match '^[ \t]*prefix:' }) | Select-Object -First 1
if (-not $prefixLine) {
  [Console]::Error.WriteLine("check-php-test-cache: php-test cache key has no prefix")
  $status = 1
} else {
  $prefix = ($prefixLine -replace '^[ \t]*prefix:[ \t]*', '')
  if ($prefix -notlike '*PHP_VERSION*') {
    [Console]::Error.WriteLine("check-php-test-cache: php-test cache key prefix does not include the PHP version: $prefix")
    $status = 1
  }
}

if ($status -eq 0) {
  Write-Output "check-php-test-cache: ok"
}
exit $status
