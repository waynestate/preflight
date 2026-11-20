# check-release-gate-fails.ps1: does the release-gate component still pass a
# tag whose commit the default branch already tested, and fail one it never
# saw?
#
# Windows twin of check-release-gate-fails.sh. The .sh is the payload of
# a container: it runs inside the template's image (composer:2.11.1, pinned
# by digest in templates/release-gate/template.yml), renders the
# template's own script lines per case and runs them with a fake curl first
# on PATH and a tiny temp git repo as the checkout: HTTP 200 with a
# successful pipeline (exit 0), HTTP 200 with an empty list (must fail),
# HTTP 403 with the commit on the default branch (exit 0, git fallback),
# and HTTP 403 with the commit off it (must fail). This wrapper checks the
# template lines natively, then runs the .sh in that image with Docker,
# on a read-only mount:
#
#   docker run --rm -v "<repo>:/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-release-gate-fails.sh
#
# The git fixtures live in a temp dir inside the container, so the check
# needs no network. One result line per case goes to stdout; a case's
# output is printed only when it went wrong. Needs PowerShell 7 and Docker,
# no bash. Its twin, check-release-gate-fails.sh, does the same on Linux
# and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0"
$Template = Join-Path $Root "templates/release-gate/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-release-gate-fails: $message")
  $script:status = 1
}

# (a) the job keeps the gate honest: it may not be allowed to fail, it runs
# only on tags, it carries the full history the git fallback needs, and the
# script still asks the API with the job token and falls back to
# merge-base, with interruptible and a timeout.
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
      Fail "the release-gate job has allow_failure; the gate must be able to stop the tag pipeline"
    }
    if (-not ($jobs -ccontains '    - if: $CI_COMMIT_TAG')) {
      Fail "the release-gate job no longer runs only on tags"
    }
    if (-not ($jobs -ccontains '    GIT_DEPTH: "0"')) {
      Fail 'the release-gate job lost GIT_DEPTH: "0"; the git fallback needs the full history'
    }
    if (-not ($jobs -ccontains '  interruptible: true')) {
      Fail "the release-gate job lost interruptible: true"
    }
    if (-not ($jobs | Where-Object { $_ -match '^  timeout:' })) {
      Fail "the release-gate job lost its timeout"
    }
    if (-not ($jobs | Where-Object { $_.Contains('JOB-TOKEN: $CI_JOB_TOKEN') })) {
      Fail "the job no longer authenticates the API call with the job token"
    }
    if (-not ($jobs | Where-Object { $_.Contains('merge-base --is-ancestor') })) {
      Fail "the job lost its git fallback"
    }
  }
} else {
  Fail "template missing: templates/release-gate/template.yml"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-release-gate-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script builds its git fixtures and temp dirs inside the container;
# the checkout is mounted read-only and keeps no cache.
docker run --rm -v "${Root}:/app:ro" -w /app $Image "sh" "tests/check-release-gate-fails.sh"
exit $LASTEXITCODE
