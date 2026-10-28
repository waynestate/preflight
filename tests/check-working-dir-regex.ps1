# check-working-dir-regex.ps1: does every working_dir input carry the
# relative-path regex, and does the pattern accept and reject the right
# values?
#
# working_dir lands in a cd "..." line in the job script, so a free string
# is a shell-injection hole. The GitLab input regex constrains it to a
# relative path: the leading-character rule blocks absolute paths (/etc)
# and parent references (../x), and the character class blocks spaces,
# semicolons and $(...). The pattern still allows a/../b; that is a later
# slice, so this test pins the exact regex line instead of re-deriving the
# rule.
#
# Plain string matching and .NET regex: no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-working-dir-regex: $message")
  $script:status = 1
}

# The one regex line every working_dir input must carry, exactly.
$expectedRegexLine = "      regex: '^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$'"

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
    Fail "${name}: no `---` separator between the spec and jobs documents"
    return
  }
  $spec = @($lines[0..($sepIndex - 1)])

  # Only templates that define a working_dir input are checked.
  if (-not ($spec | Where-Object { $_ -match '^    working_dir:[ \t]*$' })) { return }

  # The working_dir block: from its line to the next input or document end.
  $block = @()
  $inBlock = $false
  foreach ($line in $spec) {
    if (-not $inBlock) {
      if ($line -match '^    working_dir:[ \t]*$') { $inBlock = $true }
      continue
    }
    if ($line -match '^    [A-Za-z_]' -or $line -match '^[^ ]') { break }
    $block += $line
  }

  # The regex line must be present and exactly the expected one.
  $regexLine = $block | Where-Object { $_ -match '^      regex:' } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($regexLine)) {
    Fail "${name}: the working_dir input has no regex line"
    Write-Output "check-working-dir-regex: ${name}: FAIL"
    return
  }
  if ($regexLine -ne $expectedRegexLine) {
    Fail "${name}: the working_dir regex line is not the expected one: $regexLine"
    Write-Output "check-working-dir-regex: ${name}: FAIL"
    return
  }

  # Pull the pattern out of the quoted value.
  $pattern = $regexLine -replace '^      regex:[ \t]*', ''
  $pattern = $pattern.Trim()
  if ($pattern.Length -ge 2 -and $pattern.StartsWith("'") -and $pattern.EndsWith("'")) {
    $pattern = $pattern.Substring(1, $pattern.Length - 2)
  }

  $before = $status

  # The default must match.
  $default = $null
  foreach ($line in $block) {
    if ($line -match '^      default:[ \t]*(.*)$') { $default = $Matches[1]; break }
  }
  if ([string]::IsNullOrWhiteSpace($default)) {
    Fail "${name}: the working_dir input has no default"
  } else {
    $default = $default.Trim()
    if ($default.Length -ge 2 -and $default.StartsWith('"') -and $default.EndsWith('"')) {
      $default = $default.Substring(1, $default.Length - 2)
    }
    if ($default -notmatch $pattern) {
      Fail "${name}: the working_dir default does not match the regex: $default"
    }
  }

  # Values that must match.
  foreach ($good in @('web/app', 'packages/api')) {
    if ($good -notmatch $pattern) {
      Fail "${name}: $good should match the working_dir regex"
    }
  }

  # Values that must not match.
  foreach ($bad in @('/etc', '../x', 'a;rm', '$(id)', 'a b')) {
    if ($bad -match $pattern) {
      Fail "${name}: $bad must not match the working_dir regex"
    }
  }

  if ($status -eq $before) {
    Write-Output "check-working-dir-regex: ${name}: ok"
  } else {
    Write-Output "check-working-dir-regex: ${name}: FAIL"
  }
}

if ($status -eq 0) {
  Write-Output "check-working-dir-regex: ok"
}
exit $status
