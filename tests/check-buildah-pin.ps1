# check-buildah-pin.ps1: does every Buildah image reference pin an immutable tag?
#
# Red Hat re-pushed the plain version tag of the quay.io/buildah/stable image
# and garbage-collected the old digest, so a pipeline pinned to the mutable
# tag broke. Every reference to that image in the repository must now name an
# -immutable tag pinned by digest.
#
# The script lists the tracked files with git ls-files and scans their text
# for a reference to that image whose tag is missing or does not end in
# -immutable@sha256:. Changelog history is exempt (CHANGELOG.md,
# docs/changelog.md and site/docs/changelog.*), and so is the generated site/
# tree, which the lead rebuilds from docs/. It needs no modules, no network
# and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-buildah-pin: $message")
  $script:status = 1
}

$files = @(git -C $Root ls-files | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) {
  Fail "git ls-files failed in $Root"
  exit 1
}

# A reference is the image name, a colon and the tag characters that follow.
# An acceptable tag ends in -immutable@sha256:<hex>.
$refRe = 'quay\.io/buildah/stable:([A-Za-z0-9._~:+@-]*)'
$okTag = '-immutable@sha256:[0-9a-fA-F]+$'

foreach ($rel in $files) {
  # Changelog history may quote the old tag; the generated site/ tree is
  # rebuilt from docs/, so neither is checked.
  if ($rel -eq 'CHANGELOG.md' -or $rel -eq 'docs/changelog.md' -or $rel -like 'site/*') { continue }
  $full = Join-Path $Root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
  if (-not (Test-Path -LiteralPath $full)) { continue }
  $bytes = [System.IO.File]::ReadAllBytes($full)
  # Skip binary files (images, fonts); the check is about text.
  if ($bytes -contains 0) { continue }
  $lines = [System.Text.Encoding]::UTF8.GetString($bytes) -split '\r?\n'
  for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($m in [regex]::Matches($lines[$i], $refRe)) {
      if ($m.Groups[1].Value -notmatch $okTag) {
        Fail "${rel}:$($i + 1): buildah tag is not an -immutable digest pin: $($m.Value)"
      }
    }
  }
}

if ($status -eq 0) {
  Write-Output "check-buildah-pin: ok"
}
exit $status
