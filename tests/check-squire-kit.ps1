# check-squire-kit.ps1: does the squire-kit component still check the kit the
# way its docs promise?
#
# The Windows twin of check-squire-kit.sh; it reads the template as text and
# fails when a promise breaks:
#
#   * the job checks the folder in working_dir and fails on drift, with
#     Squire's exit codes (0 match, 1 drift, 2 the check could not run);
#   * the version comes from .squire.json unless squire_version is set, and
#     is a released x.y.z before it reaches Composer;
#   * Composer installs Squire outside the project with --no-dev and
#     --no-scripts, so nothing from the project or Squire's dev tools runs;
#   * squire_version only takes an empty value or x.y.z, and allow_failure
#     reaches the job as a real boolean, false by default;
#   * Preflight's own pipeline runs the component on the fixture kit in
#     tests/squire-kit-fixture, which records a released Squire.
#
# Plain string matching; no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-squire-kit: $message")
  $script:status = 1
}

$tpl = Join-Path $Root "templates\squire-kit\template.yml"
if (-not (Test-Path -LiteralPath $tpl)) {
  [Console]::Error.WriteLine("check-squire-kit: missing templates/squire-kit/template.yml")
  exit 1
}

$lines = @(Get-Content -LiteralPath $tpl)
$sep = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^---\s*$') { $sep = $i }
}
if ($sep -lt 0) {
  [Console]::Error.WriteLine("check-squire-kit: no '---' separator between the spec and jobs documents")
  exit 1
}
$spec = @($lines[0..($sep - 1)])
$jobs = @($lines[($sep + 1)..($lines.Count - 1)])

function Test-Line([string[]]$doc, [string]$line, [string]$message) {
  if (-not ($doc | Where-Object { $_ -ceq $line })) { Fail $message }
}

# The job: the kit folder, the version, the install and the check.
Test-Line $jobs '    - cd "$[[ inputs.working_dir ]]"' "the job does not cd into working_dir"
Test-Line $jobs '  allow_failure: $[[ inputs.allow_failure ]]' "allow_failure is not interpolated as a bare boolean"
Test-Line $jobs '      if [ ! -f .squire.json ]; then' "the job does not stop when the folder has no .squire.json"
Test-Line $jobs '      version="$[[ inputs.squire_version ]]"' "the job does not take squire_version first"
Test-Line $jobs '        version=$(php -r ''$m = json_decode((string) file_get_contents(".squire.json"), true); echo is_array($m) && is_string($m["version"] ?? null) ? $m["version"] : "";'')' "the job does not read the recorded version from .squire.json"
Test-Line $jobs '      if ! printf ''%s\n'' "$version" | grep -Eq ''^[0-9]+\.[0-9]+\.[0-9]+$''; then' "the job does not insist on a released x.y.z version"
Test-Line $jobs '      if ! composer create-project --no-dev --no-interaction --no-progress --no-scripts --quiet waynestate/squire "$squire_home/squire" "$version"; then' "the job does not install Squire with --no-dev and --no-scripts outside the project"
Test-Line $jobs '      squire_home=$(mktemp -d)' "the job does not install Squire into a temporary folder"
Test-Line $jobs '      php "$squire_home/squire/bin/squire" init --check --path=. || status=$?' "the job does not run squire init --check on the kit folder"
Test-Line $jobs '      exit "$status"' "the job does not exit with squire init --check's code"
if (@($jobs | Where-Object { $_ -match 'exit 2$' }).Count -ne 3) {
  Fail "the job must stop with exit 2 when there is no .squire.json, no released version, or no such Squire"
}

# The job only checks: every run of the Squire it installed is init --check.
if ($jobs | Where-Object { $_.Contains('$squire_home/squire/bin/squire') -and -not $_.Contains(' init --check ') }) {
  Fail "the job runs a squire command other than init --check"
}

# squire_version: empty or x.y.z only, and nothing else.
$pattern = '^([0-9]+\.[0-9]+\.[0-9]+)?$'
Test-Line $spec "      regex: '$pattern'" "the squire_version input does not carry its regex"
foreach ($good in @('', '0.5.0', '10.20.30')) {
  if ($good -notmatch $pattern) { Fail "squire_version regex: '$good' should match" }
}
foreach ($bad in @('0.5', 'v0.5.0', 'dev-main', '0.5.0; id', '$(id)', '0.5.0 0.4.0')) {
  if ($bad -match $pattern) { Fail "squire_version regex: '$bad' must not match" }
}

# allow_failure: a boolean, false by default.
$inBlock = $false
$isBool = $false
$isFalse = $false
foreach ($line in $spec) {
  if ($line -match '^    allow_failure:') { $inBlock = $true; continue }
  if ($inBlock -and $line -match '^    [A-Za-z_]') { $inBlock = $false }
  if ($inBlock -and $line -match '^      type: boolean') { $isBool = $true }
  if ($inBlock -and $line -match '^      default: false') { $isFalse = $true }
}
if (-not ($isBool -and $isFalse)) {
  Fail "the allow_failure input must be a boolean that defaults to false"
}

# The fixture kit and Preflight's own include of it.
$manifest = Join-Path $Root "tests\squire-kit-fixture\.squire.json"
if (-not (Test-Path -LiteralPath $manifest)) {
  Fail "tests/squire-kit-fixture/.squire.json is missing"
} elseif (-not ((Get-Content -LiteralPath $manifest -Raw) -match '"version": "[0-9]+\.[0-9]+\.[0-9]+"')) {
  Fail "tests/squire-kit-fixture/.squire.json does not record a released Squire version"
}
$ci = @(Get-Content -LiteralPath (Join-Path $Root ".gitlab-ci.yml"))
$key = -1
for ($i = 0; $i -lt $ci.Count; $i++) {
  if ($ci[$i].Contains('/squire-kit@$CI_COMMIT_SHA')) { $key = $i }
}
$found = $false
if ($key -ge 0) {
  $last = [Math]::Min($key + 3, $ci.Count - 1)
  for ($j = $key + 1; $j -le $last; $j++) {
    if ($ci[$j].Contains('working_dir: tests/squire-kit-fixture')) { $found = $true }
  }
}
if (-not $found) {
  Fail ".gitlab-ci.yml does not run the squire-kit component on tests/squire-kit-fixture"
}

if ($status -eq 0) {
  Write-Output "check-squire-kit: ok"
}
exit $status
