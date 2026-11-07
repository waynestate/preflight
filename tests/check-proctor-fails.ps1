# check-proctor-fails.ps1: does the proctor component still fail a bad app
# and pass a clean one?
#
# The proctor component passes the tool's exit code through: the job runs
# the proctor_command with a plain redirect to gl-code-quality-report.json,
# so a non-zero exit fails the job and the JSON is only the Code Quality
# report. This script checks that the template keeps that plain redirect
# (no tee, no pipe), then runs the two fixtures with sh (Git Bash):
#
#   tests/fixture-app    exit 0, prints [] (the clean case)
#   tests/proctor-fails  non-zero exit, prints one blocker finding
#                        (the must-fail case)
#
# One result line per case goes to stdout; a fixture's output is printed
# only for a case that went wrong. Needs no Docker and no Composer, but it
# needs sh: it looks for sh on the PATH and falls back to the standard Git
# for Windows layout. Its twin, check-proctor-fails.sh, does the same on
# Linux and macOS.

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
  [Console]::Error.WriteLine("check-proctor-fails: sh (Git Bash) is required: put Git for Windows' bin folder on the PATH")
  exit 1
}

$Template = Join-Path $Root "templates/proctor/template.yml"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-proctor-fails: $message")
  $script:status = 1
}

function Test-Fixture([string]$relative) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root $relative))) {
    Fail "fixture missing: $relative"
  }
}

# Run the fixture's fake proctor with sh, keep its output and exit code.
function Invoke-Fixture([string]$dir) {
  Push-Location -LiteralPath (Join-Path $Root $dir)
  try {
    $script:FixtureLog = (& $Sh "bin/proctor" "check" "--format=codequality" 2>&1) -join "`n"
  } finally {
    Pop-Location
  }
  $script:FixtureExit = $LASTEXITCODE
}

function Show-Log() {
  foreach ($line in $script:FixtureLog.Split("`n")) {
    [Console]::Error.WriteLine("  | $line")
  }
}

Test-Fixture "tests/fixture-app/bin/proctor"
Test-Fixture "tests/proctor-fails/bin/proctor"

# (a) the job keeps a plain redirect of the command to the report, so the
# exit code is the job result: no tee, no pipe.
if (Test-Path -LiteralPath $Template) {
  $want = '    - $[[ inputs.proctor_command ]] > "$CI_PROJECT_DIR/gl-code-quality-report.json"'
  if (-not ([IO.File]::ReadAllLines($Template) -contains $want)) {
    Fail "proctor job does not redirect the command plainly to gl-code-quality-report.json (no tee, no pipe)"
  }
} else {
  Fail "template missing: templates/proctor/template.yml"
}

# clean: the stub prints an empty report and exits 0.
Invoke-Fixture "tests/fixture-app"
$ok = $true
if ($script:FixtureExit -ne 0) { Fail "proctor clean: exit $($script:FixtureExit), expected 0"; $ok = $false }
if ($script:FixtureLog.Trim() -ne "[]") { Fail "proctor clean: the output is not []"; $ok = $false }
if ($ok) {
  Write-Output "proctor clean: exit $($script:FixtureExit) (expected)"
} else {
  Show-Log
}

# must-fail: the fixture prints one blocker finding and exits non-zero.
Invoke-Fixture "tests/proctor-fails"
$ok = $true
if ($script:FixtureExit -eq 0) { Fail "proctor must-fail: exit 0, expected non-zero"; $ok = $false }
if (-not $script:FixtureLog.Contains('"severity":"blocker"')) { Fail "proctor must-fail: the output does not carry the blocker finding"; $ok = $false }
if ($ok) {
  Write-Output "proctor must-fail: exit $($script:FixtureExit) (expected)"
} else {
  Show-Log
}

if ($status -eq 0) {
  Write-Output "check-proctor-fails: ok"
}
exit $status
