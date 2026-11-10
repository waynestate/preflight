#!/bin/sh
# check-preflight-gates-warns.sh: do PROCTOR's preflight-gates and
# preflight-pinned checks still warn about pipelines that skip or weaken
# Preflight, without failing them?
#
# Row 3.3 of BEST_PRACTICES.md says these checks detect an app with no
# Preflight include, an unpinned include, allow_failure on a gate, or a
# missing proctor job, and that both warn and never fail. This script
# proves it with the real PROCTOR (installed from the fixture app's own
# composer.lock), not a stub: it copies tests/fixture-app to a temp dir,
# installs its dependencies once with the proctor template's install flags,
# then swaps only the copy's .gitlab-ci.yml per case and runs the
# template's default command,
#
#   vendor/bin/proctor check --format=codequality
#
# on the copy:
#
#   as-is (no Preflight include, no proctor job) exit 0, warns preflight-gates-no-include and preflight-gates-no-proctor-job
#   proctor@0.5.0 with allow_failure: true       exit 0, warns preflight-gates-allow-failure
#   proctor@main                                 exit 0, warns preflight-pinned-unpinned
#
# PROCTOR counts an include as Preflight's only when the literal component
# string contains /preflight/, so the swapped files name
# git.wayne.edu/enterprise-apps/preflight/proctor@... verbatim, the way an
# app's pipeline does.
#
# It needs the network: composer install downloads the fixture's packages
# once. A provided COMPOSER_CACHE_DIR (the CI job and the Docker wrappers
# point it at a shared cache) is kept; without one the cache stays in the
# temp dir. One result line per case goes to stdout; a case's output is
# printed only when it went wrong.
#
# It runs inside the template's image (composer:2.11.1, pinned by digest in
# templates/proctor/template.yml). Run it with
#
#   docker run --rm -v "$(pwd):/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-preflight-gates-warns.sh
#
# Its twin, check-preflight-gates-warns.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0
fail() {
  echo "check-preflight-gates-warns: $1" >&2
  status=1
}

for f in tests/fixture-app/composer.json \
  tests/fixture-app/composer.lock \
  tests/fixture-app/.gitlab-ci.yml
do
  [ -f "$ROOT/$f" ] || fail "fixture missing: $f"
done
[ "$status" -eq 0 ] || exit 1

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A fresh Composer home, so no global config can change a verdict. A
# provided COMPOSER_CACHE_DIR is kept, so the shared download cache works;
# otherwise the cache stays in the temp dir.
export COMPOSER_HOME="$tmp/composer-home"
mkdir -p "$COMPOSER_HOME"
[ -n "${COMPOSER_CACHE_DIR:-}" ] || export COMPOSER_CACHE_DIR="$tmp/composer-cache"
mkdir -p "$COMPOSER_CACHE_DIR"

work="$tmp/app"
cp -R "$ROOT/tests/fixture-app" "$work"
(cd "$work" && composer install --no-interaction --no-progress --no-plugins --no-scripts --ignore-platform-reqs) > "$tmp/install.log" 2>&1
if [ $? -ne 0 ]; then
  echo "check-preflight-gates-warns: composer install failed" >&2
  sed 's/^/  | /' "$tmp/install.log" >&2
  exit 1
fi

# The swapped-in pipelines. PROCTOR counts an include as Preflight's only
# when the literal component string contains /preflight/, so the refs are
# written verbatim, the way an app's pipeline names them.
printf '%s\n' \
  '# case allow-failure: the gate is included but allowed to fail' \
  'image: composer:2.11.1' \
  '' \
  'include:' \
  '  - component: git.wayne.edu/enterprise-apps/preflight/proctor@0.5.0' \
  '    inputs:' \
  '      allow_failure: true' \
  '' \
  'ci:' \
  '  script:' \
  '    - composer install --no-interaction --no-progress' \
  '    - composer ci' > "$tmp/ci-allow-failure.yml"

printf '%s\n' \
  '# case unpinned: the include tracks a branch' \
  'image: composer:2.11.1' \
  '' \
  'include:' \
  '  - component: git.wayne.edu/enterprise-apps/preflight/proctor@main' \
  '' \
  'ci:' \
  '  script:' \
  '    - composer install --no-interaction --no-progress' \
  '    - composer ci' > "$tmp/ci-unpinned.yml"

# run <name> [ci-file]: swap the case's .gitlab-ci.yml into the copy (the
# as-is case keeps the fixture's own), run the template's default command,
# keep the report, PROCTOR's stderr and the exit code.
run() {
  name=$1
  ci=${2:-}
  [ -n "$ci" ] && cp "$ci" "$work/.gitlab-ci.yml"
  (cd "$work" && vendor/bin/proctor check --format=codequality > report.json 2> stderr.log)
  code=$?
  cat "$work/report.json" > "$tmp/$name.log"
  sed 's/^/  | /' "$work/stderr.log" >> "$tmp/$name.log"
  echo "$code"
}

# expect <name> [ci-file] <pattern>...: one case. The run must exit 0 (the
# warnings never fail) and the report must name every pattern, so a green
# run that warned nothing never passes.
expect() {
  name=$1
  ci=${2:-}
  shift 2
  label="preflight gates $name"
  code=$(run "$name" "$ci")
  ok=1
  if [ "$code" -ne 0 ]; then
    fail "$label: exit $code, expected 0 (the warnings must not fail)"
    ok=0
  fi
  for pattern in "$@"; do
    if ! grep -Fq -- "$pattern" "$tmp/$name.log"; then
      fail "$label: the report does not name $pattern"
      ok=0
    fi
  done
  if [ "$ok" -eq 1 ]; then
    echo "$label: exit 0, warnings as expected"
  else
    sed 's/^/  | /' "$tmp/$name.log" >&2
  fi
}

# as-is: the fixture's pipeline has no Preflight include and no proctor job.
expect as-is '' 'preflight-gates-no-include:' 'preflight-gates-no-proctor-job:'

# allow-failure: the gate is included but allowed to fail.
expect allow-failure "$tmp/ci-allow-failure.yml" 'preflight-gates-allow-failure:'

# unpinned: the include tracks a branch instead of a release tag or SHA.
expect unpinned "$tmp/ci-unpinned.yml" 'preflight-pinned-unpinned:'

if [ "$status" -eq 0 ]; then
  echo "check-preflight-gates-warns: ok"
fi
exit "$status"
