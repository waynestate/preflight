# check-sbom-fails.ps1: does the sbom component still fail a bad app
# and pass a clean one?
#
# Windows twin of check-sbom-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (composer:2.11.1, pinned
# by digest in templates/sbom/template.yml) and performs the template's
# own commands from templates/sbom/template.yml on copies of the two
# fixtures in a temp dir. This wrapper checks the template lines natively,
# then runs the .sh in that image with Docker:
#
#   docker run --rm -v "<repo>:/app" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-sbom-fails.sh
#
# One result line per case goes to stdout; a fixture's output is printed
# only for a case that went wrong. Needs PowerShell 7 and Docker, no bash.
# Its twin, check-sbom-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0"
$Template = Join-Path $Root "templates/sbom/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-sbom-fails: $message")
  $script:status = 1
}

# (a) the job keeps the plain install and plugin lines, and both make-sbom
# branches keep --validate (the omit_dev=true branch keeps --omit=dev), so
# Composer's exit code is the job result: no tee, no pipe, no swallowed
# exit code.
$wantInstall = '    - composer install --no-interaction --no-progress --prefer-dist --no-scripts --ignore-platform-reqs'
$wantRequire = '    - composer global require cyclonedx/cyclonedx-php-composer:^6.2'
if (Test-Path -LiteralPath $Template) {
  $lines = [IO.File]::ReadAllLines($Template)
  if (-not ($lines -contains $wantInstall)) {
    Fail "sbom job does not run composer install plainly (no tee, no pipe)"
  }
  if (-not ($lines -contains $wantRequire)) {
    Fail "sbom job does not run composer global require plainly (no tee, no pipe)"
  }
  $sbomText = (@($lines | Where-Object { $_ -match 'CycloneDX:make-sbom' })) -join "`n"
  if ($sbomText -eq "") {
    Fail "sbom job does not run make-sbom"
  }
  if ([regex]::Matches($sbomText, 'CycloneDX:make-sbom').Count -ne 2) {
    Fail "sbom job does not carry both make-sbom branches"
  }
  if ([regex]::Matches($sbomText, '--validate').Count -ne 2) {
    Fail "a make-sbom branch lost --validate"
  }
  if (($sbomText -replace '; *else.*$', '') -notmatch '--omit=dev') {
    Fail "the omit_dev=true branch lost --omit=dev"
  }
  foreach ($line in $lines) {
    if ($line -match 'composer' -and $line -match '\|\||\| ?tee|; ?true') {
      Fail "a composer line swallows the exit code (||, | tee or ; true)"
      break
    }
  }
} else {
  Fail "template missing: templates/sbom/template.yml"
}

foreach ($fixture in @("tests/sbom-clean", "tests/sbom-fails")) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root (Join-Path $fixture "composer.json")))) {
    Fail "fixture missing: $fixture"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-sbom-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script copies the fixtures to a temp dir inside the container; the
# only thing written into the checkout is the Composer cache folder
# (.composer-cache), which the must-fail-sbom job's cache saves under a
# fixed key.
docker run --rm -v "${Root}:/app" -w /app $Image "sh" "tests/check-sbom-fails.sh"
exit $LASTEXITCODE
