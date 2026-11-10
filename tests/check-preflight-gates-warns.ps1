# check-preflight-gates-warns.ps1: do PROCTOR's preflight-gates and
# preflight-pinned checks still warn about pipelines that skip or weaken
# Preflight, without failing them?
#
# Windows twin of check-preflight-gates-warns.sh. The .sh is the payload of
# a container: it runs inside the template's image (composer:2.11.1, pinned
# by digest in templates/proctor/template.yml), copies tests/fixture-app to
# a temp dir, installs its dependencies once with the proctor template's
# install flags, then swaps only the copy's .gitlab-ci.yml per case and
# runs the template's default command, vendor/bin/proctor check
# --format=codequality: as-is (warns no-include and no-proctor-job), an
# include pinned to a release tag with allow_failure: true (warns
# allow-failure) and an include at @main (warns unpinned). Every case exits
# 0: the warnings never fail the run. This wrapper runs the .sh in that
# image with Docker, on a read-only mount:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-preflight-gates-warns.sh
#
# composer install downloads the fixture's packages once, so this needs the
# network; the shared stack-composer-cache volume feeds the container's
# COMPOSER_CACHE_DIR. One result line per case goes to stdout; a case's
# output is printed only when it went wrong. Needs PowerShell 7 and Docker,
# no bash. Its twin, check-preflight-gates-warns.sh, does the same on Linux
# and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-preflight-gates-warns: $message")
  $script:status = 1
}

foreach ($f in @(
    'tests/fixture-app/composer.json',
    'tests/fixture-app/composer.lock',
    'tests/fixture-app/.gitlab-ci.yml'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) {
    Fail "fixture missing: $f"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-preflight-gates-warns: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The .sh copies the fixture to a temp dir inside the container and uses a
# fresh Composer home there; the checkout is mounted read-only and the
# package downloads come from the shared stack-composer-cache volume.
docker run --rm -v "${Root}:/app:ro" -v stack-composer-cache:/tmp/cache -e COMPOSER_CACHE_DIR=/tmp/cache -w /app $Image "sh" "tests/check-preflight-gates-warns.sh"
exit $LASTEXITCODE
