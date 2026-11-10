# check-php-matrix-fails.ps1: does the PHP matrix guard still fail a broken
# template?
#
# tests/check-php-matrix.sh marks BEST_PRACTICES 6.3 Checked: php-test
# keeps its parallel: matrix wiring (one job per PHP version) and the
# array-typed php_versions input behind it. Nothing proves the guard fails
# when the template breaks, so this script copies the guard and templates/
# into a temp tree, breaks one thing and requires the guard to fail:
#
#   clean  an unmutated copy exits 0
#   A      the parallel: block's three lines are deleted; the guard must
#          exit non-zero
#   B      php_versions' type: array becomes type: string; the guard must
#          exit non-zero
#
# The guard derives its root from its own location, so the copied guard
# inspects the temp tree. The tree is rebuilt between cases, and a mutation
# that changes nothing fails the script. One ok: or FAIL: line goes to
# stdout per case; the guard's log is printed only for a case that went
# wrong. Needs no Docker, but it needs sh: it looks for sh on the PATH and
# falls back to the standard Git for Windows layout. Its twin,
# check-php-matrix-fails.sh, does the same on Linux and macOS.

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
  [Console]::Error.WriteLine("check-php-matrix-fails: sh (Git Bash) is required: put Git for Windows' bin folder on the PATH")
  exit 1
}

$Guard = Join-Path $Root "tests/check-php-matrix.sh"
if (-not (Test-Path -LiteralPath $Guard)) {
  [Console]::Error.WriteLine("FAIL: guard missing: tests/check-php-matrix.sh")
  exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "templates"))) {
  [Console]::Error.WriteLine("FAIL: templates/ missing")
  exit 1
}

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("check-php-matrix-fails-" + [Guid]::NewGuid().ToString("N"))
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
  Copy-Item -LiteralPath $Guard -Destination (Join-Path $Tree "tests/check-php-matrix.sh")
}

# Invoke-Guard: run the copied guard, keep its log and exit code.
function Invoke-Guard() {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $script:GuardLog = (& $Sh (ConvertTo-ShPath (Join-Path $Tree "tests/check-php-matrix.sh")) 2>&1 | ForEach-Object { "$_" }) -join "`n"
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

  # A: the parallel: block's three lines are deleted.
  Build-Tree
  $tpl = Join-Path $Tree "templates/php-test/template.yml"
  $lines = [IO.File]::ReadAllLines($tpl)
  $targets = @('  parallel:', '    matrix:', '      - PHP_VERSION: $[[ inputs.php_versions ]]')
  if (@($lines | Where-Object { $targets -ccontains $_ }).Count -ne 3) { Fail "mutation did not apply" }
  $lines = @($lines | Where-Object { -not ($targets -ccontains $_) })
  Write-Lf $tpl $lines
  Invoke-Guard
  if ($script:GuardExit -eq 0) { Fail "A: the guard passed a template without the parallel: block" }
  Write-Output "ok: A: the guard fails a template without the parallel: block"

  # B: php_versions' type: array becomes type: string.
  Build-Tree
  $lines = [IO.File]::ReadAllLines($tpl)
  $oldLine = '      type: array'
  if (-not ($lines -ccontains $oldLine)) { Fail "mutation did not apply" }
  $lines = @($lines | ForEach-Object { if ($_ -ceq $oldLine) { '      type: string' } else { $_ } })
  Write-Lf $tpl $lines
  Invoke-Guard
  if ($script:GuardExit -eq 0) { Fail "B: the guard passed a php_versions input that is not type: array" }
  Write-Output "ok: B: the guard fails a php_versions input that is not type: array"
} finally {
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "check-php-matrix-fails: ok"
exit 0
