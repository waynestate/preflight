# check-cache-fails.ps1: do the cache guards still fail a broken template?
#
# Three guards mark BEST_PRACTICES 4.8 Checked:
#
#   * tests/check-php-test-cache.sh: the php-test key stays fixed and keeps
#     the PHP version;
#   * tests/check-proctor-cache.sh: the proctor key stays preflight-proctor;
#   * tests/check-dependency-cache.sh: every cache block saves with
#     when: always.
#
# Nothing proves they fail when a template breaks, so this script copies
# the three guards and templates/ into a temp tree, breaks one thing and
# requires the named guard to fail:
#
#   clean  all three guards exit 0 on an unmutated copy
#   1      a files: [composer.lock] line after the php-test key
#          (php-test-cache guard)
#   2      the php-test key drops the PHP version (php-test-cache guard)
#   3      a files: [composer.lock] line after the proctor key
#          (proctor-cache guard)
#   4      the proctor key is renamed (proctor-cache guard)
#   5      the php-test cache block loses when: always (dependency-cache
#          guard)
#
# Each guard derives its root from its own location, so a copied guard
# inspects the temp tree. The tree is rebuilt between cases, and a mutation
# that changes nothing fails the script. One ok: or FAIL: line goes to
# stdout per case; the guard's log is printed only for a case that went
# wrong. Needs no Docker, but it needs sh: it looks for sh on the PATH and
# falls back to the standard Git for Windows layout. Its twin,
# check-cache-fails.sh, does the same on Linux and macOS.

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
  [Console]::Error.WriteLine("check-cache-fails: sh (Git Bash) is required: put Git for Windows' bin folder on the PATH")
  exit 1
}

