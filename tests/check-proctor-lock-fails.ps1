# check-proctor-lock-fails.ps1: does PROCTOR's lock-committed check still
# fail an app without composer.lock, and pass one with it?
#
# Windows twin of check-proctor-lock-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (composer:2.11.1, pinned
# by digest in templates/proctor/template.yml), copies tests/fixture-app to
# a temp dir, installs its dependencies with the proctor template's install
# flags and runs the template's default command,
# vendor/bin/proctor check --format=codequality, on the copy with and
# without composer.lock (Composer recreates a missing lock during the
# install, so the .sh deletes it after the install, right before the check).
# This wrapper checks the template's default command natively, then runs the
# .sh in that image with Docker, on a read-only mount:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-proctor-lock-fails.sh
#
# composer install downloads the fixture's packages, so this needs the
# network; the shared stack-composer-cache volume feeds the container's
# COMPOSER_CACHE_DIR. One result line per case goes to stdout; a case's
# output is printed only when it went wrong. Needs PowerShell 7 and Docker,
# no bash. Its twin, check-proctor-lock-fails.sh, does the same on Linux
# and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0"
$Template = Join-Path $Root "templates/proctor/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-proctor-lock-fails: $message")
  $script:status = 1
}

# The .sh runs the template's default command; if the template changes it,
# teach both.
$defaultLine = '      default: vendor/bin/proctor check --format=codequality'
if (Test-Path -LiteralPath $Template) {
  if (-not ([IO.File]::ReadAllLines($Template) -ccontains $defaultLine)) {
    Fail "the proctor template no longer defaults to `"vendor/bin/proctor check --format=codequality`""
  }
} else {
  Fail "template missing: templates/proctor/template.yml"
}

foreach ($f in @(
    'tests/fixture-app/composer.json',
    'tests/fixture-app/composer.lock'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) {
    Fail "fixture missing: $f"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-proctor-lock-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The .sh copies the fixture to a temp dir inside the container and uses a
# fresh Composer home there; the checkout is mounted read-only and the
# package downloads come from the shared stack-composer-cache volume.
docker run --rm -v "${Root}:/app:ro" -v stack-composer-cache:/tmp/cache -e COMPOSER_CACHE_DIR=/tmp/cache -w /app $Image "sh" "tests/check-proctor-lock-fails.sh"
exit $LASTEXITCODE
