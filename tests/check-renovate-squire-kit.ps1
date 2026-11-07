# check-renovate-squire-kit.ps1: do the preset's Squire kit commands and the
# renovate component's allow-list agree, and does the allow-list stay tight?
#
# The Windows twin of check-renovate-squire-kit.sh; it checks the same
# things the same way:
#
#   * compiles the preset's commands the way Renovate does, for sample
#     upgrades (the replace helper, newVersion, packageFileDir), and checks
#     each one matches an allowed pattern;
#   * checks hostile variants (another package, a shell tail, ../ paths,
#     another squire command, another binary) match none;
#   * checks the rule installs php and composer, that postUpgradeTasks sits
#     only in the waynestate/squire rule, that no shell executor is turned
#     on, and that the kit-files rule switches Renovate off in the files
#     Squire writes (except Squire's own templates/).
#
# The patterns use only syntax that RE2 and .NET read the same way (anchors,
# classes, groups, +, *, ?), so -match answers what Renovate's RE2 would.
# Plain string matching; no modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-renovate-squire-kit: $message")
  $script:status = 1
}

$preset = Join-Path $Root "renovate\default.json"
$tpl = Join-Path $Root "templates\renovate\template.yml"
foreach ($f in @($preset, $tpl)) {
  if (-not (Test-Path -LiteralPath $f)) {
    [Console]::Error.WriteLine("check-renovate-squire-kit: missing $f")
    exit 1
  }
}

$presetLines = @(Get-Content -LiteralPath $preset)
$tplLines = @(Get-Content -LiteralPath $tpl)

# The commands of the waynestate/squire rule, JSON quotes and trailing commas
# stripped. They carry no JSON escapes.
$commands = @()
$inTasks = $false
$inCmds = $false
foreach ($line in $presetLines) {
  if ($line -match '"postUpgradeTasks"') { $inTasks = $true }
  if ($inTasks -and -not $inCmds -and $line -match '"commands"') { $inCmds = $true; continue }
  if ($inCmds -and $line -match '^\s*\]') { $inCmds = $false; $inTasks = $false }
  if ($inCmds) { $commands += ($line -replace '^\s*"', '' -replace '",?\s*$', '') }
}
if ($commands.Count -ne 2) {
  Fail "the waynestate/squire rule must carry exactly two postUpgradeTasks commands, found $($commands.Count)"
}

# postUpgradeTasks appears once, inside the waynestate/squire rule.
$tasks = @($presetLines | Where-Object { $_ -match '"postUpgradeTasks"' }).Count
if ($tasks -ne 1) {
  Fail "renovate/default.json must carry postUpgradeTasks exactly once (the waynestate/squire rule), found $tasks"
}

# within <lines> <key regex> <span> <scriptblock>: true when the scriptblock
# is true for a line within span lines after the last line matching key.
function Find-Key([string[]]$lines, [string]$keyPattern) {
  $key = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $keyPattern) { $key = $i }
  }
  return $key
}

$squireKey = Find-Key $presetLines '"matchDepNames".*"waynestate/squire"'
$inRule = $false
if ($squireKey -ge 0) {
  $last = [Math]::Min($squireKey + 8, $presetLines.Count - 1)
  for ($j = $squireKey + 1; $j -le $last; $j++) {
    if ($presetLines[$j] -match '"postUpgradeTasks"') { $inRule = $true }
  }
}
if (-not $inRule) {
  Fail "postUpgradeTasks is not inside the waynestate/squire rule"
}

# The rule installs the tools its commands need.
$toolsKey = Find-Key $presetLines '"installTools"'
$hasPhp = $false
$hasComposer = $false
if ($toolsKey -ge 0) {
  $last = [Math]::Min($toolsKey + 4, $presetLines.Count - 1)
  for ($j = $toolsKey + 1; $j -le $last; $j++) {
    if ($presetLines[$j] -match '"php"') { $hasPhp = $true }
    if ($presetLines[$j] -match '"composer"') { $hasComposer = $true }
  }
}
if (-not ($hasPhp -and $hasComposer)) {
  Fail "the waynestate/squire postUpgradeTasks must install php and composer (installTools)"
}

# Each template expression is one Renovate compiles the way this test does.
$uniq = "{{{replace '[^A-Za-z0-9_-]' '-' repository}}}-{{{replace '[^A-Za-z0-9_-]' '-' packageFile}}}"
$cmd1 = if ($commands.Count -ge 1) { $commands[0] } else { "" }
$cmd2 = if ($commands.Count -ge 2) { $commands[1] } else { "" }
$want1 = "composer create-project --no-dev --no-interaction --no-progress --no-scripts waynestate/squire /tmp/renovate-squire/$uniq {{{newVersion}}}"
$want2 = "php /tmp/renovate-squire/$uniq/bin/squire update --path={{{packageFileDir}}}"
if ($cmd1 -cne $want1) { Fail "command 1 is not the expected one: $cmd1" }
if ($cmd2 -cne $want2) { Fail "command 2 is not the expected one: $cmd2" }

