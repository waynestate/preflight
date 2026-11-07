# check-job-names.ps1: do the job-name templates take their job key from a
# job_name input?
#
# A component included twice must not merge into one job: these templates
# name the job with $[[ inputs.job_name ]] and promise a default through a
# job_name input (PREFLIGHT-14). Part A covers five templates; part B extends
# TEMPLATES below.
#
# The template is two YAML documents separated by `---`: the spec before the
# last separator, the jobs after it. Some templates start with a comment
# header, so the split happens at the last `---` line, not the first. This
# script checks the documents with plain string matching, so it needs no
# modules, no yq and no Docker.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$Templates = @("pint", "phpstan", "eslint", "sbom", "renovate", "proctor", "php-test", "composer-audit", "package-publish", "secret-detection", "a11y")

$status = 0

function Fail([string]$message) {
  [Console]::Error.WriteLine("check-job-names: $message")
  $script:status = 1
}

foreach ($name in $Templates) {
  $tpl = Join-Path $Root "templates/$name/template.yml"
  if (-not (Test-Path -LiteralPath $tpl)) {
    Fail "${name}: no template at templates/$name/template.yml"
    continue
  }

  $lines = @(Get-Content -LiteralPath $tpl)

  # The jobs document is everything after the last `---` line.
  $sepIndex = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^---[ \t]*$') { $sepIndex = $i }
  }
  if ($sepIndex -lt 0) {
    Fail "${name}: no '---' separator between the spec and jobs documents"
    continue
  }
  $spec = @($lines[0..($sepIndex - 1)])
  $jobs = @($lines[($sepIndex + 1)..($lines.Count - 1)])

  # The job key must be exactly $[[ inputs.job_name ]].
  $jobKey = '"$[[ inputs.job_name ]]":'
  if (-not ($jobs -contains $jobKey)) {
    Fail "${name}: jobs document has no $jobKey job key"
  }

  # The spec must declare the job_name input with a non-empty default:.
  $inJob = $false
  $hasDefault = $false
  foreach ($line in $spec) {
    if ($inJob) {
      if ($line -match '^    [A-Za-z_][A-Za-z0-9_-]*:') { $inJob = $false; continue }
      if ($line -match '^      default:\s*(\S.*)$') { $hasDefault = $true; break }
    }
    elseif ($line -match '^    job_name:') { $inJob = $true }
  }
  if ($hasDefault) {
  } elseif (-not ($spec -match '^    job_name:')) {
    Fail "${name}: spec does not declare a job_name input"
  } else {
    Fail "${name}: job_name input has no non-empty default"
  }
}

if ($status -eq 0) {
  Write-Output "check-job-names: ok"
}
exit $status