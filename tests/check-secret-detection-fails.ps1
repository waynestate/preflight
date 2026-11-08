# check-secret-detection-fails.ps1: does the secret-detection component still
# fail a bad app and pass a clean one?
#
# Windows twin of check-secret-detection-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (zricethezav/gitleaks, pinned
# by digest in templates/secret-detection/template.yml) and performs the
# template's own command from templates/secret-detection/template.yml on
# copies of the fixture in a temp dir. This wrapper checks the template lines
# natively, then runs the .sh in that image with Docker:
#
#   docker run --rm --entrypoint sh -v "<repo>:/app" -w /app \
#     zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f \
#     tests/check-secret-detection-fails.sh
#
# One result line per case goes to stdout; a case's log is printed only for a
# case that went wrong. Needs PowerShell 7 and Docker, no bash. Its twin,
# check-secret-detection-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"
$Template = Join-Path $Root "templates/secret-detection/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-secret-detection-fails: $message")
  $script:status = 1
}

# (a) the job keeps the plain gitleaks dir line, so Gitleaks' exit code is
# the job result: no tee, no pipe, no swallowed exit code.
$wantScan = '      gitleaks dir --redact --no-banner --config="$CONFIG" --report-format=json --report-path="$CI_PROJECT_DIR/gitleaks.json" .'
if (Test-Path -LiteralPath $Template) {
  $lines = [IO.File]::ReadAllLines($Template)
  if (-not ($lines -contains $wantScan)) {
    Fail "secret-detection job does not run gitleaks dir plainly (no tee, no pipe)"
  }
  foreach ($line in $lines) {
    if ($line -match 'gitleaks dir' -and $line -match '\|\||\| ?tee|; ?true') {
      Fail "a gitleaks dir line swallows the exit code (||, | tee or ; true)"
      break
    }
  }
} else {
  Fail "template missing: templates/secret-detection/template.yml"
}

if (-not (Test-Path -LiteralPath (Join-Path $Root "tests/secret-detection-clean/src/app.php"))) {
  Fail "fixture missing: tests/secret-detection-clean"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-secret-detection-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script works in a temp dir inside the container; nothing is written
# into the checkout.
docker run --rm --entrypoint sh -v "${Root}:/app" -w /app $Image "tests/check-secret-detection-fails.sh"
exit $LASTEXITCODE