# The allowed patterns, from config.js in the template: the quoted strings
# between "allowedCommands: squireKitTasks ? [" and "] : []", with the JS
# escape \\ turned back into \.
$patterns = @()
$inList = $false
foreach ($line in $tplLines) {
  if ($line -match 'allowedCommands: squireKitTasks \? \[') { $inList = $true; continue }
  if ($inList -and $line -match '\] : \[\]') { $inList = $false }
  if ($inList) {
    $p = $line -replace '^\s*"', '' -replace '",?\s*$', ''
    $patterns += $p.Replace('\\', '\')
  }
}
if ($patterns.Count -ne 2) {
  Fail "templates/renovate/template.yml must allow exactly two commands, found $($patterns.Count)"
}
if (-not ($tplLines | Where-Object { $_.Contains('const squireKitTasks = $[[ inputs.squire_kit_tasks ]];') })) {
  Fail "config.js does not take the allow-list switch from the squire_kit_tasks input"
}
$inBlock = $false
$isBool = $false
$isFalse = $false
foreach ($line in $tplLines) {
  if ($line -match '^    squire_kit_tasks:') { $inBlock = $true; continue }
  if ($inBlock -and $line -match '^    [A-Za-z_]') { $inBlock = $false }
  if ($inBlock -and $line -match '^      type: boolean') { $isBool = $true }
  if ($inBlock -and $line -match '^      default: false') { $isFalse = $true }
}
if (-not ($isBool -and $isFalse)) {
  Fail "the squire_kit_tasks input must be a boolean that defaults to false"
}
if (($presetLines + $tplLines) | Where-Object { $_ -match 'allowShellExecutorForPostUpgradeCommands' }) {
  Fail "the shell executor must stay off: commands run as plain argument lists"
}

function Test-Allowed([string]$command) {
  foreach ($p in $script:patterns) {
    if ($command -cmatch $p) { return $true }
  }
  return $false
}

function Compile([string]$raw, [string]$repo, [string]$file, [string]$dir, [string]$ver) {
  $repoSeg = $repo -replace '[^A-Za-z0-9_-]', '-'
  $fileSeg = $file -replace '[^A-Za-z0-9_-]', '-'
  return $raw.Replace("{{{replace '[^A-Za-z0-9_-]' '-' repository}}}", $repoSeg).
    Replace("{{{replace '[^A-Za-z0-9_-]' '-' packageFile}}}", $fileSeg).
    Replace('{{{packageFileDir}}}', $dir).
    Replace('{{{newVersion}}}', $ver)
}

# Sample upgrades: repository, packageFile, packageFileDir, newVersion.
$samples = @(
  @('enterprise-apps/creed', 'deploy/.squire.json', 'deploy', '0.5.0'),
  @('group/sub/app', '.squire.json', '', '1.12.0'),
  @('enterprise-apps/preflight', 'tests/squire-kit-fixture/.squire.json', 'tests/squire-kit-fixture', '0.6.0')
)
foreach ($s in $samples) {
  foreach ($raw in @($cmd1, $cmd2)) {
    $compiled = Compile $raw $s[0] $s[1] $s[2] $s[3]
    if ($compiled.Contains('{{')) { Fail "a template expression was left uncompiled: $compiled" }
    if (-not (Test-Allowed $compiled)) { Fail "allowedCommands does not allow the preset's command: $compiled" }
  }
}

# Hostile variants: each must match no allowed pattern.
$pre = 'composer create-project --no-dev --no-interaction --no-progress --no-scripts'
$sq = 'php /tmp/renovate-squire/enterprise-apps-creed-deploy--squire-json/bin/squire'
$bad = @(
  "$pre waynestate/squire /tmp/renovate-squire/x 0.5.0; id",
  "$pre waynestate/squire /tmp/renovate-squire/x 0.5.0 && id",
  "$pre waynestate/squire-evil /tmp/renovate-squire/x 0.5.0",
  "$pre other/package /tmp/renovate-squire/x 0.5.0",
  "$pre --repository=https://example.com waynestate/squire /tmp/renovate-squire/x 0.5.0",
  "$pre waynestate/squire /tmp/renovate-squire/../x 0.5.0",
  "$pre waynestate/squire /tmp/renovate-squire/a/b 0.5.0",
  "$pre waynestate/squire /home/x 0.5.0",
  "$pre waynestate/squire /tmp/renovate-squire/x dev-main",
  'composer create-project waynestate/squire /tmp/renovate-squire/x 0.5.0',
  "$sq update --path=../etc",
  "$sq update --path=/etc",
  "$sq update --path=a/../b",
  "$sq update --path=.hidden",
  "$sq update --path=deploy `$(id)",
  "$sq update --path=deploy; id",
  "$sq init --force --path=deploy",
  "$sq update --dry-run --path=deploy",
  'php /tmp/renovate-squire/../evil/bin/squire update --path=deploy',
  'php /tmp/renovate-squire/x/evil.php update --path=deploy',
  "php -r system('id');",
  'sh -c id'
)
foreach ($b in $bad) {
  if (Test-Allowed $b) { Fail "allowedCommands must not allow: $b" }
}

# The kit-files rule: Renovate leaves the files Squire writes alone, apart
# from Squire's own source templates, and they move with a Squire release.
$kitKey = Find-Key $presetLines ([regex]::Escape('"**/docker-compose.squire.yml"'))
$c = $false; $sDir = $false; $t = $false; $e = $false
if ($kitKey -ge 0) {
  $last = [Math]::Min($kitKey + 4, $presetLines.Count - 1)
  for ($j = $kitKey; $j -le $last; $j++) {
    $l = $presetLines[$j]
    if ($l.Contains('"**/docker-compose.squire.yml"')) { $c = $true }
    if ($l.Contains('"**/.squire/**"')) { $sDir = $true }
    if ($l.Contains('"!/^templates\\/(common|vue|raw|laravel|static)\\//"')) { $t = $true }
    if ($l -match '"enabled":\s*false') { $e = $true }
  }
}
if (-not ($c -and $sDir -and $t -and $e)) {
  Fail "the kit-files rule (docker-compose.squire.yml and .squire/ off, Squire's templates/ kept) is missing or incomplete"
}

if ($status -eq 0) {
  Write-Output "check-renovate-squire-kit: ok"
}
exit $status
