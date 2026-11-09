# check-proctor-fails.ps1: does the proctor component still fail a bad app
# and pass a clean one, and keep proctor.json only when PROCTOR can write it?
#
# The proctor component passes the tool's exit code through: the job runs
# the proctor_command with a plain redirect to gl-code-quality-report.json,
# so a non-zero exit fails the job and the JSON is only the Code Quality
# report. When the app's PROCTOR has `check --record` (0.11.0 and later),
# a guard in the job adds --record "$CI_PROJECT_DIR/proctor.json", the JSON
# report Rollcall reads from the job's artifact. This script checks that
# the template keeps the plain redirect (no tee, no pipe), the guard, the
# variable the guard reads and the artifact block, then renders the
# template's own guard and command line (the command filled in per case)
# and runs them with sh -e (Git Bash), the way the runner does, on fake
# PROCTORs:
#
#   tests/fixture-app     0.10.0 or older (no --record)   exit 0, [], no proctor.json
#   tests/proctor-record  0.11.0 or later, clean          exit 0, [], proctor.json
#   tests/proctor-fails   0.11.0 or later, one blocker    non-zero, blocker, proctor.json
#   tests/proctor-record  a gate command                  no proctor.json
#   tests/proctor-record  a command with quotes           no proctor.json
#
# One result line per case goes to stdout; a case's log is printed only for
# a case that went wrong. Needs no Docker and no Composer, but it needs sh:
# it looks for sh on the PATH and falls back to the standard Git for
# Windows layout. Its twin, check-proctor-fails.sh, does the same on Linux
# and macOS.

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

if (-not (Test-Path -LiteralPath $Template)) {
  Fail "template missing: templates/proctor/template.yml"
  exit 1
}
foreach ($dir in @("tests/fixture-app", "tests/proctor-record", "tests/proctor-fails")) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root "$dir/bin/proctor"))) {
    Fail "fixture missing: $dir/bin/proctor"
  }
}
if ($status -ne 0) { exit 1 }

$Lines = [IO.File]::ReadAllLines($Template)

# The command line the job runs. Only the --record guard's ${...:+...} sits
# between the command and the plain redirect.
$CmdLine = '    - $[[ inputs.proctor_command ]] ${PREFLIGHT_PROCTOR_RECORD:+--record "$CI_PROJECT_DIR/proctor.json"} > "$CI_PROJECT_DIR/gl-code-quality-report.json"'
$Placeholder = '$[[ inputs.proctor_command ]]'

# (a) the job keeps a plain redirect of the command to the report, so the
# exit code is the job result: no tee, no pipe.
if (-not ($Lines -ccontains $CmdLine)) {
  Fail "proctor job does not run the command, plus the guarded --record, with a plain redirect to gl-code-quality-report.json (no tee, no pipe)"
}

# (b) the guard reads the command as text from a job variable.
if (-not ($Lines -ccontains '    PREFLIGHT_PROCTOR_COMMAND: $[[ inputs.proctor_command ]]')) {
  Fail "proctor job does not set PREFLIGHT_PROCTOR_COMMAND from the proctor_command input"
}

# (c) the artifact block: kept on failure too, for 30 days, with
# proctor.json next to the Code Quality report.
$block = @()
$inBlock = $false
foreach ($line in $Lines) {
  if ($line -cmatch '^  artifacts:\s*$') { $inBlock = $true; continue }
  if ($inBlock) {
    if ($line -cmatch '^  [^ ]' -or $line -cmatch '^[^ ]') { break }
    $block += $line
  }
}
foreach ($want in @('    when: always', '    expire_in: 30 days', '      - proctor.json', '      codequality: gl-code-quality-report.json')) {
  if (-not ($block -ccontains $want)) { Fail "proctor artifacts block lacks: $($want.Trim())" }
}

