# check-composer-floor.ps1: do the php-test and proctor templates hold the
# same composer_version regex, and does that pattern keep out the Composer
# versions below the stack's floor?
#
# Both components install the Composer named by composer_version (default
# 2.11.1). The stack's floor is 2.9.6 (BEST_PRACTICES 4.6 and 4.9): a
# Composer from before the 2026 security fixes must be refused at pipeline
# creation, not discovered at install time. The pattern accepts 2.9.6 to
# 2.9.x and 2.10.0 and later, and refuses 2.9.5, 2.8.x, 2.0.0 and 3.x.
#
# The script pulls the regex line out of each template's composer_version
# input (the first regex: line after composer_version:, single quotes
# stripped) and tests the pattern against the sample values with -match;
# RE2 and .NET agree on this simple pattern. It needs no modules, no
# network and no Docker, and runs on Windows PowerShell 5.1 and
# PowerShell 7.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-composer-floor: $message")
  $script:status = 1
}

# The composer_version regex of one template: the value of the regex: line
# inside its input block, with the single quotes stripped.
function PatternOf([string]$template, [string]$name) {
  $lines = @(Get-Content -LiteralPath $template)

  # The spec document is everything before the last `---` line.
  $sep = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^---[ \t]*$') { $sep = $i }
  }
  if ($sep -lt 0) {
    Fail "${name}: no ``---`` separator between the spec and jobs documents"
    return ''
  }
  $spec = $lines[0..($sep - 1)]

  # The composer_version block: from its line to the next input or document end.
  $block = @()
  $inblock = $false
  foreach ($line in $spec) {
    if (-not $inblock) {
      if ($line -match '^    composer_version:[ \t]*$') { $inblock = $true }
      continue
    }
    if ($line -match '^    [A-Za-z_]' -or $line -match '^[^ ]') { break }
    $block += $line
  }

  # The regex line must be present.
  $regexLine = $null
  foreach ($line in $block) {
    if ($line -match '^      regex:') { $regexLine = $line }
  }
  if ($null -eq $regexLine) {
    Fail "${name}: the composer_version input has no regex line"
    return ''
  }

  # Pull the pattern out of the quoted value.
  $pattern = $regexLine -replace '^      regex:[ \t]*''', ''
  return ($pattern -replace "'$", '')
}

$phpTestPattern = PatternOf (Join-Path $Root 'templates/php-test/template.yml') 'php-test'
if ($status -ne 0) { exit 1 }
$proctorPattern = PatternOf (Join-Path $Root 'templates/proctor/template.yml') 'proctor'
if ($status -ne 0) { exit 1 }

if ($phpTestPattern -ne $proctorPattern) {
  Fail "the composer_version regex differs between the templates: php-test '$phpTestPattern', proctor '$proctorPattern'"
  exit 1
}

foreach ($good in @('2.9.6', '2.9.10', '2.10.3', '2.11.1', '2.20.0')) {
  if ($good -notmatch $phpTestPattern) {
    Fail "$good should match the composer_version regex"
  }
}

foreach ($bad in @('2.9.5', '2.8.12', '2.0.0', '3.0.0', '2.10', 'v2.10.3')) {
  if ($bad -match $phpTestPattern) {
    Fail "$bad must not match the composer_version regex"
  }
}

if ($status -eq 0) {
  Write-Output "check-composer-floor: ok"
}
exit $status
