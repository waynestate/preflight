# check-abandoned-input.ps1: does composer-audit expose the abandoned input
# the way the docs promise?
#
# An abandoned package fails the job by default (Composer's own default),
# and the abandoned input lets an app relax it on purpose: fail (default),
# report (list them, do not fail) or ignore. This script checks that the
# template and contract/inputs.json carry the input with its default and
# regex and that the job passes --abandoned. How the flag behaves on real
# locks is check-composer-audit-fails.ps1's job: it runs composer audit in
# Docker and needs the network.
#
# PowerShell 7 with no modules: the template is checked line by line and
# the contract with ConvertFrom-Json, so it needs no external tool.
# The .sh twin needs only POSIX tools.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$TemplatePath = Join-Path $Root "templates/composer-audit/template.yml"
$ContractPath = Join-Path $Root "contract/inputs.json"

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-abandoned-input: $message")
  $script:status = 1
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

if ($status -eq 0) {
  Write-Output "check-abandoned-input: ok"
}
exit $status