# (d) the guard: the block-scalar script item that sets
# PREFLIGHT_PROCTOR_RECORD, without its six-space indent.
$guard = $null
$buf = @()
$inBlock = $false
$found = $false
foreach ($line in $Lines) {
  if ($line -cmatch '^    - \|\s*$') {
    if ($found) { break }
    $inBlock = $true; $buf = @(); continue
  }
  if ($inBlock -and $line.StartsWith('      ')) {
    $text = $line.Substring(6)
    $buf += $text
    if ($text.StartsWith('PREFLIGHT_PROCTOR_RECORD=')) { $found = $true }
    continue
  }
  if ($inBlock) {
    $inBlock = $false
    if ($found) { break }
  }
}
if ($found) { $guard = ($buf -join "`n") + "`n" }
if (-not $guard) {
  Fail "no --record guard (a script block that sets PREFLIGHT_PROCTOR_RECORD) in the template"
  exit 1
}

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("check-proctor-fails-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Tmp | Out-Null

# Git Bash reads C:/ paths, and CI_PROJECT_DIR must not hold a backslash.
function ConvertTo-ShPath([string]$path) { return $path.Replace('\', '/') }

# Run one case: render the guard and the command line with the case's
# command, run them with sh -e from the fixture, CI_PROJECT_DIR set to a
# fresh temp dir. Sets $script:CaseExit and $script:CaseLog.
function Invoke-Case([string]$name, [string]$dir, [string]$cmd) {
  $project = Join-Path $Tmp $name
  New-Item -ItemType Directory -Path $project | Out-Null
  $line = $CmdLine.Substring(6).Replace($Placeholder, $cmd)
  $scriptFile = Join-Path $Tmp "$name.sh"
  [IO.File]::WriteAllText($scriptFile, $guard + $line + "`n", (New-Object Text.UTF8Encoding $false))
  $env:PREFLIGHT_PROCTOR_COMMAND = $cmd
  $env:CI_PROJECT_DIR = ConvertTo-ShPath $project
  Push-Location -LiteralPath (Join-Path $Root $dir)
  try {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $script:CaseLog = (& $Sh -e (ConvertTo-ShPath $scriptFile) 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $script:CaseExit = $LASTEXITCODE
    $ErrorActionPreference = $previous
  } finally {
    Pop-Location
    Remove-Item Env:PREFLIGHT_PROCTOR_COMMAND -ErrorAction SilentlyContinue
    Remove-Item Env:CI_PROJECT_DIR -ErrorAction SilentlyContinue
  }
}

# One case. The report must hold the pattern (fixed text) when one is given.
function Test-Case([string]$name, [string]$dir, [string]$cmd, [bool]$wantZero, [bool]$wantRecord, [string]$pattern) {
  Invoke-Case $name $dir $cmd
  $project = Join-Path $Tmp $name
  $record = Join-Path $project "proctor.json"
  $report = Join-Path $project "gl-code-quality-report.json"
  $ok = $true
  if ($wantZero -and $script:CaseExit -ne 0) { Fail "${name}: exit $($script:CaseExit), expected 0"; $ok = $false }
  if (-not $wantZero -and $script:CaseExit -eq 0) { Fail "${name}: exit 0, expected non-zero"; $ok = $false }
  if ($wantRecord) {
    if (-not (Test-Path -LiteralPath $record) -or (Get-Item -LiteralPath $record).Length -eq 0) {
      Fail "${name}: proctor.json was not written"; $ok = $false
    } elseif (-not ([IO.File]::ReadAllText($record).Contains('"tool":"proctor"'))) {
      Fail "${name}: proctor.json is not the stub's JSON report"; $ok = $false
    }
  } elseif (Test-Path -LiteralPath $record) {
    Fail "${name}: proctor.json was written, expected none"; $ok = $false
  }
  if ($pattern) {
    $text = if (Test-Path -LiteralPath $report) { [IO.File]::ReadAllText($report) } else { "" }
    if (-not $text.Contains($pattern)) { Fail "${name}: the Code Quality report does not hold $pattern"; $ok = $false }
  }
  if ($ok) {
    $kept = if (Test-Path -LiteralPath $record) { "proctor.json kept" } else { "no proctor.json" }
    Write-Output "proctor ${name}: exit $($script:CaseExit), $kept (expected)"
  } else {
    foreach ($logLine in $script:CaseLog.Split("`n")) {
      [Console]::Error.WriteLine("  | $logLine")
    }
  }
}

$Default = 'sh bin/proctor check --format=codequality'

try {
  Test-Case "clean-old" "tests/fixture-app" $Default $true $false '[]'
  Test-Case "clean-new" "tests/proctor-record" $Default $true $true '[]'
  Test-Case "must-fail" "tests/proctor-fails" $Default $false $true '"severity":"blocker"'
  Test-Case "gate" "tests/proctor-record" 'sh bin/proctor gate --format=json' $true $false ''
  Test-Case "quoted" "tests/proctor-record" 'sh bin/proctor check --format=codequality --path="."' $true $false '[]'
} finally {
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($status -eq 0) {
  Write-Output "check-proctor-fails: ok"
}
exit $status
