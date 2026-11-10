# check-portability.ps1: does the portability probe still pass a portable app
# and fail each flaw for the right reason?
#
# Windows twin of check-portability.sh. The .sh is the payload of a
# container: it runs inside the component's own Buildah image and runs
# templates/portability/probe.sh against tests/portability/app, once clean
# and once per flaw, passing only when the clean case passes and each flaw
# fails the check it targets. The setup-fails case proves a setup_command
# that exits 3 stops the job before any replica starts. This wrapper runs
# the .sh in that image with
# Docker, the repository bound read-only:
#
#   docker run --rm --security-opt seccomp=unconfined -v "<repo>:/src:ro" -w /src \
#     <the Buildah image in $Image below> sh tests/check-portability.sh
#
# seccomp=unconfined, not --privileged: Docker's default seccomp profile
# refuses the user namespace Buildah's chroot isolation needs, and GitLab
# runners commonly allow it. No extra capabilities are granted either way.
#
# -Cases limits the run to some flaws, for example -Cases none,sigterm. One
# result line per case goes to stdout. Needs PowerShell 7 and Docker, no
# bash. Its twin, check-portability.sh, does the same on Linux and macOS.

param([string[]]$Cases = @())

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Image = "quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("check-portability: docker is required")
  exit 1
}

$envArgs = @()
if ($Cases.Count -gt 0) {
  $envArgs = @("-e", "PORTABILITY_CASES=$($Cases -join ' ')")
}

docker run --rm --security-opt seccomp=unconfined @envArgs -v "${Root}:/src:ro" -w /src $Image "sh" "tests/check-portability.sh"
exit $LASTEXITCODE
