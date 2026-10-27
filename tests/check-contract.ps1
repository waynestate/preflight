# check-contract.ps1: do the templates still match contract/inputs.json?
#
# The contract is the promise to consumers: inside a major version, an input
# keeps its name, type and default, and a job keeps its name
# (BEST_PRACTICES.md 1.4). This script is the test that catches a rename
# before a consumer does.
#
# PowerShell 7 has no YAML parser built in, and this script must run with no
# modules, so the YAML is parsed by running yq in Docker:
#   docker run --rm -v "<root>:/w" -w /w mikefarah/yq:4 -o=json eval ...
# Needs Docker and the mikefarah/yq:4 image. The .sh twin needs only yq.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ContractPath = Join-Path $Root "contract/inputs.json"

if (-not (Test-Path -LiteralPath $ContractPath)) {
  [Console]::Error.WriteLine("contract/inputs.json not found at $ContractPath")
  exit 1
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("docker is required: this script parses the templates with yq in Docker")
  exit 1
}

$contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json

function Invoke-YqJson {
  param([string[]]$YqArgs)
  docker run --rm -v "${Root}:/w" -w /w mikefarah/yq:4 -o=json @YqArgs
  if ($LASTEXITCODE -ne 0) {
    throw "yq failed (exit $LASTEXITCODE): mikefarah/yq:4 $($YqArgs -join ' ')"
  }
}

function Format-Json {
  param($Value)
  ConvertTo-Json -InputObject $Value -Depth 10 -Compress
}

function Test-SameValue {
  param($A, $B)
  (Format-Json $A) -ceq (Format-Json $B)
}

$status = 0
$componentNames = @($contract.components.PSObject.Properties.Name)

foreach ($name in $componentNames) {
  $component = $contract.components.$name
  $tplPath = "templates/$name/template.yml"
  if (-not (Test-Path -LiteralPath (Join-Path $Root $tplPath))) {
    Write-Output "contract entry '$name' has no template at $tplPath"
    $status = 1
    continue
  }
  $tplInputs = Invoke-YqJson @("eval", "select(document_index == 0) | .spec.inputs", $tplPath) | ConvertFrom-Json
  $tplJobs = @(Invoke-YqJson @("eval", "select(document_index == 1) | keys", $tplPath) | ConvertFrom-Json)
  $contractInputs = @($component.inputs)
  $contractJobs = @($component.jobs)
  $mismatches = @()

  foreach ($ci in $contractInputs) {
    $prop = $tplInputs.PSObject.Properties[$ci.name]
    if (-not $prop) {
      $mismatches += "missing input: $($ci.name)"
      continue
    }
    if ("$($prop.Value.type)" -cne "$($ci.type)") {
      $mismatches += "input $($ci.name): type is $($prop.Value.type), contract says $($ci.type)"
    }
    if (-not (Test-SameValue $prop.Value.default $ci.default)) {
      $mismatches += "input $($ci.name): default is $(Format-Json $prop.Value.default), contract says $(Format-Json $ci.default)"
    }
  }
  foreach ($n in @($tplInputs.PSObject.Properties.Name)) {
    if ($contractInputs.name -notcontains $n) {
      $mismatches += "unexpected input: $n"
    }
  }
  foreach ($j in $contractJobs) {
    if ($tplJobs -notcontains $j) {
      $mismatches += "missing job: $j"
    }
  }
  foreach ($j in $tplJobs) {
    if ($contractJobs -notcontains $j) {
      $mismatches += "unexpected job: $j"
    }
  }

  if ($mismatches.Count -gt 0) {
    Write-Output "component '$name' does not match the contract:"
    foreach ($m in $mismatches) {
      Write-Output $m
    }
    $status = 1
  }
}

# A template that is not in the contract is drift too.
$tplDirs = Get-ChildItem -LiteralPath (Join-Path $Root "templates") -Directory |
  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "template.yml") }
foreach ($d in $tplDirs) {
  if ($componentNames -notcontains $d.Name) {
    Write-Output "template '$($d.Name)' has no entry in contract/inputs.json"
    $status = 1
  }
}

if ($status -eq 0) {
  Write-Output "contract: all components match contract/inputs.json"
}
exit $status
