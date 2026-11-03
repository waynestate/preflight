# check-portability.ps1: do the portability fixtures still prove the contract?
#
# Runs the same steps as templates/portability/template.yml against local
# Docker (localhost instead of the registry), for the three fixtures under
# tests/portability. Exits 0 only when good passes and both bad-* fixtures
# fail.
#
# PowerShell 7, no bash. Needs Docker. The fixtures are built and run the
# strict way: a non-root user in group 0, a read-only root filesystem, /tmp
# as a tmpfs, and one anonymous volume per writable path. The goss file and
# run script are bind-mounted at /goss, because docker cp fails on a read-only
# rootfs. The goss checks (templates/portability/goss.yaml) run inside the
# container as the app user, so they see the same permissions the app has. If
# the app fails to boot (the container exits), goss runs in a keep-alive
# container from the same image, so the checks fail for the right reason.
#
# One line per fixture goes to stdout (good: pass, bad-writes-root: fail
# (expected), and so on). Build output, container logs and the goss output go
# to stderr, so the result lines stay easy to read.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Fixtures = Join-Path $Root "tests/portability"
$GossTemplate = Join-Path $Root "templates/portability/goss.yaml"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("docker is required")
  exit 1
}

# The goss checks run inside the container as the app user. The uid, port,
# health path, app root and writable paths mirror the component's defaults.
$Uid = 100123
$Port = 8080
$HealthPath = "/up"
$AppRoot = "/app"
$WritablePaths = @("storage", "bootstrap/cache")
$BootTimeout = 60

# Generate the goss file from the template and the fixture's inputs. The
# template is the same file the component uses; the writable-path checks are
# appended one per path.
function New-GossFile {
  param([string]$OutPath)
  $content = Get-Content -LiteralPath $GossTemplate -Raw
  $content = $content -replace '\{\{PORT\}\}', "$Port"
  $content = $content -replace '\{\{HEALTH_PATH\}\}', $HealthPath
  $content = $content -replace '\{\{APP_ROOT\}\}', $AppRoot
  $content = $content -replace '\{\{UID\}\}', "$Uid"
  foreach ($p in $WritablePaths) {
    $key = "writable-" + ($p -replace '/', '-')
    $content += "  ${key}:`n    exec: test -w $AppRoot/$p`n    exit-status: 0`n"
  }
  [System.IO.File]::WriteAllText($OutPath, $content)
}

# The goss download-and-run script, run inside the container as the app user.
# It is the same steps the portability-run job does inline, except the goss
# binary is downloaded to /goss (the bind mount) instead of /tmp: docker
# mounts --tmpfs with noexec, so the binary cannot be executed from /tmp. The
# goss file is bind-mounted at /goss/goss.yaml (docker cp fails on a read-only
# rootfs).
$GossRunScript = @'
set -eu
arch=$(uname -m)
case "$arch" in
  x86_64) goss_arch=x86_64; goss_sha=26e365428946294bcec0c61d867bb3c8349f39feb3d0e6f59084e98632785cc7 ;;
  aarch64|arm64) goss_arch=arm64; goss_sha=90a59612b4d67d9f1a9038634c000790136bb82526a69de1e81ac075c2f6d2c6 ;;
  *) echo "portability: unsupported architecture $arch" >&2; exit 1 ;;
esac
curl -fsSL -o /goss/goss.tar.gz "https://github.com/goss-org/goss/releases/download/v0.4.10/goss_0.4.10_linux_${goss_arch}.tar.gz"
echo "${goss_sha}  /goss/goss.tar.gz" | sha256sum -c -
tar -xzf /goss/goss.tar.gz -C /goss goss
chmod +x /goss/goss
/goss/goss validate -g /goss/goss.yaml --retry-timeout 60s
'@

