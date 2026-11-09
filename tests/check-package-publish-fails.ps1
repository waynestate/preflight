# check-package-publish-fails.ps1: do the package-publish component's
# offline guards still stop a bad release?
#
# Windows twin of check-package-publish-fails.sh. The .sh is the payload of
# a container: it runs inside the template's image (composer:2.11.1, pinned
# by digest in templates/package-publish/template.yml) and performs the
# template's own first two script blocks (the tag guard and the
# composer.json guard) on copies of the fixtures in a temp dir. This wrapper
# checks the template lines natively, then runs the .sh in that image with
# Docker:
#
#   docker run --rm -v "<repo>:/app" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-package-publish-fails.sh
#
# One result line per case goes to stdout; a fixture's output is printed
# only for a case that went wrong. Needs PowerShell 7 and Docker, no bash.
# Its twin, check-package-publish-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Image = "composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0"
$Template = Join-Path $Root "templates/package-publish/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-package-publish-fails: $message")
  $script:status = 1
}

# (a) the template keeps the offline guards: the semver grep -Eq line, the
# two failure messages, and an exit 1 right after the semver message.
$wantSemver = '      if ! printf ''%s\n'' "$tag" | grep -Eq ''^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$''; then'
if (Test-Path -LiteralPath $Template) {
  $lines = [IO.File]::ReadAllLines($Template)
  if (-not ($lines -contains $wantSemver)) {
    Fail "the template dropped the semver guard's grep -Eq line"
  }
  $found = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -like '*is not a semantic version*') {
      $found = $true
      if ($i + 1 -ge $lines.Count -or $lines[$i + 1].Trim() -ne 'exit 1') {
        Fail "the semver guard no longer exits 1 after its message"
      }
      break
    }
  }
  if (-not $found) {
    Fail "the template dropped the semver guard's message"
  }
  if (-not ($lines | Where-Object { $_ -like '*composer.json not found in the project root.*' })) {
    Fail "the template dropped the composer.json guard's message"
  }
} else {
  Fail "template missing: templates/package-publish/template.yml"
}

if (-not (Test-Path -LiteralPath (Join-Path $Root "tests/package-publish-badtag/composer.json"))) {
  Fail "fixture missing: tests/package-publish-badtag"
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "tests/package-publish-nocomposer/README.md"))) {
  Fail "fixture missing: tests/package-publish-nocomposer"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-package-publish-fails: docker is required")
  exit 1
}

if ($status -ne 0) {
  exit 1
}

# The script copies the fixtures to a temp dir inside the container; it
# writes nothing into the checkout, so it keeps no cache.
docker run --rm -v "${Root}:/app" -w /app $Image "sh" "tests/check-package-publish-fails.sh"
exit $LASTEXITCODE
