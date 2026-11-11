# check-composer-ci-fails.ps1: does the composer-ci component still pass a
# project whose composer ci exits 0, and fail one whose composer ci exits
# non-zero, or whose composer install cannot run?
#
# Windows twin of check-composer-ci-fails.sh. The .sh is the payload of
# a container: it runs inside the template's image (composer:2.11.1, pinned
# by digest in templates/composer-ci/template.yml), renders the
# template's own script lines per case and runs them on copies of
# tests/ci-fixtures/pass (clean) and tests/ci-fixtures/fail (must-fail),
# plus a broken copy of pass whose install cannot run. This wrapper checks
# the template lines natively, then runs the .sh in that image with Docker,
# on a read-only mount:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-composer-ci-fails.sh
#
# The fixtures carry no packages, so the check needs no network. One
# result line per case goes to stdout; a case's output is printed only when
# it went wrong. Needs PowerShell 7 and Docker, no bash. Its twin,
# check-composer-ci-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0"
$Template = Join-Path $Root "templates/composer-ci/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-composer-ci-fails: $message")
  $script:status = 1
}

# (a) the job lets Composer's exit code be the result: no allow_failure,
# no flag that skips the app's scripts or ignores its platform requirements
# on the install, no swallowed exit code on the ci line, and the two lines
# the component promises are still there, with interruptible and a timeout.
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
    if ($jobs | Where-Object { $_ -match '^  allow_failure:' }) {
      Fail "the composer-ci job has allow_failure; a failing composer ci must fail"
    }
    if ($jobs | Where-Object { $_.Contains('composer install') -and $_ -match '--no-scripts|--ignore-platform-reqs' }) {
      Fail "the composer install line passes --no-scripts or --ignore-platform-reqs; the app's install must run"
    }
    if ($jobs | Where-Object { $_.Contains('composer ci') -and $_ -match '\|\||\| *tee|; *true' }) {
      Fail "the composer ci line swallows the exit code (||, | tee, ; true)"
    }
    $installLine = '    - composer install --no-interaction --no-progress --prefer-dist'
    if (-not ($jobs -ccontains $installLine)) {
      Fail "the job lost its install line: expected `"$installLine`""
    }
    $ciLine = '    - composer ci'
    if (-not ($jobs -ccontains $ciLine)) {
      Fail "the job lost its ci line: expected `"$ciLine`""
    }
    if (-not ($jobs -ccontains '  interruptible: true')) {
      Fail "the composer-ci job lost interruptible: true"
    }
    if (-not ($jobs | Where-Object { $_ -match '^  timeout:' })) {
      Fail "the composer-ci job lost its timeout"
    }
  }
} else {
  Fail "template missing: templates/composer-ci/template.yml"
}

foreach ($f in @(
    'tests/ci-fixtures/pass/composer.json',
    'tests/ci-fixtures/fail/composer.json'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) {
    Fail "fixture missing: $f"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-composer-ci-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script copies the fixtures to a temp dir inside the container and
# uses a fresh Composer home and cache there; the checkout is mounted
# read-only and keeps no cache.
docker run --rm -v "${Root}:/app:ro" -w /app $Image "sh" "tests/check-composer-ci-fails.sh"
exit $LASTEXITCODE
