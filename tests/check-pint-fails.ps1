# check-pint-fails.ps1: does the pint component still fail a bad app
# and pass a clean one?
#
# Windows twin of check-pint-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (composer:2.10.3, pinned by
# digest in templates/pint/template.yml) and performs the template's own
# commands from templates/pint/template.yml on copies of the two fixtures in
# a temp dir. This wrapper checks the template line natively, then runs the
# .sh in that image with Docker:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app \
#     composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc \
#     sh tests/check-pint-fails.sh
#
# One result line per case goes to stdout; a fixture's output is printed
# only for a case that went wrong. Needs PowerShell 7 and Docker, no bash.
# Its twin, check-pint-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.10.3@sha256:b6dcd72ca98fa19d0e5b8476de179859704891fad06dd9e0b96833d4c430a5fc"
$Template = Join-Path $Root "templates/pint/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-pint-fails: $message")
  $script:status = 1
}

# (a) the job runs the pint command as its own script line, so the exit
# code is the job result: no pipe, no || true.
$want = '    - vendor/bin/pint --test --config=$[[ inputs.config ]]'
if (Test-Path -LiteralPath $Template) {
  if (-not ([IO.File]::ReadAllLines($Template) -contains $want)) {
    Fail "pint job does not run the pint command as its own script line (no pipe, no || true)"
  }
} else {
  Fail "template missing: templates/pint/template.yml"
}

foreach ($fixture in @("tests/fixture-app", "tests/pint-fails")) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root (Join-Path $fixture "composer.json")))) {
    Fail "fixture missing: $fixture"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-pint-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The repository is bound read-only: the script copies the fixtures to a
# temp dir inside the container, so nothing is ever written into the checkout.
docker run --rm -v "${Root}:/app:ro" -w /app $Image "sh" "tests/check-pint-fails.sh"
exit $LASTEXITCODE
