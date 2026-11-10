# check-squire-kit-fails.ps1: does the squire-kit component still fail a
# drifted kit and pass a clean one?
#
# Windows twin of check-squire-kit-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (composer:2.11.1, pinned
# by digest in templates/squire-kit/template.yml), renders the template's
# own script per case and runs it on copies of tests/squire-kit-fixture:
# the clean kit (must pass), a copy with a line appended to
# .squire/php-web.ini (must fail, naming the file) and a copy with no
# .squire.json (must stop with exit 2). This wrapper checks the template
# lines natively, then runs the .sh in that image with Docker:
#
#   docker run --rm -v "<repo>:/app" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-squire-kit-fails.sh
#
# The script installs the Squire release the kit records, so this needs
# the network, like the component. One result line per case goes to stdout;
# a case's log is printed only when it went wrong. Needs PowerShell 7 and
# Docker, no bash. Its twin, check-squire-kit-fails.sh, does the same on
# Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0"
$Template = Join-Path $Root "templates/squire-kit/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-squire-kit-fails: $message")
  $script:status = 1
}

# (a) the job keeps the compare step that lets Squire's exit code be the
# job result: it stops with exit 2 when the folder has no .squire.json,
# runs init --check on the kit folder and exits with its code.
if (Test-Path -LiteralPath $Template) {
  $lines = [IO.File]::ReadAllLines($Template)
  $sep = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^---\s*$') { $sep = $i }
  }
  if ($sep -lt 0) {
    Fail "no '---' separator between the spec and jobs documents"
  } else {
    $jobs = @($lines[($sep + 1)..($lines.Count - 1)])
    if (-not ($jobs -contains '      if [ ! -f .squire.json ]; then')) {
      Fail "the job does not stop when the folder has no .squire.json"
    }
    if (-not ($jobs -contains '      php "$squire_home/squire/bin/squire" init --check --path=. || status=$?')) {
      Fail "the job does not run squire init --check on the kit folder"
    }
    if (-not ($jobs -contains '      exit "$status"')) {
      Fail "the job does not exit with squire init --check's code"
    }
  }
} else {
  Fail "template missing: templates/squire-kit/template.yml"
}

foreach ($f in @(
    'tests/squire-kit-fixture/.squire.json',
    'tests/squire-kit-fixture/.squire/php-web.ini'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) {
    Fail "fixture missing: $f"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-squire-kit-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script copies the fixture to a temp dir inside the container and
# keeps its Composer home and cache there unless COMPOSER_CACHE_DIR points
# elsewhere; the checkout is mounted read-only and keeps no cache.
docker run --rm -v "${Root}:/app:ro" -w /app $Image "sh" "tests/check-squire-kit-fails.sh"
exit $LASTEXITCODE
