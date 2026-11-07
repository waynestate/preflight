# check-input-interpolation.ps1: do the templates hand their inputs to the
# job's shell the way GitLab interpolates them?
#
# GitLab replaces only the $[[ inputs.name ]] form before the job runs. Any
# other mention of inputs. reaches the job's shell as literal text: $([[
# inputs.name ]]) is a command substitution that runs [[ inputs.name ]],
# which fails in POSIX sh (and prints nothing in bash), so the variable ends
# up empty and whatever depends on it never runs. This test scans every
# template for $([[ (or $( [[) and for inputs. references that are not
# inside $[[ ... ]].
#
# Plain string matching, so it needs no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-input-interpolation: $message")
  $script:status = 1
}

Get-ChildItem -LiteralPath (Join-Path $Root "templates") -Directory | ForEach-Object {
  $name = $_.Name
  $tpl = Join-Path $_.FullName "template.yml"
  if (-not (Test-Path -LiteralPath $tpl)) { return }

  $lines = @(Get-Content -LiteralPath $tpl)

  # A $([[ is a command substitution running the [[ test, not an
  # interpolation. $( [[ with a space is the same mistake.
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\$\(\[+\[') {
      Fail "${name}: line $($i + 1): shell command substitution where an interpolation belongs: $($lines[$i].Trim())"
    }
  }

  # Every inputs.<name> reference must sit inside $[[ ... ]].
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    foreach ($m in [regex]::Matches($line, 'inputs\.[A-Za-z_][A-Za-z0-9_-]*')) {
      $before = $line.Substring(0, $m.Index)
      $after = $line.Substring($m.Index + $m.Length)
      if ($before -notmatch '\$\[\[[ \t]*$' -or $after -notmatch '^[ \t]*\]\]') {
        Fail "${name}: line $($i + 1): $($m.Value) is not inside `\$[[ ... ]]: $($line.Trim())"
      }
    }
  }
}

if ($status -eq 0) {
  Write-Output "check-input-interpolation: ok"
}
exit $status
