# check-php-matrix.ps1: does php-test keep its parallel: matrix wiring?
#
# The php-test component creates one job per PHP version: GitLab expands
# the php_versions array input into a parallel:matrix, PHP_VERSION becomes
# a CI/CD variable in each job, and the image input's default expands it.
# This check fails if either half goes away:
#
#   * the three consecutive lines in the jobs document:
#       parallel:
#         matrix:
#           - PHP_VERSION: $[[ inputs.php_versions ]]
#   * the php_versions input declared in the spec with type: array and a
#     non-empty default: list.
#
# The template is two YAML documents separated by `---`; the jobs live in
# the second. This script reads the documents and checks them with plain
# string matching, so it needs no modules and no yq, and it runs natively
# in PowerShell 7 without sh or Git Bash.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-php-matrix: $message")
  $script:status = 1
}

$tpl = Join-Path $Root "templates/php-test/template.yml"
if (-not (Test-Path -LiteralPath $tpl)) {
  [Console]::Error.WriteLine("templates/php-test/template.yml not found at $tpl")
  exit 1
}

# Read with -Raw and split on \r?\n so CRLF checkouts behave like LF ones.
$lines = @((Get-Content -Raw -LiteralPath $tpl) -split '\r?\n')

# The jobs document is everything after the last `---` line; the spec
# document is everything before it.
$sepIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^---[ \t]*$') { $sepIndex = $i }
}
if ($sepIndex -lt 0) {
  Fail "no `---` separator between the spec and jobs documents"
  exit 1
}
$spec = @($lines[0..($sepIndex - 1)])
$jobs = @($lines[($sepIndex + 1)..($lines.Count - 1)])

# The matrix block: three consecutive lines in the jobs document. Each
# line is checked on its own so the missing piece is named, then the three
# are required to sit next to each other.
if ($jobs -cnotcontains '  parallel:') {
  Fail "php-test job has no parallel: line"
}
if ($jobs -cnotcontains '    matrix:') {
  Fail "php-test job has no matrix: line"
}
if ($jobs -cnotcontains '      - PHP_VERSION: $[[ inputs.php_versions ]]') {
  Fail "php-test matrix does not feed the php_versions input"
}
$p = $false
$m = $false
$consecutive = $false
foreach ($line in $jobs) {
  if ($line -ceq '  parallel:') { $p = $true; continue }
  if ($p -and $line -ceq '    matrix:') { $m = $true; continue }
  if ($m -and $line -ceq '      - PHP_VERSION: $[[ inputs.php_versions ]]') { $consecutive = $true; break }
  $p = $false
  $m = $false
}
if (-not $consecutive) {
  Fail "the parallel:, matrix: and PHP_VERSION lines are not consecutive"
}

# The spec must declare php_versions as an array with a non-empty default
# list. The block runs from the input key to the next four-space key.
$block = @()
$inBlock = $false
foreach ($line in $spec) {
  if ($line -cmatch '^    php_versions:[ \t]*$') { $inBlock = $true; continue }
  if (-not $inBlock) { continue }
  if ($line -cmatch '^    [A-Za-z_]' -or $line -cmatch '^[^ ]') { $inBlock = $false; continue }
  $block += $line
}
if ($block.Count -eq 0) {
  Fail "the spec does not declare the php_versions input"
} else {
  if (-not ($block | Where-Object { $_ -cmatch '^      type:[ \t]*array[ \t]*$' })) {
    Fail "the php_versions input is not type: array"
  }
  $defaults = @($block | Where-Object { $_ -cmatch '^      default:[ \t]*(.*)$' } | ForEach-Object { $_ -creplace '^      default:[ \t]*', '' })
  $compact = (($defaults -join '') -replace '\s', '')
  if ($compact.Length -eq 0) {
    Fail "the php_versions input has no default: list"
  } elseif ($compact -ceq '[]') {
    Fail "the php_versions default: list is empty"
  }
}

if ($status -eq 0) {
  Write-Output "check-php-matrix: ok"
}
exit $status
