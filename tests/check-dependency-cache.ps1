# check-dependency-cache.ps1: do the components and this repository's own
# pipeline keep their dependency downloads cached?
#
# The stack's rule (2026-11-07): every dependency download is cached or
# proxied, so a busy day of pipelines never gets the runner's address rate
# limited by Docker Hub, Packagist or npm. Three practices, checked in one
# pass:
#
#   * A component whose image default comes from Docker Hub has the
#     image_prefix input, defaulting to the group's Dependency Proxy
#     (${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}), and every job image is
#     $[[ inputs.image_prefix ]]/$[[ inputs.image ]].
#   * A component whose jobs run composer install, update, require or
#     create-project, or npm ci or install, has a cache: block and points
#     the tool at it (COMPOSER_CACHE_DIR; NPM_CONFIG_CACHE, npm_config_cache
#     or --cache).
#   * In .gitlab-ci.yml, every Docker Hub job image starts with
#     ${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/, and no component include
#     passes an image that already carries the proxy (the component adds it,
#     and twice is a path Docker Hub has never heard of).
#
# Images on other registries (mcr.microsoft.com, quay.io) are left alone:
# GitLab's Dependency Proxy serves Docker Hub only. The twin of
# check-dependency-cache.sh, with plain string matching, so it needs no
# modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Proxy = '${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}'
$Prefixed = '$[[ inputs.image_prefix ]]/$[[ inputs.image ]]'

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-dependency-cache: $message")
  $script:status = 1
}

# True when $ref names a Docker Hub image, that is, when nothing in front of
# the first slash looks like a registry host.
function Test-DockerHub([string]$ref) {
  $nameTag = ($ref -split '@', 2)[0]
  if (-not $nameTag.Contains('/')) { return $true }
  $first = ($nameTag -split '/', 2)[0]
  if ($first.Contains('.') -or $first.Contains(':') -or $first -eq 'localhost') { return $false }
  return $true
}

# The default of input $key in the spec lines, without surrounding quotes.
function Get-InputDefault([string[]]$spec, [string]$key) {
  $inBlock = $false
  foreach ($line in $spec) {
    if ($line -match ('^    ' + [regex]::Escape($key) + ':[ \t]*$')) { $inBlock = $true; continue }
    if ($inBlock) {
      if ($line -match '^    [A-Za-z_]' -or $line -match '^[^ ]') { $inBlock = $false; continue }
      if ($line -match '^      default:[ \t]*(.*)$') { return ($Matches[1] -replace '^"|"$', '') }
    }
  }
  return ''
}

# Every job image value in the jobs lines, inline or block form.
function Get-JobImages([string[]]$jobs) {
  $images = @()
  $block = $false
  foreach ($line in $jobs) {
    if ($line -match '^  image:[ \t]*$') { $block = $true; continue }
    if ($block) {
      $block = $false
      if ($line -match '^    name:[ \t]*(.*)$') { $images += $Matches[1] }
      continue
    }
    if ($line -match '^  image:[ \t]+(.*)$') { $images += $Matches[1] }
  }
  return $images
}

$composerPattern = '(^|[\s(])composer\s+(install|update|require|create-project|global\s+require)'
$npmPattern = '(^|[\s(])npm\s+(ci|install)'

Get-ChildItem -Path (Join-Path $Root "templates") -Directory | ForEach-Object {
  $tpl = Join-Path $_.FullName "template.yml"
  if (-not (Test-Path -LiteralPath $tpl)) { return }
  $name = $_.Name

  $lines = @(Get-Content -LiteralPath $tpl)
  $sepIndex = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^---[ \t]*$') { $sepIndex = $i }
  }
  if ($sepIndex -lt 0) {
    Fail "${name}: no --- separator between the spec and jobs documents"
    return
  }
  $spec = @($lines[0..($sepIndex - 1)])
  $jobs = @($lines[($sepIndex + 1)..($lines.Count - 1)])

  # Docker Hub images go through image_prefix.
  $default = Get-InputDefault $spec 'image'
  if ($default -ne '' -and (Test-DockerHub $default)) {
    $prefixDefault = Get-InputDefault $spec 'image_prefix'
    if ($prefixDefault -ne $Proxy) {
      Fail "${name}: the image default ($default) is on Docker Hub, so the image_prefix input must default to $Proxy (found '$prefixDefault')"
    }
    foreach ($image in (Get-JobImages $jobs)) {
      if ($image -ne $Prefixed) {
        Fail "${name}: a Docker Hub job image must be $Prefixed, found: $image"
      }
    }
  }

  # Package downloads are cached. Only code lines count: a comment that
  # mentions an install is not one.
  $code = @($jobs | Where-Object { $_ -notmatch '^[ \t]*#' })
  $hasCache = [bool]($jobs | Where-Object { $_ -match '^  cache:' })
  if ($code | Where-Object { $_ -cmatch $composerPattern }) {
    if (-not $hasCache) { Fail "${name}: runs Composer but has no cache: block" }
    if (-not ($jobs | Where-Object { $_ -match '^    COMPOSER_CACHE_DIR:' })) {
      Fail "${name}: runs Composer but does not set COMPOSER_CACHE_DIR"
    }
  }
  if ($code | Where-Object { $_ -cmatch $npmPattern }) {
    if (-not $hasCache) { Fail "${name}: runs npm but has no cache: block" }
    $pointed = ($jobs | Where-Object { $_ -cmatch '^    (NPM_CONFIG_CACHE|npm_config_cache):' }) -or
      ($code | Where-Object { $_ -cmatch ($npmPattern + '.*--cache\s') })
    if (-not $pointed) {
      Fail "${name}: runs npm but points it at no cache (NPM_CONFIG_CACHE, npm_config_cache or --cache)"
    }
  }
}

# This repository's own pipeline.
$ciPath = Join-Path $Root ".gitlab-ci.yml"
if (Test-Path -LiteralPath $ciPath) {
  $top = ''
  $block = $false
  foreach ($line in @(Get-Content -LiteralPath $ciPath)) {
    if ($line -match '^[^ \t#-]') { $top = ($line -replace ':.*$', ''); $block = $false }
    $image = $null
    if ($top -eq 'include') {
      if ($line -match '^[ \t]+image:[ \t]+(.*)$' -and $Matches[1].Contains('CI_DEPENDENCY_PROXY')) {
        Fail ".gitlab-ci.yml: a component include passes an image that already carries the proxy; drop it, the component's image_prefix adds it: $($Matches[1])"
      }
      continue
    }
    if ($line -match '^  image:[ \t]*$') { $block = $true; continue }
    if ($block) {
      $block = $false
      if ($line -match '^    name:[ \t]*(.*)$') { $image = $Matches[1] }
    } elseif ($line -match '^  image:[ \t]+(.*)$') {
      $image = $Matches[1]
    }
    if ($null -eq $image) { continue }
    $image = $image -replace '^"|"$', ''
    if ($image.StartsWith("$Proxy/") -or $image.StartsWith('$')) { continue }
    if (Test-DockerHub $image) {
      Fail ".gitlab-ci.yml: job $top pulls $image from Docker Hub; put $Proxy/ in front of it"
    }
  }
}

if ($status -eq 0) {
  Write-Output "check-dependency-cache: ok"
}
exit $status
