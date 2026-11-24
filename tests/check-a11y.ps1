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
#   routes, the unit test          exit 0: the coverage logic, no Docker, no
#                                  browser
#   routes, the file is missing    exit 2: a configuration error
#   routes, a route off the list   exit 1: the message names the route and the
#                                  file; the browser never runs
#   routes, every route covered    exit 0: the check proceeds, 2 pages x 4 modes
#
# One result line per case goes to stdout; the checker's own output is kept
# in a temp folder and printed only for a case that went wrong. Windows
# PowerShell 5.1 and PowerShell 7. Needs Docker and node. Its twin,
# check-a11y.sh, does the same on Linux and macOS.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("docker is required")
  exit 1
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("node is required")
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

# The default of one input in the component's spec, without YAML quotes: the
# same reader as scripts/a11y.ps1. The routes cases below drive the container
# themselves, because scripts/a11y.ps1 predates required_routes_file and
# cannot forward it to the checker.
$tplLines = Get-Content -LiteralPath "templates/a11y/template.yml"
function Read-InputDefault([string]$name) {
  $inBlock = $false
  foreach ($line in $tplLines) {
    if ($line -ceq "    ${name}:") { $inBlock = $true; continue }
    if ($inBlock -and $line -match '^    [A-Za-z_]') { break }
    if ($inBlock -and $line -match '^      default:\s*(.*)$') {
      $value = $Matches[1].Trim()
      if ($value -match '^"(.*)"$') { $value = $Matches[1] }
      return $value
    }
  }
  return ""
}

$image = Read-InputDefault "image"
$axeCore = Read-InputDefault "axe_core_version"
$axePw = Read-InputDefault "axe_playwright_version"
$schemes = Read-InputDefault "color_schemes"
$widths = Read-InputDefault "widths"
$pw = ""
if ($image -match 'playwright:v([0-9]+\.[0-9]+\.[0-9]+)') { $pw = $Matches[1] }
if (-not $image -or -not $axeCore -or -not $axePw -or -not $pw) {
  [Console]::Error.WriteLine("check-a11y: cannot read the image and versions from templates/a11y/template.yml")
  exit 1
}

# Run the checker with A11Y_REQUIRED_ROUTES_FILE set, keep its log and
# reports, return its exit code.
function Invoke-RoutesGate([string]$case, [string]$site, [string]$pages, [string]$routesFile) {
  $report = Join-Path $Tmp $case
  New-Item -ItemType Directory -Force -Path $report | Out-Null
  $config = '{{"siteDir": "{0}", "pages": {1}, "tags": {2}, "colorSchemes": {3}, "widths": {4}, "axeCoreVersion": "{5}"}}' -f $site, $pages, $Tags, $schemes, $widths, $axeCore
  # The values go to the container through an env file, not -e: Windows
  # PowerShell 5.1 drops the double quotes inside a native argument, and the
  # config is JSON. An env file line is read literally.
  $envFile = Join-Path ([IO.Path]::GetTempPath()) "check-a11y-$PID.env"
  $envLines = @(
    "A11Y_CONFIG=$config",
    "A11Y_REPORT_DIR=/report",
    "A11Y_PLAYWRIGHT_VERSION=$pw",
    "A11Y_AXE_PLAYWRIGHT_VERSION=$axePw",
    "A11Y_AXE_CORE_VERSION=$axeCore",
    "A11Y_REQUIRED_ROUTES_FILE=$routesFile"
  )
  [IO.File]::WriteAllText($envFile, (($envLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
  $dockerArgs = @("run", "--rm", "--label", "task=preflight-a11y-routes-1124", "-v", "$((Get-Location).Path):/work:ro", "-v", "preflight-a11y-npm-cache:/root/.npm", "-v", "$((Resolve-Path -LiteralPath $report).Path):/report", "-w", "/work", "--env-file", $envFile, $image, "sh", "scripts/a11y-container.sh")
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $log = & docker @dockerArgs *>&1 | Out-String
  } finally {
    $ErrorActionPreference = $previous
    [IO.File]::Delete($envFile)
    Set-Location -LiteralPath $Root
  }
  [IO.File]::WriteAllText((Join-Path $Tmp "$case.log"), $log)
  return $LASTEXITCODE
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

  # routes-unit: the coverage logic as pure functions, no Docker, no browser.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $log = & node "tests/check-a11y-routes.mjs" *>&1 | Out-String
  } finally {
    $ErrorActionPreference = $previous
  }
  [IO.File]::WriteAllText((Join-Path $Tmp "routes-unit.log"), $log)
  Test-Exit "routes-unit" 0 $LASTEXITCODE

  # routes-missing: the file is set but not there: a tool error, not a check failure.
  $code = Invoke-RoutesGate "routes-missing" "tests/a11y-fixtures/routes" '["**/*.html"]' "tests/a11y-fixtures/routes/nope.txt"
  Test-Exit "routes-missing" 2 $code
  if (-not ([IO.File]::ReadAllText((Join-Path $Tmp "routes-missing.log"))).Contains("a11y: required_routes_file tests/a11y-fixtures/routes/nope.txt was not found.")) {
    Fail "routes-missing: the log does not name the missing file"
  }

  # routes-fail: a route the page list does not cover fails the check before
  # any page is opened.
  $code = Invoke-RoutesGate "routes-fail" "tests/a11y-fixtures/routes" '["**/*.html"]' "tests/a11y-fixtures/routes/routes.txt"
  Test-Exit "routes-fail" 1 $code
  if (-not ([IO.File]::ReadAllText((Join-Path $Tmp "routes-fail.log"))).Contains("a11y: 1 required route(s) are not on the page list: /about. Add them to pages, or drop them from tests/a11y-fixtures/routes/routes.txt.")) {
    Fail "routes-fail: the log does not name the uncovered route"
  }

  # routes-ok: every route covered: the check proceeds and passes.
  $code = Invoke-RoutesGate "routes-ok" "tests/a11y-fixtures/routes" '["**/*.html"]' "tests/a11y-fixtures/routes/routes-ok.txt"
  Test-Exit "routes-ok" 0 $code
  if (-not (Read-Report "routes-ok" "gl-a11y-junit.xml").Contains('tests="8" failures="0"')) {
    Fail "routes-ok: the JUnit report does not show 8 checks and 0 failures"
  }
} finally {
  [IO.Directory]::Delete($Tmp, $true)
}

if ($status -eq 0) {
  Write-Output "check-a11y: ok"
}
exit $status
