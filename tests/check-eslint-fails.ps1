# check-eslint-fails.ps1: does the eslint component still fail a bad app
# and pass a clean one?
#
# Windows twin of check-eslint-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (node:22.13-alpine, pinned
# by digest in templates/eslint/template.yml) and performs the template's
# own commands from templates/eslint/template.yml on copies of the two
# fixtures in a temp dir. This wrapper checks the template lines natively,
# then runs the .sh in that image with Docker:
#
#   docker run --rm -v "<repo>:/app" -w /app \
#     node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da \
#     sh tests/check-eslint-fails.sh
#
# One result line per case goes to stdout; a fixture's output is printed
# only for a case that went wrong. Needs PowerShell 7 and Docker, no bash.
# Its twin, check-eslint-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da"
$Template = Join-Path $Root "templates/eslint/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-eslint-fails: $message")
  $script:status = 1
}

# (a) the job keeps the plain npm ci and eslint lines, so the tools' exit
# codes are the job result: no tee, no pipe, no swallowed exit code.
$wantInstall = '    - npm ci --ignore-scripts --cache .npm-cache'
$wantLint = '    - npx --no-install eslint $[[ inputs.eslint_args ]]'
if (Test-Path -LiteralPath $Template) {
  $lines = [IO.File]::ReadAllLines($Template)
  if (-not ($lines -contains $wantInstall)) {
    Fail "eslint job does not run npm ci plainly (no tee, no pipe)"
  }
  if (-not ($lines -contains $wantLint)) {
    Fail "eslint job does not run eslint plainly (no tee, no pipe)"
  }
  foreach ($line in $lines) {
    if ($line -match 'eslint' -and $line -match '\|\||\| ?tee|; ?true') {
      Fail "an eslint line swallows the exit code (||, | tee or ; true)"
      break
    }
  }
} else {
  Fail "template missing: templates/eslint/template.yml"
}

foreach ($fixture in @("tests/eslint-clean", "tests/eslint-fails")) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root (Join-Path $fixture "package.json")))) {
    Fail "fixture missing: $fixture"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-eslint-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script copies the fixtures to a temp dir inside the container; the
# only thing written into the checkout is the npm cache folder (.npm-cache),
# which the must-fail-eslint job's cache saves under a fixed key.
docker run --rm -v "${Root}:/app" -w /app $Image "sh" "tests/check-eslint-fails.sh"
exit $LASTEXITCODE
