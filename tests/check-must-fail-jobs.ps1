# check-must-fail-jobs.ps1: does every must-fail check have a job in the
# repository's own pipeline?
#
# Preflight's own .gitlab-ci.yml carries a job for every
# tests/check-*-fails.sh script: either a must-fail-* job that runs the
# script directly, or a line in the contract job's script list. This check
# fails when the wiring breaks in either direction:
#
#   * a script tests/check-*-fails.sh exists but its file name is not
#     mentioned anywhere in .gitlab-ci.yml, so the check never runs; or
#   * a top-level must-fail-* job names a tests/check-*.sh file in its
#     script that does not exist, so the job fails for the wrong reason.
#
# It reads .gitlab-ci.yml with plain string matching, so it needs no
# modules, no yq and no Docker. Point it at a copy with $env:CI_FILE.
# With --self-test it copies .gitlab-ci.yml to a temp file with every line
# that mentions check-composer-ci-fails removed, runs itself against that
# copy, and passes only when that run fails and names
# check-composer-ci-fails.sh.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$CiPath = if ($env:CI_FILE) { $env:CI_FILE } else { Join-Path $Root ".gitlab-ci.yml" }

function Write-Failure([string]$msg) {
  [Console]::Error.WriteLine("check-must-fail-jobs: $msg")
}

function Test-PipelineFile([string]$Path) {
  $msgs = @()
  if (-not (Test-Path -LiteralPath $Path)) {
    return @(".gitlab-ci.yml is missing at $Path")
  }
  $lines = @(Get-Content -LiteralPath $Path)

  # Case A: every tests/check-*-fails.sh script must be mentioned
  # somewhere in the CI file.
  $checks = @(Get-ChildItem -LiteralPath (Join-Path $Root "tests") -Filter "check-*-fails.sh" -File -ErrorAction SilentlyContinue)
  foreach ($c in $checks) {
    if (@($lines | Where-Object { $_ -like "*$($c.Name)*" }).Count -eq 0) {
      $msgs += "tests/$($c.Name) exists but $Path never mentions it"
    }
  }

  # Case B: every top-level must-fail-* job's script lines must name test
  # scripts that exist.
  $inJob = $false
  $inScript = $false
  $scriptLines = @()
  foreach ($line in $lines) {
    if ($line -match '^must-fail-[A-Za-z0-9_-]*:[ \t]*$') {
      $inJob = $true
      $inScript = $false
      continue
    }
    if ($inJob -and $line -match '^[^ ]') {
      $inJob = $false
      $inScript = $false
      continue
    }
    if ($inJob -and $line -match '^  script:[ \t]*$') {
      $inScript = $true
      continue
    }
    if ($inJob -and $inScript -and $line -match '^  [A-Za-z_]') {
      $inScript = $false
    }
    if ($inJob -and $inScript) {
      $scriptLines += $line
    }
  }
  $refs = @()
  foreach ($sl in $scriptLines) {
    if ($sl -match 'tests/check-[A-Za-z0-9_.\-]+\.sh') {
      $refs += $Matches[0]
    }
  }
  foreach ($r in @($refs | Sort-Object -Unique)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $r))) {
      $msgs += "must-fail job names $r but that file does not exist"
    }
  }
  return $msgs
}

# Self-test: copy the CI file with every line that mentions
# check-composer-ci-fails removed, run this script against that copy, and
# pass only when that run fails and names check-composer-ci-fails.sh.
if ($args.Count -gt 0 -and $args[0] -eq '--self-test') {
  $status = 0
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("check-must-fail-jobs-" + [System.Guid]::NewGuid().ToString("N"))
  $stripped = @((Get-Content -LiteralPath $CiPath) | Where-Object { $_ -notlike '*check-composer-ci-fails*' })
  Set-Content -LiteralPath $tmp -Value $stripped
  try {
    $prev = $env:CI_FILE
    $env:CI_FILE = $tmp
    $out = ""
    $code = 0
    try {
      $out = & "$PSCommandPath" 2>&1 | Out-String
      $code = $LASTEXITCODE
    } finally {
      if ($null -eq $prev) { Remove-Item Env:\CI_FILE -ErrorAction SilentlyContinue } else { $env:CI_FILE = $prev }
    }
    if ($code -ne 0 -and $out -like '*check-composer-ci-fails.sh*') {
      Write-Output "check-must-fail-jobs: self-test ok (stripped run failed and named check-composer-ci-fails.sh)"
    } else {
      Write-Failure "self-test: the stripped run did not fail as expected (exit $code); output:"
      [Console]::Error.WriteLine(($out -split "`n" | ForEach-Object { "  | $_" }) -join "`n")
      $status = 1
    }
  } finally {
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
  }
  exit $status
}

$failures = @(Test-PipelineFile $CiPath)
if ($failures.Count -gt 0) {
  foreach ($f in $failures) { Write-Failure $f }
  exit 1
}
Write-Output "check-must-fail-jobs: ok"
exit 0
