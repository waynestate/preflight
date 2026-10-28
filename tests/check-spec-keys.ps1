# check-spec-keys.ps1: does every template keep spec: to the keys GitLab
# accepts (inputs and description)?
#
# GitLab's component spec header rejects unknown keys: a pipeline that
# includes a component carrying version, name, category or tags under
# spec: fails at creation with "header:spec config contains unknown keys".
# The spec may carry only inputs and description, so this test fails on any
# other key directly under spec:.
#
# The template is two YAML documents separated by `---`: the spec before the
# last separator, the jobs after it. Some templates start with a comment
# header, so the spec document is everything before the last `---` line, not
# the first. The keys directly under spec: are the two-space-indented keys of
# that document. This script reads the documents and checks them with plain
# string matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-spec-keys: $message")
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

  # The keys directly under spec: are the two-space-indented keys.
  foreach ($line in $spec) {
    if ($line -match '^  ([A-Za-z_][A-Za-z0-9_-]*):') {
      $key = $Matches[1]
      if ($key -ne 'inputs' -and $key -ne 'description') {
        Fail "${name}: spec: has an unknown key: $key"
      }
    }
  }
}

if ($status -eq 0) {
  Write-Output "check-spec-keys: ok"
}
exit $status
