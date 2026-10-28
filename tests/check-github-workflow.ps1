# check-github-workflow.ps1: are the GitHub Actions workflows safe to run?
#
# A reusable workflow runs with the permissions the caller gives it, and an
# unpinned action can be repointed to run arbitrary code. This script checks
# the two things that keep a workflow honest:
#   1. every `uses:` is pinned to a full 40-hex commit SHA (or is a local
#      `./` action), so a repointed tag cannot change what runs; and
#   2. `permissions` grants nothing beyond `read` or `none`, so the workflow
#      cannot write back to the caller's repository.
#
# PowerShell 7 has no YAML parser built in, and this script must run with no
# modules, so the permissions check parses the workflow with yq in Docker:
#   docker run --rm -v "<root>:/w" -w /w mikefarah/yq@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e eval ...
# The pinning check is plain regex. Needs Docker and the mikefarah/yq image.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$WfDir = Join-Path $Root ".github/workflows"

if (-not (Test-Path -LiteralPath $WfDir)) {
  [Console]::Error.WriteLine(".github/workflows not found at $WfDir")
  exit 1
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("docker is required: this script parses the workflows with yq in Docker")
  exit 1
}

function Invoke-YqJson {
  param([string[]]$YqArgs)
  docker run --rm -v "${Root}:/w" -w /w mikefarah/yq@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e -o=json @YqArgs
  if ($LASTEXITCODE -ne 0) {
    throw "yq failed (exit $LASTEXITCODE): mikefarah/yq@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e $($YqArgs -join ' ')"
  }
}

$status = 0
$workflows = Get-ChildItem -LiteralPath $WfDir -Filter *.yml -File

foreach ($wf in $workflows) {
  $wfStatus = 0
  # Container-relative path with forward slashes: yq runs in Docker with -w /w,
  # so it sees the repo at /w and needs a POSIX path, not a Windows one.
  $rel = $wf.FullName.Substring($Root.Length + 1) -replace '\\', '/'
  $lines = Get-Content -LiteralPath $wf.FullName

  # --- 1. every uses: is pinned to a full commit SHA -----------------------
  # A step's uses: is usually on its own line, but a single-key step may be
  # written as `- uses:`, so allow an optional list dash before it.
  foreach ($line in $lines) {
    if ($line -match '^\s*(?:-\s+)?uses:\s*(\S+)') {
      $value = $Matches[1]
      if ($value -like './.*') {
        continue  # a local action lives in the repo; nothing to pin
      }
      if ($value -notmatch '^[^@]+@[0-9a-f]{40}$') {
        Write-Output "${rel}: unpinned action: $value"
        $wfStatus = 1
      }
    }
  }

  # --- 2. permissions grant only read or none ------------------------------
  # The permissions key may be a scalar (permissions: read) or a map
  # (permissions: { contents: read }). A reusable workflow must set one, so a
  # null result is a failure. yq returns it as JSON; PowerShell handles both
  # shapes.
  $permValue = Invoke-YqJson @("eval", ".permissions", $rel) | ConvertFrom-Json
  if ($null -eq $permValue) {
    Write-Output "${rel}: no permissions key (a reusable workflow must set one)"
    $wfStatus = 1
  } elseif ($permValue -is [System.Management.Automation.PSCustomObject]) {
    foreach ($prop in $permValue.PSObject.Properties) {
      if ($prop.Value -ne "read" -and $prop.Value -ne "none") {
        Write-Output "${rel}: permission '$($prop.Value)' is not read or none"
        $wfStatus = 1
      }
    }
  } else {
    if ($permValue -ne "read" -and $permValue -ne "none") {
      Write-Output "${rel}: permission '$permValue' is not read or none"
      $wfStatus = 1
    }
  }

  if ($wfStatus -eq 0) {
    Write-Output "${rel}: actions pinned, permissions read-only"
  }
  if ($wfStatus -ne 0) {
    $status = 1
  }
}

if ($status -eq 0) {
  Write-Output "github workflows: all actions pinned, all permissions read-only"
}
exit $status
