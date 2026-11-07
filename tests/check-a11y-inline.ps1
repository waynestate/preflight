# check-a11y-inline.ps1: does the a11y template carry templates/a11y/check.mjs
# byte for byte?
#
# A GitLab component ships only its template.yml, so the a11y job writes the
# checker from a heredoc in the template. The readable source is
# templates/a11y/check.mjs, which scripts/a11y.sh and scripts/a11y.ps1 run
# locally. This test fails when the two drift apart, so a local run and a
# pipeline run always check the same way.
#
#   tests\check-a11y-inline.ps1          check (exit 0 in step, 1 drifted)
#   tests\check-a11y-inline.ps1 -Write   copy check.mjs into the heredoc
#
# The heredoc sits in a YAML block scalar indented by six spaces: each line
# of check.mjs is written with six spaces in front, and blank lines stay
# blank. Plain string handling, so it needs no modules, no yq and no Docker.
# Its twin, check-a11y-inline.sh, does the same on Linux and macOS.

param([switch]$Write)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Tpl = Join-Path $Root "templates/a11y/template.yml"
$Src = Join-Path $Root "templates/a11y/check.mjs"
$Start = '      cat > "$A11Y_HOME/check.mjs" <<''PREFLIGHT_A11Y_CHECK'''
$End = '      PREFLIGHT_A11Y_CHECK'

foreach ($f in @($Tpl, $Src)) {
  if (-not (Test-Path -LiteralPath $f)) {
    [Console]::Error.WriteLine("check-a11y-inline: missing $f")
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
  [Console]::Error.WriteLine("check-a11y-inline: templates/a11y/template.yml needs exactly one heredoc start and end line for check.mjs")
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
  Write-Output "check-a11y-inline: wrote templates/a11y/check.mjs into templates/a11y/template.yml"
  exit 0
}

$inlined = @()
if ($endAt[0] - $startAt[0] -gt 1) {
  $inlined = @($tplLines[($startAt[0] + 1)..($endAt[0] - 1)])
}

if (($indented -join "`n") -cne ($inlined -join "`n")) {
  [Console]::Error.WriteLine("check-a11y-inline: the heredoc in templates/a11y/template.yml differs from templates/a11y/check.mjs; run tests\check-a11y-inline.ps1 -Write")
  exit 1
}

# GitLab interpolates $[[ ... ]] everywhere in a template, heredoc included.
if (($srcLines -join "`n").Contains('$[[')) {
  [Console]::Error.WriteLine('check-a11y-inline: templates/a11y/check.mjs contains $[[, which GitLab would interpolate')
  exit 1
}

Write-Output "check-a11y-inline: ok"
exit 0
