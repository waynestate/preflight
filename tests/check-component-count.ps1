# check-component-count.ps1: do the docs count the components correctly?
#
# templates/ holds one folder per component, and BEST_PRACTICES.md and
# README.md name how many there are in several places. When a component is
# added, those counts drift: 0.9.0 added composer-ci and the docs still say
# fifteen. This check fails if any part of that contract is broken:
#
#   * the component-list sentence in BEST_PRACTICES.md stops saying
#     "Today it has <word>:" with the right word;
#   * an "All <word> templates" or "The <word> templates" phrase in
#     BEST_PRACTICES.md uses a different word;
#   * the "<Word> on the manifest" line in README.md uses a different word;
#     or
#   * the 7.2 sentence "Every component that runs as a job, X of Y," in
#     BEST_PRACTICES.md ends in a different word.
#
# The script counts the directories under templates/ that hold a
# template.yml, converts the count to its English word, and greps the docs
# for the count, so it needs no modules, no yq and no Docker.
#
# --self-test runs the guard against a temp copy of the repo files with the
# word changed to fourteen and passes only when that run fails. The guard
# reads the files from the PF_ROOT environment variable (default: the repo
# root), so the self-test points it at the copy.

$ErrorActionPreference = "Stop"

$Root = if ($env:PF_ROOT) { $env:PF_ROOT } else { Split-Path -Parent $PSScriptRoot }

$Words = @(
  "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
  "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
  "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "twenty-one",
  "twenty-two", "twenty-three", "twenty-four", "twenty-five", "twenty-six",
  "twenty-seven", "twenty-eight", "twenty-nine", "thirty")

function Invoke-Check {
  param([string]$CheckRoot)

  $script:Status = 0
  $Fail = {
    param([string]$Message)
    [Console]::Error.WriteLine("check-component-count: $Message")
    $script:Status = 1
  }

  $Bp = Join-Path $CheckRoot "BEST_PRACTICES.md"
  $Rm = Join-Path $CheckRoot "README.md"
  $Templates = Join-Path $CheckRoot "templates"

  if (-not (Test-Path -LiteralPath $Bp)) { $Fail "BEST_PRACTICES.md is missing"; return }
  if (-not (Test-Path -LiteralPath $Rm)) { $Fail "README.md is missing"; return }
  if (-not (Test-Path -LiteralPath $Templates)) { $Fail "templates/ is missing"; return }

  $Count = @(Get-ChildItem -LiteralPath $Templates -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "template.yml") }).Count
  if ($Count -lt 1 -or $Count -gt 30) {
    $Fail "templates/ holds $Count components; the guard names counts from one to thirty only"
    return
  }
  $Word = $Words[$Count]
  $CapWord = $Word.Substring(0, 1).ToUpper() + $Word.Substring(1)

  # The component-list sentence names the count.
  $m = Select-String -LiteralPath $Bp -Pattern 'Today it has [a-z]+:' -List
  if (-not $m) {
    $Fail "BEST_PRACTICES.md: no 'Today it has <word>:' sentence in the component list, expected 'Today it has $Word:'"
  } elseif ($m.Matches[0].Value -ne "Today it has $Word:") {
    $Fail "BEST_PRACTICES.md: found '$($m.Matches[0].Value)', expected 'Today it has $Word:'"
  }

  # Every "All <word> templates" and "The <word> templates" phrase uses the count.
  foreach ($Pattern in @('All [a-z]+ templates', 'The [a-z]+ templates')) {
    $Lead = ($Pattern -split ' ')[0]
    $Seen = @{}
    foreach ($mm in (Select-String -LiteralPath $Bp -Pattern $Pattern -AllMatches).Matches) {
      $w = ($mm.Value -split ' ')[1]
      if ($w -eq $Word -or $Seen[$w]) { continue }
      $Seen[$w] = $true
      $Fail "BEST_PRACTICES.md: found '$Lead $w templates', expected the word '$Word'"
    }
  }

  # The README manifest line uses the capitalised count.
  $line = (Select-String -LiteralPath $Rm -Pattern '<sub>.*on the manifest' -List).Line
  if (-not $line) {
    $Fail "README.md: no '<sub>' line with 'on the manifest', expected '$CapWord on the manifest'"
  } else {
    $found = [regex]::Match($line, '<sub>[^A-Za-z]*([A-Z][A-Za-z-]*) on the manifest').Groups[1].Value
    if ($found -ne $CapWord) {
      $Fail "README.md: found '$found on the manifest', expected '$CapWord on the manifest'"
    }
  }

  # The 7.2 sentence "Every component that runs as a job, X of Y," ends in the count.
  $m2 = Select-String -LiteralPath $Bp -Pattern 'Every component that runs as a job, [a-z]+ of [a-z]+,' -List
  if (-not $m2) {
    $Fail "BEST_PRACTICES.md: no 7.2 sentence 'Every component that runs as a job, X of Y,', expected Y to be '$Word'"
  } else {
    $phrase = $m2.Matches[0].Value
    $y = ((($phrase -replace ',', '') -split ' ') | Select-Object -Last 1)
    if ($y -ne $Word) {
      $Fail "BEST_PRACTICES.md: found '$phrase', expected the second word to be '$Word'"
    }
  }
}

if ($args -contains '--self-test') {
  # Run the guard against a copy of the repo files whose word is changed to
  # fourteen; it passes only when that run fails.
  $Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pf-compcount-" + [System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $Tmp | Out-Null
  try {
    Copy-Item -LiteralPath (Join-Path $Root "BEST_PRACTICES.md") -Destination $Tmp
    Copy-Item -LiteralPath (Join-Path $Root "README.md") -Destination $Tmp
    Copy-Item -LiteralPath (Join-Path $Root "templates") -Destination $Tmp -Recurse
    $Count = @(Get-ChildItem -LiteralPath (Join-Path $Tmp "templates") -Directory |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "template.yml") }).Count
    $Word = $Words[$Count]
    $CapWord = $Word.Substring(0, 1).ToUpper() + $Word.Substring(1)
    foreach ($Name in @("BEST_PRACTICES.md", "README.md")) {
      $Path = Join-Path $Tmp $Name
      $Text = [System.IO.File]::ReadAllText($Path)
      $Text = $Text.Replace($Word, "fourteen").Replace($CapWord, "Fourteen")
      [System.IO.File]::WriteAllText($Path, $Text)
    }
    $env:PF_ROOT = $Tmp
    Invoke-Check -CheckRoot $Tmp
    $Bad = $script:Status
    Remove-Item Env:PF_ROOT
    if ($Bad -eq 0) {
      [Console]::Error.WriteLine("check-component-count: self-test failed: the guard passed on a copy whose word was changed to fourteen")
      exit 1
    }
  } finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force
  }
  Write-Output "check-component-count: self-test ok"
  exit 0
}

Invoke-Check -CheckRoot $Root
if ($script:Status -eq 0) {
  Write-Output "check-component-count: ok"
}
exit $script:Status
