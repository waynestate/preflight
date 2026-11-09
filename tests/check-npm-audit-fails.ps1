# check-npm-audit-fails.ps1: does the npm-audit component still fail a lock
# with a known advisory, and pass a clean one, an app with no lock and a
# dev-only finding?
#
# Windows twin of check-npm-audit-fails.sh. The .sh is the payload of a
# container: it runs inside the template's image (node:22.13-alpine, pinned
# by digest in templates/npm-audit/template.yml), renders the template's
# own script per case and runs it on copies of tests/npm-audit-fails
# (must-fail) and tests/npm-audit-fixtures/clean, dev-only and no-lock.
# This wrapper checks the template lines natively, then runs the .sh in
# that image with Docker, on a read-only mount:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app \
#     node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da \
#     sh tests/check-npm-audit-fails.sh
#
# npm audit asks the registry's audit endpoint, so this needs the network.
# One result line per case goes to stdout; a case's output is printed only
# when it went wrong. Needs PowerShell 7 and Docker, no bash. Its twin,
# check-npm-audit-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "node:22.13-alpine@sha256:e2b39f7b64281324929257d0f8004fb6cb4bf0fdfb9aa8cedb235a766aec31da"
$Template = Join-Path $Root "templates/npm-audit/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-npm-audit-fails: $message")
  $script:status = 1
}

# (a) the job lets npm's exit code be the result: no allow_failure, the
# gate's exit code kept, the one || true on the report line only, and no
# flag that turns the audit off.
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
    $code = @($jobs | Where-Object { $_ -notmatch '^\s*#' })
    if ($jobs | Where-Object { $_ -match '^  allow_failure:' }) {
      Fail "the npm-audit job has allow_failure; advisories must fail"
    }
    $gate = '      if npm audit $omit --audit-level="$level" --audit=true --offline=false >"$log" 2>&1; then status=0; else status=$?; fi'
    if (-not ($jobs -ccontains $gate)) {
      Fail 'the job lost its gate line: npm audit $omit --audit-level="$level" --audit=true --offline=false, exit code kept in $status'
    }
    $exitLine = '      if [ "$status" -ne 0 ]; then exit "$status"; fi'
    if (-not ($jobs -ccontains $exitLine)) {
      Fail "the job no longer exits with the gate's exit code"
    }
    $report = '        npm audit --audit=true --offline=false || true'
    $others = @($code | Where-Object { ($_ -match '\|\||; *true') -and ($_ -cne $report) })
    if ($others.Count -gt 0) {
      Fail "a line swallows an exit code (only the full report may): $($others[0])"
    }
    if ($code | Where-Object { $_ -match '--audit=false|--offline=true|--audit-level=(none|info)|--dry-run' }) {
      Fail "the job turns the audit off (--audit=false, --offline=true, --audit-level=none or info, --dry-run)"
    }
  }
} else {
  Fail "template missing: templates/npm-audit/template.yml"
}

foreach ($f in @(
    'tests/npm-audit-fails/package-lock.json',
    'tests/npm-audit-fixtures/clean/package-lock.json',
    'tests/npm-audit-fixtures/dev-only/package-lock.json',
    'tests/npm-audit-fixtures/no-lock/package.json'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) {
    Fail "fixture missing: $f"
  }
}
if (Test-Path -LiteralPath (Join-Path $Root 'tests/npm-audit-fixtures/no-lock/package-lock.json')) {
  Fail "tests/npm-audit-fixtures/no-lock must have no package-lock.json"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-npm-audit-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script copies the fixtures to a temp dir inside the container; the
# checkout is mounted read-only and nothing is installed.
docker run --rm -v "${Root}:/app:ro" -w /app $Image "sh" "tests/check-npm-audit-fails.sh"
exit $LASTEXITCODE
