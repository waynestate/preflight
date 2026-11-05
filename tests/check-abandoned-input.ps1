# check-abandoned-input.ps1: does composer-audit expose the abandoned input,
# and does the flag behave the way the docs promise?
#
# An abandoned package fails the job by default (Composer's own default),
# and the abandoned input lets an app relax it on purpose: fail (default),
# report (list them, do not fail) or ignore. This script checks that the
# template and contract/inputs.json carry the input with its default and
# regex and that the job passes --abandoned, then runs composer audit in
# the composer:2.10.3 Docker image on two fixtures under
# tests/audit-fixtures: a lock whose only package is abandoned (fail exits
# non-zero, report and ignore exit 0) and a lock with a known advisory
# (all three modes exit non-zero).
#
# PowerShell 7 with no modules: the template is checked line by line and
# the contract with ConvertFrom-Json, so the only external tool is Docker.
# The .sh twin needs only POSIX tools and Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$TemplatePath = Join-Path $Root "templates/composer-audit/template.yml"
$ContractPath = Join-Path $Root "contract/inputs.json"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-abandoned-input: $message")
  $script:status = 1
}

function Invoke-ComposerAudit {
  param([string]$Fixture, [string]$Mode)
  $out = docker run --rm -v "${Root}/tests/audit-fixtures/${Fixture}:/w" -w /w composer:2.10.3 composer audit --locked "--abandoned=$Mode" 2>&1
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($out) }
}

# (a) the template carries the input with its default, regex and flag.
if (-not (Test-Path -LiteralPath $TemplatePath)) {
  Fail "template missing: templates/composer-audit/template.yml"
} else {
  $tpl = @(Get-Content -LiteralPath $TemplatePath)
  $specEnd = $tpl.Count
  for ($i = 0; $i -lt $tpl.Count; $i++) {
    if ($tpl[$i] -ceq '---') { $specEnd = $i; break }
  }
  $idx = -1
  for ($i = 0; $i -lt $specEnd; $i++) {
    if ($tpl[$i] -ceq '    abandoned:') { $idx = $i; break }
  }
  if ($idx -lt 0) {
    Fail 'template has no abandoned input in spec.inputs'
  } else {
    $end = $specEnd
    for ($i = $idx + 1; $i -lt $specEnd; $i++) {
      if ($tpl[$i] -match '^    \S') { $end = $i; break }
    }
    $block = @()
    for ($i = $idx + 1; $i -lt $end; $i++) { $block += $tpl[$i] }
    foreach ($want in @(
      '      description: "How composer audit treats abandoned packages: fail (default), report (list them, do not fail) or ignore."',
      '      type: string',
      '      default: fail',
      "      regex: '^(fail|report|ignore)$'"
    )) {
      if ($block -notcontains $want) {
        Fail "template abandoned input is missing or wrong: $want"
      }
    }
  }
  $scriptLine = '    - composer audit --locked --abandoned=$[[ inputs.abandoned ]]'
  if ($tpl -notcontains $scriptLine) {
    Fail "template script does not pass the input: expected '$scriptLine'"
  }
}

# (b) the contract lists the input with the same shape.
if (-not (Test-Path -LiteralPath $ContractPath)) {
  Fail "contract missing: contract/inputs.json"
} else {
  $contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
  $entry = @($contract.components.'composer-audit'.inputs | Where-Object { $_.name -ceq 'abandoned' })
  if ($entry.Count -eq 0) {
    Fail 'contract/inputs.json composer-audit entry has no abandoned input'
  } else {
    $e = $entry[0]
    if ("$($e.type)" -cne 'string') { Fail "contract abandoned input type is $($e.type), expected string" }
    if ("$($e.default)" -cne 'fail') { Fail "contract abandoned input default is $($e.default), expected fail" }
    if ("$($e.regex)" -cne '^(fail|report|ignore)$') { Fail "contract abandoned input regex is $($e.regex), expected ^(fail|report|ignore)$" }
  }
}

# (c) and (d) the flag behaves: the abandoned fixture fails only in fail
# mode, the advisory fixture fails in every mode.
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Fail "docker is required: this script runs composer audit in the composer:2.10.3 image"
} else {
  foreach ($fixture in @('abandoned', 'advisory')) {
    foreach ($f in @('composer.json', 'composer.lock')) {
      if (-not (Test-Path -LiteralPath (Join-Path $Root "tests/audit-fixtures/$fixture/$f"))) {
        Fail "fixture missing: tests/audit-fixtures/$fixture/$f"
      }
    }
  }
  $expectFail = [ordered]@{
    'abandoned/fail' = $true
    'abandoned/report' = $false
    'abandoned/ignore' = $false
    'advisory/fail' = $true
    'advisory/report' = $true
    'advisory/ignore' = $true
  }
  foreach ($key in $expectFail.Keys) {
    $parts = $key -split '/'
    $r = Invoke-ComposerAudit -Fixture $parts[0] -Mode $parts[1]
    if ($expectFail[$key]) {
      if ($r.ExitCode -eq 0) {
        Fail "composer audit --abandoned=$($parts[1]) on $($parts[0]) exited 0, expected non-zero"
        Write-Output $r.Output
      }
    } elseif ($r.ExitCode -ne 0) {
      Fail "composer audit --abandoned=$($parts[1]) on $($parts[0]) exited $($r.ExitCode), expected 0"
      Write-Output $r.Output
    }
  }
}

if ($status -eq 0) {
  Write-Output "check-abandoned-input: ok"
}
exit $status
