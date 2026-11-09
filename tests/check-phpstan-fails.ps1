# check-phpstan-fails.ps1: does the phpstan component still fail a bad app
# and pass a clean one?
#
# Windows twin of check-phpstan-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (composer:2.10.3, pinned by
# digest in templates/phpstan/template.yml) and performs the template's own
# commands from templates/phpstan/template.yml on copies of the two fixtures
# in a temp dir. This wrapper checks the template line natively, then runs
# the .sh in that image with Docker:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app \
#     composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48 \
#     sh tests/check-phpstan-fails.sh
#
# One result line per case goes to stdout; a fixture's output is printed
# only for a case that went wrong. Needs PowerShell 7 and Docker, no bash.
# Its twin, check-phpstan-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.10.3@sha256:2cf275428757e5435a667bfc0d038b14520ca02be2b1b70d44a05c8c19e2de48"
$Template = Join-Path $Root "templates/phpstan/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-phpstan-fails: $message")
  $script:status = 1
}

# (a) the job keeps a plain redirect of the command to the report, so the
# exit code is the job result: no tee, no pipe.
$want = '    - vendor/bin/phpstan analyse --no-progress --error-format=gitlab --memory-limit=$[[ inputs.memory_limit ]] -c $[[ inputs.config ]] > "$CI_PROJECT_DIR/phpstan-report.json"'
if (Test-Path -LiteralPath $Template) {
  if (-not ([IO.File]::ReadAllLines($Template) -contains $want)) {
    Fail "phpstan job does not redirect the command plainly to phpstan-report.json (no tee, no pipe)"
  }
} else {
  Fail "template missing: templates/phpstan/template.yml"
}

foreach ($fixture in @("tests/fixture-app", "tests/phpstan-fails")) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root (Join-Path $fixture "composer.json")))) {
    Fail "fixture missing: $fixture"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-phpstan-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The repository is bound read-only: the script copies the fixtures to a
# temp dir inside the container, so nothing is ever written into the checkout.
docker run --rm -v "${Root}:/app:ro" -w /app $Image "sh" "tests/check-phpstan-fails.sh"
exit $LASTEXITCODE
