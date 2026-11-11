# check-path-input-regex.ps1: do the path-like inputs that reach a shell line
# carry their input regex, and do the patterns accept and reject the right
# values?
#
# phpstan's config and memory_limit, pint's config and sbom's output land in
# unquoted or free positions of a job script line, so a free string is a
# shell-injection hole. The GitLab input regex constrains the path inputs to
# a relative path: the leading-character rule blocks absolute paths (/etc)
# and parent references (../x), and the character class blocks spaces,
# semicolons and $(...). memory_limit takes a PHP size such as 1G, 512M or
# -1. A value outside the regex stops the pipeline at creation. The pattern
# still allows a/../b; that is a later slice (same as working_dir), so this
# test pins the exact regex lines instead of re-deriving the rule. The
# proctor check_path input is checked here too: the job cds into it after
# the install, so it must stay a relative path or be empty.
#
# test_command, proctor_command and eslint_args stay free on purpose: they
# are arbitrary commands by design.
#
# Plain string matching and .NET regex: no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-path-input-regex: $message")
  $script:status = 1
}

# The expected regex lines, exactly as they must appear in the templates.
$pathRegexLine = "      regex: '^[A-Za-z0-9_-][A-Za-z0-9._/-]*$'"
$memoryRegexLine = "      regex: '^(-1|[0-9]+[KkMmGg]?)$'"
$checkPathRegexLine = "      regex: '^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)?$'"

function Get-InputBlock([string[]]$spec, [string]$key) {
  $block = @()
  $inBlock = $false
  foreach ($line in $spec) {
    if (-not $inBlock) {
      if ($line -match "^    ${key}:[ \t]*$") { $inBlock = $true }
      continue
    }
    if ($line -match '^    [A-Za-z_]' -or $line -match '^[^ ]') { break }
    $block += $line
  }
  return $block
}

function Check-Input([string]$name, [string]$tpl, [string]$inputName, [string]$expectedLine) {
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

  $block = @(Get-InputBlock $spec $inputName)
  if ($block.Count -eq 0) {
    Fail "${name}: the $inputName input is not defined in the spec"
    return
  }

  # The regex line must be present and exactly the expected one.
  $regexLine = $block | Where-Object { $_ -match '^      regex:' } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($regexLine)) {
    Fail "${name}: the $inputName input has no regex line"
    return
  }
  if ($regexLine -ne $expectedLine) {
    Fail "${name}: the $inputName regex line is not the expected one: $regexLine"
    return
  }

  # Pull the pattern out of the quoted value.
  $pattern = $regexLine -replace '^      regex:[ \t]*', ''
  $pattern = $pattern.Trim()
  if ($pattern.Length -ge 2 -and $pattern.StartsWith("'") -and $pattern.EndsWith("'")) {
    $pattern = $pattern.Substring(1, $pattern.Length - 2)
  }

  # The default must match.
  $default = $null
  foreach ($line in $block) {
    if ($line -match '^      default:[ \t]*(.*)$') { $default = $Matches[1]; break }
  }
  if ([string]::IsNullOrWhiteSpace($default)) {
    Fail "${name}: the $inputName input has no default"
  } else {
    $default = $default.Trim()
    if ($default.Length -ge 2 -and $default.StartsWith('"') -and $default.EndsWith('"')) {
      $default = $default.Substring(1, $default.Length - 2)
    }
    if ($default -notmatch $pattern) {
      Fail "${name}: the $inputName default does not match the regex: $default"
    }
  }
}

Check-Input "phpstan" (Join-Path $Root "templates/phpstan/template.yml") "config" $pathRegexLine
Check-Input "phpstan" (Join-Path $Root "templates/phpstan/template.yml") "memory_limit" $memoryRegexLine
Check-Input "pint" (Join-Path $Root "templates/pint/template.yml") "config" $pathRegexLine
Check-Input "proctor" (Join-Path $Root "templates/proctor/template.yml") "check_path" $checkPathRegexLine
Check-Input "sbom" (Join-Path $Root "templates/sbom/template.yml") "output" $pathRegexLine

# The path pattern accepts the samples.
$pathPattern = '^[A-Za-z0-9_-][A-Za-z0-9._/-]*$'
foreach ($good in @('phpstan.neon', 'config/phpstan.neon', 'sbom.cdx.json', 'a_b-c/d.json')) {
  if ($good -notmatch $pathPattern) {
    Fail "path regex: $good should match"
  }
}

# The path pattern rejects the samples.
foreach ($bad in @('/etc/passwd', '../x', '.hidden', 'a b', 'a;b', '$(id)')) {
  if ($bad -match $pathPattern) {
    Fail "path regex: $bad must not match"
  }
}

# The check_path pattern accepts the samples.
$checkPathPattern = '^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)?$'
foreach ($good in @('.', 'deploy', 'a_b-c/d', 'tests/fixture-app', '')) {
  if ($good -notmatch $checkPathPattern) {
    Fail "check_path regex: $good should match"
  }
}

# The check_path pattern rejects the samples.
foreach ($bad in @('/etc', '../x', '..', '.hidden', 'a b', 'a;b', '$(id)', 'deploy/..;id')) {
  if ($bad -match $checkPathPattern) {
    Fail "check_path regex: $bad must not match"
  }
}

# The memory_limit pattern accepts the samples.
$memoryPattern = '^(-1|[0-9]+[KkMmGg]?)$'
foreach ($good in @('1G', '512M', '-1', '2048')) {
  if ($good -notmatch $memoryPattern) {
    Fail "memory_limit regex: $good should match"
  }
}

# The memory_limit pattern rejects the samples.
foreach ($bad in @('1G;id', 'G', '1 G', '')) {
  if ($bad -match $memoryPattern) {
    Fail "memory_limit regex: $bad must not match"
  }
}

if ($status -eq 0) {
  Write-Output "check-path-input-regex: ok"
}
exit $status