function Test-Fixture {
  param([string]$Name, [string]$Expected)
  $dir = Join-Path $Fixtures $Name
  $image = "portability-$Name"

  if (-not (Test-Path -LiteralPath $dir)) {
    [Console]::Error.WriteLine("${Name}: no fixture at tests/portability/$Name")
    return 1
  }

  # Build the image from the fixture.
  $build = docker build -t $image -f (Join-Path $dir "Dockerfile") $dir 2>&1
  if ($LASTEXITCODE -ne 0) {
    $build | ForEach-Object { [Console]::Error.WriteLine("$_") }
    [Console]::Error.WriteLine("${Name}: build failed")
    return 1
  }

  # Generate the goss file and the goss run script in a host temp dir. They are
  # bind-mounted into the container at /goss, because docker cp fails on a
  # read-only rootfs (the daemon copies through the rootfs layer, not the
  # tmpfs).
  $tmpdir = Join-Path ([System.IO.Path]::GetTempPath()) "portability-$Name"
  New-Item -ItemType Directory -Path $tmpdir -Force | Out-Null
  $gossFile = Join-Path $tmpdir "goss.yaml"
  New-GossFile -OutPath $gossFile
  $gossRun = Join-Path $tmpdir "goss-run.sh"
  # The here-string carries the ps1 file's line endings (CRLF on Windows); the
  # container's sh needs LF, so normalize before writing.
  [System.IO.File]::WriteAllText($gossRun, ($GossRunScript -replace "`r`n", "`n"))

  # The strict run flags: a non-root user in group 0, a read-only root
  # filesystem, /tmp as a tmpfs, one anonymous volume per writable path (each
  # starts from the image contents), and the bind mount at /goss.
  $runArgs = @("--user", "${Uid}:0", "--read-only", "--tmpfs", "/tmp")
  foreach ($p in $WritablePaths) {
    $runArgs += @("--mount=type=volume,dst=$AppRoot/$p")
  }
  $runArgs += @("--mount=type=bind,src=$tmpdir,dst=/goss")

  # Run the app the strict way.
  $container = (docker run -d @runArgs $image 2>&1).Trim()
  if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("$container")
    [Console]::Error.WriteLine("${Name}: run failed")
    docker rmi $image | Out-Null
    Remove-Item -LiteralPath $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
    return 1
  }

  # Give the app a moment to boot or fail.
  Start-Sleep -Seconds 2

  # If the app container is still running, run goss in it. If it has exited
  # (the app failed to boot), run goss in a keep-alive container from the same
  # image with the same strict flags, so the checks fail for the right reason:
  # the health check fails because the app is not running, and the writable
  # path checks fail where the paths are not writable.
  $gossContainer = $container
  $running = (docker inspect -f '{{.State.Running}}' $container 2>&1).Trim()
  if ($running -ne "true") {
    $gossContainer = (docker run -d @runArgs $image "sh" "-c" "sleep 3600" 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) {
      [Console]::Error.WriteLine("$gossContainer")
      [Console]::Error.WriteLine("${Name}: keep-alive run failed")
      docker rm -f $container | Out-Null
      docker rmi $image | Out-Null
      Remove-Item -LiteralPath $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
      return 1
    }
  }

  # Run goss inside the container as the app user.
  $gossOutput = docker exec --user "${Uid}:0" $gossContainer sh /goss/goss-run.sh 2>&1
  $gossExit = $LASTEXITCODE
  $gossOutput | ForEach-Object { [Console]::Error.WriteLine("$_") }

  # Always remove the containers, the image, and the temp dir.
  docker rm -f $gossContainer | Out-Null
  if ($gossContainer -ne $container) { docker rm -f $container | Out-Null }
  docker rmi $image | Out-Null
  Remove-Item -LiteralPath $tmpdir -Recurse -Force -ErrorAction SilentlyContinue

  if ($gossExit -eq 0) {
    if ($Expected -eq "pass") { [Console]::Out.WriteLine("${Name}: pass"); return 0 }
    [Console]::Out.WriteLine("${Name}: pass (unexpected)")
    return 1
  }
  if ($Expected -eq "fail") { [Console]::Out.WriteLine("${Name}: fail (expected)"); return 0 }
  [Console]::Out.WriteLine("${Name}: fail")
  return 1
}

$status = 0
if ((Test-Fixture -Name "good" -Expected "pass") -ne 0) { $status = 1 }
if ((Test-Fixture -Name "bad-writes-root" -Expected "fail") -ne 0) { $status = 1 }
if ((Test-Fixture -Name "bad-needs-root" -Expected "fail") -ne 0) { $status = 1 }

exit $status
