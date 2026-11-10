# check-contract-fails.ps1: does the contract guard still fail a drifted
# template?
#
# tests/check-contract.ps1 marks BEST_PRACTICES 1.4 (inside a major version,
# an input keeps its name, type and default, and a job keeps its name)
# Checked. Nothing proves the guard fails when a template drifts, so this
# script copies the guard, the templates and the contract into a temp tree,
# breaks one thing and requires the guard to fail:
#
#   clean  an unmutated copy exits 0
#   M1     the composer-audit abandoned input's default changes from fail
#          to report; the guard must exit non-zero and name the component
#          and the input
#   M2     the abandoned input key is renamed abandonment in the spec;
#          the guard must exit non-zero and name both names
#
# The guard derives its root from its own location, so the copied guard
# inspects the temp tree. The tree is rebuilt between cases, and a mutation
# that changes nothing fails the script. One ok: or FAIL: line goes to
# stdout per case; the guard's log is printed only for a case that went
# wrong. The guard parses the templates with yq in Docker, so this script
# needs Docker and the mikefarah/yq image, like the guard. Its twin,
# check-contract-fails.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

function Fail([string]$message) {
  [Console]::Error.WriteLine("FAIL: $message")
  exit 1
}

$Guard = Join-Path $Root "tests/check-contract.ps1"
if (-not (Test-Path -LiteralPath $Guard)) {
  Fail "guard missing: tests/check-contract.ps1"
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "templates"))) {
  Fail "templates/ missing"
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "contract/inputs.json"))) {
  Fail "contract/inputs.json missing"
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Fail "docker is required: the guard parses the templates with yq in Docker"
}
# The guard ends with exit, so it runs in its own pwsh process.
$Pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $Pwsh) { $Pwsh = Join-Path $PSHome "pwsh.exe" }
if (-not (Test-Path -LiteralPath $Pwsh)) {
  Fail "pwsh is required: the guard runs in its own PowerShell 7 process"
}

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("check-contract-fails-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$Tree = Join-Path $Tmp "tree"

# Build-Tree: a fresh copy of the guard, the templates and the contract.
function Build-Tree() {
  if (Test-Path -LiteralPath $Tree) { Remove-Item -LiteralPath $Tree -Recurse -Force }
  New-Item -ItemType Directory -Path (Join-Path $Tree "tests") | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $Tree "contract") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Root "templates") -Destination (Join-Path $Tree "templates") -Recurse
  Copy-Item -LiteralPath (Join-Path $Root "contract/inputs.json") -Destination (Join-Path $Tree "contract/inputs.json")
  Copy-Item -LiteralPath $Guard -Destination (Join-Path $Tree "tests/check-contract.ps1")
}

# Invoke-Guard: run the copied guard, keep its log and exit code. The
# redirect files must not exist when Start-Process starts, so each run
# removes the previous case's log first.
function Invoke-Guard() {
  $stdout = Join-Path $Tmp "guard.out"
  $stderr = Join-Path $Tmp "guard.err"
  Remove-Item -LiteralPath $stdout -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stderr -ErrorAction SilentlyContinue
  $process = Start-Process -FilePath $Pwsh -ArgumentList @("-NoProfile", "-File", (Join-Path $Tree "tests/check-contract.ps1")) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
  $script:GuardExit = $process.ExitCode
  $log = [IO.File]::ReadAllText($stdout)
  $errors = [IO.File]::ReadAllText($stderr)
  if ($errors.Trim() -ne "") { $log += $errors }
  $script:GuardLog = $log
}

# Print-Log: the guard's log, prefixed, for a case that went wrong.
function Print-Log() {
  foreach ($line in $script:GuardLog.Split("`n")) {
    [Console]::Error.WriteLine("  | $($line.TrimEnd("`r"))")
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
  if ($script:GuardLog -notlike "*contract: all components match contract/inputs.json*") {
    Print-Log
    Fail "clean: the guard did not confirm the contract"
  }
  Write-Output "ok: clean: the guard passes an unmutated copy"

  # M1: the abandoned input's default changes from fail to report.
  Build-Tree
  $tpl = Join-Path $Tree "templates/composer-audit/template.yml"
  $lines = [IO.File]::ReadAllLines($tpl)
  $oldLine = '      default: fail'
  if (-not ($lines -ccontains $oldLine)) { Fail "mutation did not apply" }
  $lines = @($lines | ForEach-Object { if ($_ -ceq $oldLine) { '      default: report' } else { $_ } })
  Write-Lf $tpl $lines
  Invoke-Guard
  if ($script:GuardExit -eq 0) { Fail "M1: the guard passed a changed abandoned default" }
  if ($script:GuardLog -notlike "*composer-audit*") { Print-Log; Fail "M1: the guard did not name the component" }
  if ($script:GuardLog -notlike "*abandoned*") { Print-Log; Fail "M1: the guard did not name the input" }
  Write-Output "ok: M1: the guard fails a changed abandoned default"

  # M2: the abandoned input key is renamed abandonment in the spec.
  Build-Tree
  $lines = [IO.File]::ReadAllLines($tpl)
  $oldLine = '    abandoned:'
  if (-not ($lines -ccontains $oldLine)) { Fail "mutation did not apply" }
  $lines = @($lines | ForEach-Object { if ($_ -ceq $oldLine) { '    abandonment:' } else { $_ } })
  Write-Lf $tpl $lines
  Invoke-Guard
  if ($script:GuardExit -eq 0) { Fail "M2: the guard passed a renamed abandoned input" }
  if ($script:GuardLog -notlike "*abandoned*") { Print-Log; Fail "M2: the guard did not name the old name" }
  if ($script:GuardLog -notlike "*abandonment*") { Print-Log; Fail "M2: the guard did not name the new name" }
  Write-Output "ok: M2: the guard fails a renamed abandoned input"
} finally {
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "check-contract-fails: ok"
exit 0
