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
# The cache block lives on a hidden job that the php-test job extends when the
# cache input is true (docs: Components, "Use boolean inputs to conditionally
# configure jobs"). Rather than hard-coding that hidden job's name, the check
# finds whichever job in the template carries a cache: block, so it keeps
# working if the hidden job is renamed.
#
# PowerShell 7 has no YAML parser built in, and this script must run with no
# modules, so the YAML is parsed by running yq in Docker:
#   docker run --rm -v "<root>:/w" -w /w mikefarah/yq@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e -o=json eval ...
# Needs Docker and the mikefarah/yq@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e image. The .sh twin needs only yq.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$TplPath = Join-Path $Root "templates/php-test/template.yml"

if (-not (Test-Path -LiteralPath $TplPath)) {
  [Console]::Error.WriteLine("templates/php-test/template.yml not found at $TplPath")
  exit 1
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("docker is required: this script parses the template with yq in Docker")
  exit 1
}

function Invoke-YqJson {
  param([string[]]$YqArgs)
  docker run --rm -v "${Root}:/w" -w /w mikefarah/yq@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e -o=json @YqArgs
  if ($LASTEXITCODE -ne 0) {
    throw "yq failed (exit $LASTEXITCODE): mikefarah/yq@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e $($YqArgs -join ' ')"
  }
}

$status = 0
$tplRel = "templates/php-test/template.yml"

# The job that carries the cache: block. There is exactly one (the hidden job
# the php-test job extends when cache is true).
$cacheJobs = Invoke-YqJson @("eval", "select(document_index == 1) | to_entries | map(select(.value.cache != null)) | length", $tplRel) | ConvertFrom-Json
if ("$cacheJobs" -ne "1") {
  [Console]::Error.WriteLine("check-php-test-cache: expected exactly one job with a cache: block, found $cacheJobs")
  $status = 1
}

# The cache key must depend on composer.lock, so a lock change invalidates the
# cache.
$files = @(Invoke-YqJson @("eval", "select(document_index == 1) | .[] | select(.cache != null) | .cache.key.files[]", $tplRel) | ConvertFrom-Json)
if ($files.Count -eq 0) {
  [Console]::Error.WriteLine("check-php-test-cache: php-test cache key has no files list (expected composer.lock)")
  $status = 1
} elseif ($files -notcontains "composer.lock") {
  [Console]::Error.WriteLine("check-php-test-cache: php-test cache key files do not include composer.lock: $($files -join ', ')")
  $status = 1
}

# The cache key prefix must include the PHP version, so 8.4 and 8.5 jobs do
# not share a cache.
$prefix = Invoke-YqJson @("eval", "select(document_index == 1) | .[] | select(.cache != null) | .cache.key.prefix", $tplRel) | ConvertFrom-Json
if ([string]::IsNullOrEmpty($prefix)) {
  [Console]::Error.WriteLine("check-php-test-cache: php-test cache key has no prefix")
  $status = 1
} elseif ($prefix -notlike "*PHP_VERSION*") {
  [Console]::Error.WriteLine("check-php-test-cache: php-test cache key prefix does not include the PHP version: $prefix")
  $status = 1
}

if ($status -eq 0) {
  Write-Output "check-php-test-cache: ok"
}
exit $status
