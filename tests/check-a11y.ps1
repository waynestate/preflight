# check-a11y.ps1: does the a11y component's checker still pass a clean site
# and fail a bad one?
#
# Runs scripts/a11y.ps1, which runs templates/a11y/check.mjs with the image
# and versions pinned in templates/a11y/template.yml, against the fixtures in
# tests/a11y-fixtures with the component's default tags (WCAG 2.1 AA), light
# and dark, 320 px and 1280 px:
#
#   good, every page by glob       exit 0: 2 pages x 4 modes, no failure
#   bad, every page by glob        exit 1: the report names html-has-lang,
#                                  image-alt, label, color-contrast and
#                                  preflight-reflow (at 320 px only), and
#                                  dark.html fails in dark mode only
#   good, a page that is missing   exit 1: HTTP 404
#   good, a glob matching nothing  exit 2: a configuration error
#   good, the root page ""         exit 0: "" is the site root, 1 page x 4 modes
#   good, the root page "/"        exit 0: "/" is the site root, 1 page x 4 modes
#
# One result line per case goes to stdout; the checker's own output is kept
# in a temp folder and printed only for a case that went wrong. Windows
# PowerShell 5.1 and PowerShell 7. Needs Docker. Its twin, check-a11y.sh,
# does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("docker is required")
  exit 1
}

$Tags = '["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]'
$Gate = Join-Path $Root "scripts/a11y.ps1"
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("check-a11y-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-a11y: $message")
  $script:status = 1
}

# Run the gate in this process, keep its log and reports, return its exit code.
function Invoke-Gate([string]$case, [hashtable]$gateArgs) {
  $report = Join-Path $Tmp $case
  New-Item -ItemType Directory -Force -Path $report | Out-Null
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $log = & $Gate -Tags $Tags -Report $report @gateArgs *>&1 | Out-String
  } finally {
    $ErrorActionPreference = $previous
    Set-Location -LiteralPath $Root
  }
  [IO.File]::WriteAllText((Join-Path $Tmp "$case.log"), $log)
  return $LASTEXITCODE
}

function Test-Exit([string]$case, [int]$want, [int]$got) {
  if ($got -eq $want) {
    Write-Output "${case}: exit $got (expected)"
  } else {
    Fail "${case}: exit $got, expected $want"
    Get-Content -LiteralPath (Join-Path $Tmp "$case.log") | ForEach-Object { [Console]::Error.WriteLine("  | $_") }
  }
}

function Read-Report([string]$case, [string]$file) {
  $path = Join-Path (Join-Path $Tmp $case) $file
  if (Test-Path -LiteralPath $path) { return [IO.File]::ReadAllText($path) }
  return ""
}

# The JUnit failure line that follows a test case, or "" when it passed.
function Get-CaseFailure([string]$junit, [string]$name) {
  $lines = $junit -split "`n"
  for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    if ($lines[$i].Contains("name=""$name""")) {
      if ($lines[$i + 1].Contains("<failure")) { return $lines[$i + 1] }
      return ""
    }
  }
  return ""
}

try {
  # good: every page by glob, clean.
  $code = Invoke-Gate "good" @{ Site = "tests/a11y-fixtures/good" }
  Test-Exit "good" 0 $code
  if (-not (Read-Report "good" "gl-a11y-junit.xml").Contains('tests="8" failures="0"')) {
    Fail "good: the JUnit report does not show 8 checks and 0 failures"
  }

  # bad: every page by glob, each known flaw named.
  $code = Invoke-Gate "bad" @{ Site = "tests/a11y-fixtures/bad" }
  Test-Exit "bad" 1 $code
  $json = Read-Report "bad" "gl-a11y-report.json"
  $junit = Read-Report "bad" "gl-a11y-junit.xml"
  foreach ($rule in @("html-has-lang", "image-alt", "label", "color-contrast", "preflight-reflow")) {
    if (-not $json.Contains("""id"": ""$rule""")) { Fail "bad: the report does not name $rule" }
  }
  if (-not (Get-CaseFailure $junit "index.html light 320px").Contains("preflight-reflow")) {
    Fail "bad: index.html at 320 px is not reported for reflow"
  }
  if ((Get-CaseFailure $junit "index.html light 1280px").Contains("preflight-reflow")) {
    Fail "bad: reflow is reported at 1280 px, where it does not apply"
  }
  foreach ($mode in @("light 320px", "light 1280px")) {
    if (Get-CaseFailure $junit "dark.html $mode") { Fail "bad: dark.html fails in $mode, where it is clean" }
  }
  foreach ($mode in @("dark 320px", "dark 1280px")) {
    if (-not (Get-CaseFailure $junit "dark.html $mode")) { Fail "bad: dark.html passes in $mode, where its contrast fails" }
  }
  Write-Output "bad: rules and modes checked"

  # missing: a literal page that is not there fails the check, not the tool.
  $code = Invoke-Gate "missing" @{ Site = "tests/a11y-fixtures/good"; Pages = '["missing.html"]' }
  Test-Exit "missing" 1 $code
  if (-not ([IO.File]::ReadAllText((Join-Path $Tmp "missing.log"))).Contains("HTTP 404")) {
    Fail "missing: the log does not say HTTP 404"
  }

  # nomatch: a glob that matches nothing is a configuration error.
  $code = Invoke-Gate "nomatch" @{ Site = "tests/a11y-fixtures/good"; Pages = '["nope/**/*.html"]' }
  Test-Exit "nomatch" 2 $code

  # root: the empty string is the site root, reported as "/".
  $code = Invoke-Gate "root" @{ Site = "tests/a11y-fixtures/good"; Pages = '[""]' }
  Test-Exit "root" 0 $code
  if (-not (Read-Report "root" "gl-a11y-junit.xml").Contains('tests="4" failures="0"')) {
    Fail "root: the JUnit report does not show 4 checks and 0 failures"
  }
  if (-not (Read-Report "root" "gl-a11y-junit.xml").Contains('name="/ light 320px"')) {
    Fail "root: the JUnit report does not name the root /"
  }

  # rootslash: "/" is the other spelling of the site root.
  $code = Invoke-Gate "rootslash" @{ Site = "tests/a11y-fixtures/good"; Pages = '["/"]' }
  Test-Exit "rootslash" 0 $code
  if (-not (Read-Report "rootslash" "gl-a11y-junit.xml").Contains('tests="4" failures="0"')) {
    Fail "rootslash: the JUnit report does not show 4 checks and 0 failures"
  }
  if (-not (Read-Report "rootslash" "gl-a11y-junit.xml").Contains('name="/ light 320px"')) {
    Fail "rootslash: the JUnit report does not name the root /"
  }
} finally {
  [IO.Directory]::Delete($Tmp, $true)
}

if ($status -eq 0) {
  Write-Output "check-a11y: ok"
}
exit $status
