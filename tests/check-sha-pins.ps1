# check-sha-pins.ps1: do the published examples pin Preflight by commit SHA?
#
# A tag can move, a SHA cannot, so every example in the README, the front
# page and examples/ pins each component and the GitHub workflow at the full
# commit SHA of the release tag, with the tag kept in a trailing comment.
# This script greps those files for a component or workflow ref whose version
# starts with a digit but is not a full 40-character SHA, so it needs no
# modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-sha-pins: $message")
  $script:status = 1
}

# A ref is bare when its version starts with a digit and is not a full
# 40-character SHA: preflight/<component>@0.1.1 or php-package.yml@0.1.1.
$bare = '(preflight/[a-z-]*|php-package\.yml)@[0-9]'
$sha = '(preflight/[a-z-]*|php-package\.yml)@[0-9a-f]{40}'

$files = @(
  (Join-Path $Root "README.md"),
  (Join-Path $Root "site\index.md")
)
$files += Get-ChildItem -LiteralPath (Join-Path $Root "examples") -Recurse -File | ForEach-Object { $_.FullName }

foreach ($f in $files) {
  $rel = $f.Substring($Root.Length + 1)
  if (-not (Test-Path -LiteralPath $f)) {
    Fail "$rel is missing"
    continue
  }
  $lines = @(Get-Content -LiteralPath $f)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if (($lines[$i] -match $bare) -and ($lines[$i] -notmatch $sha)) {
      Fail "${rel}:$($i + 1): $($lines[$i])"
    }
  }
}

if ($status -eq 0) {
  Write-Output "check-sha-pins: ok"
}
exit $status
