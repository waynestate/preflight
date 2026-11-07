# check-php-test-fails.ps1: does the php-test component still fail a bad app
# and pass a clean one?
#
# Windows twin of check-php-test-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (php:8.3-cli-trixie, the
# template's default for PHP 8.3, the stack's floor) and performs the
# template's own steps from templates/php-test/template.yml on copies of the
# two fixtures in a temp dir. This wrapper checks the template line
# natively, then runs the .sh in that image with Docker:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app php:8.3-cli-trixie \
#     sh tests/check-php-test-fails.sh
#
# One result line per case goes to stdout; a fixture's output is printed
# only for a case that went wrong. Needs PowerShell 7 and Docker, no bash.
# Its twin, check-php-test-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "php:8.3-cli-trixie"
$Template = Join-Path $Root "templates/php-test/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-php-test-fails: $message")
  $script:status = 1
}

# (a) the job runs the test command as its own script line, so the exit
# code is the job result: no pipe, no || true.
$want = '    - $[[ inputs.test_command ]]'
if (Test-Path -LiteralPath $Template) {
  if (-not ([IO.File]::ReadAllLines($Template) -contains $want)) {
    Fail "php-test job does not run the test command as its own script line (no pipe, no || true)"
  }
} else {
  Fail "template missing: templates/php-test/template.yml"
}

foreach ($fixture in @("tests/fixture-app", "tests/php-test-fails")) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root (Join-Path $fixture "composer.json")))) {
    Fail "fixture missing: $fixture"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-php-test-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The repository is bound read-only: the script copies the fixtures to a
# temp dir inside the container, so nothing is ever written into the checkout.
docker run --rm -v "${Root}:/app:ro" -w /app $Image "sh" "tests/check-php-test-fails.sh"
exit $LASTEXITCODE
