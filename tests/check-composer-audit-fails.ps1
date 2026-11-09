# check-composer-audit-fails.ps1: does the composer-audit component still
# fail a lock with a known advisory, a malware-flagged version or an
# abandoned package, and pass a clean one?
#
# Windows twin of check-composer-audit-fails.sh. The .sh is the payload of
# a container: it runs inside the template's image (composer:2.11.1, pinned
# by digest in templates/composer-audit/template.yml), renders the
# template's own script lines per case and runs them on copies of
# tests/fixture-app (clean) and tests/audit-fixtures/advisory, malware and
# abandoned (must-fail). This wrapper checks the template lines natively,
# then runs the .sh in that image with Docker, on a read-only mount:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-composer-audit-fails.sh
#
# composer audit asks Packagist for advisories and filter lists, so this
# needs the network. One result line per case goes to stdout; a case's
# output is printed only when it went wrong. Needs PowerShell 7 and Docker,
# no bash. Its twin, check-composer-audit-fails.sh, does the same on Linux
# and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0"
$Template = Join-Path $Root "templates/composer-audit/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-composer-audit-fails: $message")
  $script:status = 1
}

# (a) the job lets Composer's exit code be the result: no allow_failure,
# no flag that hides an unreachable advisory source or a severity, no
# variable that turns the audit or a policy off, no swallowed exit code.
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
      Fail "the composer-audit job has allow_failure; advisories must fail"
    }
    if ($jobs | Where-Object { $_.Contains('--ignore-unreachable') }) {
      Fail "the composer-audit job passes --ignore-unreachable; an unreachable advisory source must fail"
    }
    if ($jobs | Where-Object { $_.Contains('--ignore-severity') }) {
      Fail "the composer-audit job passes --ignore-severity"
    }
    if ($jobs | Where-Object { $_ -cmatch 'COMPOSER_(NO_AUDIT|AUDIT_ABANDONED|POLICY)' }) {
      Fail "the composer-audit job sets a COMPOSER_ audit variable; use the abandoned input"
    }
    if ($jobs | Where-Object { $_.Contains('composer audit') -and $_ -match '\|\||\| *tee|; *true|--format' }) {
      Fail "the composer audit line swallows the exit code or changes the format (||, | tee, ; true, --format)"
    }
    $auditLine = '    - composer audit --locked --abandoned=$[[ inputs.abandoned ]]'
    if (-not ($jobs -ccontains $auditLine)) {
      Fail "the job lost its audit line: expected `"composer audit --locked --abandoned=`$[[ inputs.abandoned ]]`""
    }
  }
} else {
  Fail "template missing: templates/composer-audit/template.yml"
}

foreach ($f in @(
    'tests/fixture-app/composer.lock',
    'tests/audit-fixtures/advisory/composer.lock',
    'tests/audit-fixtures/malware/composer.lock',
    'tests/audit-fixtures/abandoned/composer.lock'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) {
    Fail "fixture missing: $f"
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-composer-audit-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script copies the fixtures to a temp dir inside the container and
# uses a fresh Composer home and cache there; the checkout is mounted
# read-only and keeps no cache.
docker run --rm -v "${Root}:/app:ro" -w /app $Image "sh" "tests/check-composer-audit-fails.sh"
exit $LASTEXITCODE
