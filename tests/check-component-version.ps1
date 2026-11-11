# check-component-version.ps1: does every template declare spec: component:
# and print the Preflight component line first in every job?
#
# Every component declares `component: [name, version, sha, reference]` under
# spec: so GitLab fills the fields in, and the first command of every job's
# script (or its before_script, when a template uses one) prints one line:
#
#   Preflight component <name> <version> (ref <reference>, sha <sha>)
#
# so a misbehaving job's log says which Preflight release produced it
# (BEST_PRACTICES 2.11). This script checks both halves with plain string
# matching: the spec document (everything before the last `---` line) must
# carry a two-space-indented `component:` key, and the first list item of
# each job's before_script or script must contain `Preflight component`. A
# job may get its script from a hidden job through `extends:`, and the
# check follows that one level, like the .sh twin. It needs no modules, no
# yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-component-version: $message")
  $script:status = 1
}

Get-ChildItem -Path (Join-Path $Root "templates") -Directory | ForEach-Object {
  $tpl = Join-Path $_.FullName "template.yml"
  if (-not (Test-Path -LiteralPath $tpl)) { return }
  $name = $_.Name

  $lines = @(Get-Content -LiteralPath $tpl)

  # The spec document is everything before the last `---` line.
  $sepIndex = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^---[ \t]*$') { $sepIndex = $i }
  }
  if ($sepIndex -lt 0) {
    Fail "${name}: no '---' separator between the spec and jobs documents"
    return
  }
  $spec = @($lines[0..($sepIndex - 1)])
  $jobs = @($lines[($sepIndex + 1)..($lines.Count - 1)])

  # Half one: the spec declares component:.
  if (-not ($spec | Where-Object { $_ -match '^  component:[ \t]' })) {
    Fail "${name}: spec: does not declare component:"
    return
  }

  # Half two: the first command of every job prints the Preflight component
  # line. Jobs are the top-level keys of the jobs document; their keys are
  # two-space indented, and the first command is the first four-space `- `
  # item of the job's before_script (when present) or script. A job with no
  # script of its own is judged by the job its `extends:` names (php-test's
  # visible jobs extend a hidden base job). Every job is read first, then
  # judged, the same two passes as the .sh twin's awk.
  $order = New-Object System.Collections.Generic.List[string]
  $info = @{}
  $job = $null
  $wantFirst = $false
  foreach ($line in $jobs) {
    if ($line -match '^"[^"]*":[ \t]*$' -or $line -match '^[A-Za-z_.][A-Za-z0-9_.-]*:[ \t]*$') {
      $job = ($line -replace ':[ \t]*$', '')
      $order.Add($job)
      $info[$job] = @{ HaveFirst = $false; FirstOk = $false; Kind = ""; Extends = "" }
      $wantFirst = $false
      continue
    }
    if ($job -eq $null) { continue }
    $j = $info[$job]
    if ($line -match '^  before_script:[ \t]*$') {
      if ($j.Kind -eq "") { $j.Kind = "before_script"; $wantFirst = $true }
      continue
    }
    if ($line -match '^  script:[ \t]*$') {
      if ($j.Kind -eq "") { $j.Kind = "script"; $wantFirst = $true }
      continue
    }
    if ($line -match '^  extends:[ \t]*(.*?)[ \t]*$') {
      $v = $Matches[1] -replace '^"', '' -replace '"$', ''
      if ($v -ne "") { $j.Extends = $v }
      continue
    }
    if ($line -match '^  [A-Za-z_]') { $wantFirst = $false; continue }
    if ($wantFirst -and $line -match '^    - ') {
      $j.HaveFirst = $true
      $wantFirst = $false
      $j.FirstOk = ($line -match 'Preflight component')
    }
  }
  foreach ($key in $order) {
    $j = $info[$key]
    if ($j.HaveFirst) {
      if (-not $j.FirstOk) { Fail "${name}: job ${key} does not print the Preflight component line first in its $($j.Kind)" }
      continue
    }
    $target = $null
    if ($j.Extends -ne "") {
      foreach ($other in $order) {
        if (($other -replace '^"', '' -replace '"$', '') -eq $j.Extends) { $target = $other; break }
      }
    }
    if ($target -ne $null -and $info[$target].HaveFirst) {
      if (-not $info[$target].FirstOk) { Fail "${name}: job ${key} does not print the Preflight component line first in its $($info[$target].Kind)" }
      continue
    }
    Fail "${name}: job ${key} has no script or before_script to print the Preflight component line"
  }
}

if ($status -eq 0) {
  Write-Output "check-component-version: ok"
}
exit $status
