# check-portability-inline.ps1: does the portability template carry
# templates/portability/probe.sh byte for byte?
#
# A GitLab component ships only its template.yml, so the portability job
# writes the probe from a heredoc in the template. The readable source is
# templates/portability/probe.sh, which tests/check-portability.sh runs
# against the fixtures. This test fails when the two drift apart, so the
# must-fail fixtures and a consumer's pipeline always probe the same way.
#
#   tests\check-portability-inline.ps1          check (exit 0 in step, 1 drifted)
#   tests\check-portability-inline.ps1 -Write   copy probe.sh into the heredoc
#
# The heredoc sits in a YAML block scalar indented by six spaces: each line
# of probe.sh is written with six spaces in front, and blank lines stay
# blank. Plain string handling, so it needs no modules, no yq and no Docker.
# Its twin, check-portability-inline.sh, does the same on Linux and macOS.

param([switch]$Write)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Tpl = Join-Path $Root "templates/portability/template.yml"
$Src = Join-Path $Root "templates/portability/probe.sh"
$Start = '      cat > /tmp/portability-probe.sh <<''PREFLIGHT_PORTABILITY_PROBE'''
$End = '      PREFLIGHT_PORTABILITY_PROBE'

foreach ($f in @($Tpl, $Src)) {
  if (-not (Test-Path -LiteralPath $f)) {
    [Console]::Error.WriteLine("check-portability-inline: missing $f")
    exit 1
  }
}

# Read as UTF-8 and split on LF, so the comparison sees the bytes git stores.
function Read-Lines([string]$path) {
  $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
  if ($text.EndsWith("`n")) { $text = $text.Substring(0, $text.Length - 1) }
  return , ($text -split "`n")
}

$tplLines = Read-Lines $Tpl
$srcLines = Read-Lines $Src

$startAt = @(for ($i = 0; $i -lt $tplLines.Count; $i++) { if ($tplLines[$i] -ceq $Start) { $i } })
$endAt = @(for ($i = 0; $i -lt $tplLines.Count; $i++) { if ($tplLines[$i] -ceq $End) { $i } })
if ($startAt.Count -ne 1 -or $endAt.Count -ne 1 -or $endAt[0] -lt $startAt[0]) {
  [Console]::Error.WriteLine("check-portability-inline: templates/portability/template.yml needs exactly one heredoc start and end line for probe.sh")
  exit 1
}

# The source as the template must carry it: six spaces in front, blank lines
# left blank.
$indented = @($srcLines | ForEach-Object { if ($_ -eq "") { "" } else { "      $_" } })

if ($Write) {
  $out = @()
  $out += $tplLines[0..$startAt[0]]
  $out += $indented
  $out += $tplLines[$endAt[0]..($tplLines.Count - 1)]
  [System.IO.File]::WriteAllText($Tpl, (($out -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
  Write-Output "check-portability-inline: wrote templates/portability/probe.sh into templates/portability/template.yml"
  exit 0
}

$inlined = @()
if ($endAt[0] - $startAt[0] -gt 1) {
  $inlined = @($tplLines[($startAt[0] + 1)..($endAt[0] - 1)])
}

if (($indented -join "`n") -cne ($inlined -join "`n")) {
  [Console]::Error.WriteLine("check-portability-inline: the heredoc in templates/portability/template.yml differs from templates/portability/probe.sh; run tests\check-portability-inline.ps1 -Write")
  exit 1
}

# GitLab interpolates $[[ ... ]] everywhere in a template, heredoc included.
if (($srcLines -join "`n").Contains('$[[')) {
  [Console]::Error.WriteLine('check-portability-inline: templates/portability/probe.sh contains $[[, which GitLab would interpolate')
  exit 1
}

# session_header: declared as an input, passed into the probe, resolved from
# the job environment with printenv, and never through eval.
if (-not @($tplLines | Where-Object { $_ -ceq '    session_header:' })) {
  [Console]::Error.WriteLine("check-portability-inline: templates/portability/template.yml has no session_header input")
  exit 1
}
if (-not @($tplLines | Where-Object { $_ -ceq '      session_header=$[[ inputs.session_header ]]' })) {
  [Console]::Error.WriteLine("check-portability-inline: the inputs heredoc does not pass session_header to the probe")
  exit 1
}
if (-not (($srcLines -join "`n").Contains('printenv'))) {
  [Console]::Error.WriteLine("check-portability-inline: templates/portability/probe.sh does not resolve session_header with printenv")
  exit 1
}
$usesEval = $false
foreach ($line in $srcLines) {
  if ($line -match '(^|[\s;|&(`])eval\s') { $usesEval = $true; break }
}
if ($usesEval) {
  [Console]::Error.WriteLine("check-portability-inline: templates/portability/probe.sh uses eval")
  exit 1
}

Write-Output "check-portability-inline: ok"
exit 0
