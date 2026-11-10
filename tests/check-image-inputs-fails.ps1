# check-image-inputs-fails.ps1: does the image-input guard still fail a
# broken template?
#
# tests/check-image-inputs.sh marks BEST_PRACTICES 2.10 (every job image is
# an input) and 4.10 (a default php: tag names the Debian release) Checked.
# Nothing proves the guard fails when a template breaks, so this script
# copies the guard and templates/ into a temp tree, breaks one thing and
# requires the guard to fail:
#
#   clean  an unmutated copy exits 0
#   A      the php-test base job's image line becomes the hard-coded
#          php:8.4-cli-trixie; the guard must exit non-zero
#   B      the image input's default loses its Debian release,
#          php:${PHP_VERSION}-cli; the guard must exit non-zero
#
# The guard derives its root from its own location, so the copied guard
# inspects the temp tree. The tree is rebuilt between cases, and a mutation
# that changes nothing fails the script. One ok: or FAIL: line goes to
# stdout per case; the guard's log is printed only for a case that went
# wrong. Needs no Docker, but it needs sh: it looks for sh on the PATH and
# falls back to the standard Git for Windows layout. Its twin,
# check-image-inputs-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

# Find sh: the PATH first, then the standard Git for Windows layout,
# resolved through git when it is on the PATH.
function Find-Sh() {
  $command = Get-Command sh -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $candidate = Join-Path (Split-Path -Parent (Split-Path -Parent $git.Source)) "bin\sh.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  foreach ($install in @("C:\Program Files\Git", "C:\Program Files (x86)\Git")) {
    $candidate = Join-Path $install "bin\sh.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  return $null
}

$Sh = Find-Sh
if (-not $Sh) {
  [Console]::Error.WriteLine("check-image-inputs-fails: sh (Git Bash) is required: put Git for Windows' bin folder on the PATH")
  exit 1
}

$Guard = Join-Path $Root "tests/check-image-inputs.sh"
if (-not (Test-Path -LiteralPath $Guard)) {
  [Console]::Error.WriteLine("FAIL: guard missing: tests/check-image-inputs.sh")
  exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "templates"))) {
  [Console]::Error.WriteLine("FAIL: templates/ missing")
  exit 1
}

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("check-image-inputs-fails-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$Tree = Join-Path $Tmp "tree"

# Git Bash reads C:/ paths, so convert before handing them to sh.
function ConvertTo-ShPath([string]$path) { return $path.Replace('\', '/') }

function Fail([string]$message) {
  [Console]::Error.WriteLine("FAIL: $message")
  exit 1
}

# Build-Tree: a fresh copy of the guard and the templates.
function Build-Tree() {
  if (Test-Path -LiteralPath $Tree) { Remove-Item -LiteralPath $Tree -Recurse -Force }
  New-Item -ItemType Directory -Path (Join-Path $Tree "tests") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Root "templates") -Destination (Join-Path $Tree "templates") -Recurse
  Copy-Item -LiteralPath $Guard -Destination (Join-Path $Tree "tests/check-image-inputs.sh")
}

# Invoke-Guard: run the copied guard, keep its log and exit code.
function Invoke-Guard() {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $script:GuardLog = (& $Sh (ConvertTo-ShPath (Join-Path $Tree "tests/check-image-inputs.sh")) 2>&1 | ForEach-Object { "$_" }) -join "`n"
  $script:GuardExit = $LASTEXITCODE
  $ErrorActionPreference = $previous
}

# Print-Log: the guard's log, prefixed, for a case that went wrong.
function Print-Log() {
  foreach ($line in $script:GuardLog.Split("`n")) {
    [Console]::Error.WriteLine("  | $line")
  }
}

# Write-Lf: write the lines back with LF endings, like the checkout.
function Write-Lf([string]$path, [string[]]$lines) {
  [IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
}

try {
  # clean: the guard passes an unmutated copy.
  Build-Tree
  Invoke-Guard
  if ($script:GuardExit -ne 0) {
    Print-Log
    Fail "clean: the guard failed an unmutated copy"
  }
  Write-Output "ok: clean: the guard passes an unmutated copy"

  # A: the base job's image line becomes a hard-coded image.
  Build-Tree
  $tpl = Join-Path $Tree "templates/php-test/template.yml"
  $lines = [IO.File]::ReadAllLines($tpl)
  $oldLine = '  image: $[[ inputs.image_prefix ]]/$[[ inputs.image ]]'
  if (-not ($lines -ccontains $oldLine)) { Fail "mutation did not apply" }
  $lines = @($lines | ForEach-Object { if ($_ -ceq $oldLine) { '  image: php:8.4-cli-trixie' } else { $_ } })
  Write-Lf $tpl $lines
  Invoke-Guard
  if ($script:GuardExit -eq 0) { Fail "A: the guard passed a hard-coded php-test image" }
  Write-Output "ok: A: the guard fails a hard-coded php-test image"

  # B: the image input's default loses its Debian release.
  Build-Tree
  $lines = [IO.File]::ReadAllLines($tpl)
  $oldLine = '      default: php:${PHP_VERSION}-cli-trixie'
  if (-not ($lines -ccontains $oldLine)) { Fail "mutation did not apply" }
  $lines = @($lines | ForEach-Object { if ($_ -ceq $oldLine) { '      default: php:${PHP_VERSION}-cli' } else { $_ } })
  Write-Lf $tpl $lines
  Invoke-Guard
  if ($script:GuardExit -eq 0) { Fail "B: the guard passed a default tag without the Debian release" }
  Write-Output "ok: B: the guard fails a default tag without the Debian release"
} finally {
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "check-image-inputs-fails: ok"
exit 0