foreach ($g in @("check-php-test-cache", "check-proctor-cache", "check-dependency-cache")) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root "tests/$g.sh"))) {
    [Console]::Error.WriteLine("FAIL: guard missing: tests/$g.sh")
    exit 1
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "templates"))) {
  [Console]::Error.WriteLine("FAIL: templates/ missing")
  exit 1
}

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("check-cache-fails-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$Tree = Join-Path $Tmp "tree"

# Git Bash reads C:/ paths, so convert before handing them to sh.
function ConvertTo-ShPath([string]$path) { return $path.Replace('\', '/') }

function Fail([string]$message) {
  [Console]::Error.WriteLine("FAIL: $message")
  exit 1
}

# Build-Tree: a fresh copy of the three guards and the templates.
function Build-Tree() {
  if (Test-Path -LiteralPath $Tree) { Remove-Item -LiteralPath $Tree -Recurse -Force }
  New-Item -ItemType Directory -Path (Join-Path $Tree "tests") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Root "templates") -Destination (Join-Path $Tree "templates") -Recurse
  foreach ($g in @("check-php-test-cache", "check-proctor-cache", "check-dependency-cache")) {
    Copy-Item -LiteralPath (Join-Path $Root "tests/$g.sh") -Destination (Join-Path $Tree "tests/$g.sh")
  }
}

# Invoke-Guard <name>: run the named copied guard, keep its log and exit code.
function Invoke-Guard([string]$name) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $script:GuardLog = (& $Sh (ConvertTo-ShPath (Join-Path $Tree "tests/$name")) 2>&1 | ForEach-Object { "$_" }) -join "`n"
  $script:GuardExit = $LASTEXITCODE
  $ErrorActionPreference = $previous
}

# Print-Log: the guard's log, prefixed, for a case that went wrong.
function Print-Log() {
  foreach ($line in $script:GuardLog.Split("`n")) {
    [Console]::Error.WriteLine("  | $line")
  }
}

try {
  # clean: all three guards pass an unmutated copy.
  Build-Tree
  foreach ($g in @("check-php-test-cache", "check-proctor-cache", "check-dependency-cache")) {
    Invoke-Guard "$g.sh"
    if ($script:GuardExit -ne 0) {
      Print-Log
      Fail "clean: $g failed an unmutated copy"
    }
  }
  Write-Output "ok: clean: all three guards pass an unmutated copy"

  # 1: the php-test key gains a lock-hash files: line.
  Build-Tree
  $tpl = Join-Path $Tree "templates/php-test/template.yml"
  $content = [IO.File]::ReadAllText($tpl)
  $oldLine = '    key: preflight-php-${PHP_VERSION}'
  if (-not $content.Contains($oldLine)) { Fail "mutation did not apply" }
  [IO.File]::WriteAllText($tpl, $content.Replace($oldLine, $oldLine + "`n    files: [composer.lock]"), (New-Object Text.UTF8Encoding $false))
  Invoke-Guard "check-php-test-cache.sh"
  if ($script:GuardExit -eq 0) { Fail "1: the php-test-cache guard passed a files: line in the key" }
  Write-Output "ok: 1: the php-test-cache guard fails a files: line in the key"

  # 2: the php-test key drops the PHP version.
  Build-Tree
  $content = [IO.File]::ReadAllText($tpl)
  $oldLine = '    key: preflight-php-${PHP_VERSION}'
  if (-not $content.Contains($oldLine)) { Fail "mutation did not apply" }
  [IO.File]::WriteAllText($tpl, $content.Replace($oldLine, '    key: preflight-php'), (New-Object Text.UTF8Encoding $false))
  Invoke-Guard "check-php-test-cache.sh"
  if ($script:GuardExit -eq 0) { Fail "2: the php-test-cache guard passed a key without the PHP version" }
  Write-Output "ok: 2: the php-test-cache guard fails a key without the PHP version"

  # 3: the proctor key gains a lock-hash files: line.
  Build-Tree
  $tpl = Join-Path $Tree "templates/proctor/template.yml"
  $content = [IO.File]::ReadAllText($tpl)
  $oldLine = '    key: preflight-proctor'
  if (-not $content.Contains($oldLine + "`n")) { Fail "mutation did not apply" }
  [IO.File]::WriteAllText($tpl, $content.Replace($oldLine + "`n", $oldLine + "`n    files: [composer.lock]`n"), (New-Object Text.UTF8Encoding $false))
  Invoke-Guard "check-proctor-cache.sh"
  if ($script:GuardExit -eq 0) { Fail "3: the proctor-cache guard passed a files: line in the key" }
  Write-Output "ok: 3: the proctor-cache guard fails a files: line in the key"

  # 4: the proctor key is renamed.
  Build-Tree
  $content = [IO.File]::ReadAllText($tpl)
  $oldLine = '    key: preflight-proctor'
  if (-not $content.Contains($oldLine + "`n")) { Fail "mutation did not apply" }
  [IO.File]::WriteAllText($tpl, $content.Replace($oldLine + "`n", '    key: preflight-proctor-old' + "`n"), (New-Object Text.UTF8Encoding $false))
  Invoke-Guard "check-proctor-cache.sh"
  if ($script:GuardExit -eq 0) { Fail "4: the proctor-cache guard passed a renamed key" }
  Write-Output "ok: 4: the proctor-cache guard fails a renamed key"

  # 5: the php-test cache block loses when: always.
  Build-Tree
  $tpl = Join-Path $Tree "templates/php-test/template.yml"
  $content = [IO.File]::ReadAllText($tpl)
  $oldLine = '    when: always  # a failed job still keeps every package that finished downloading'
  if (-not $content.Contains($oldLine)) { Fail "mutation did not apply" }
  $newContent = $content.Replace($oldLine + "`n", "")
  if ($newContent.Contains('when: always')) { Fail "mutation did not apply" }
  [IO.File]::WriteAllText($tpl, $newContent, (New-Object Text.UTF8Encoding $false))
  Invoke-Guard "check-dependency-cache.sh"
  if ($script:GuardExit -eq 0) { Fail "5: the dependency-cache guard passed a cache block without when: always" }
  Write-Output "ok: 5: the dependency-cache guard fails a cache block without when: always"
} finally {
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "check-cache-fails: ok"
exit 0
