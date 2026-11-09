#!/bin/sh
# check-sbom-fails.sh: does the sbom component still fail a bad app
# and pass a clean one?
#
# The sbom component passes Composer's exit code through: the job runs
# composer install and the CycloneDX plugin plainly, so a non-zero exit
# fails the job, and --validate fails it on an invalid SBOM. This script
# checks that the template keeps those plain lines (no tee, no pipe, no
# swallowed exit code, --validate on both make-sbom branches, --omit=dev
# on the omit_dev=true branch), then runs the two fixtures:
#
#   tests/sbom-clean  exit 0, writes sbom.cdx.json that lists psr/log and
#                     not the dev-only psr/container (the clean case)
#   tests/sbom-fails  non-zero exit, composer install refuses the broken
#                     lock (the must-fail case)
#
# It runs inside the template's image (composer:2.11.1, pinned by digest in
# templates/sbom/template.yml), where it performs the template's own
# commands from templates/sbom/template.yml for each fixture, in a copy in
# a temp dir: composer install --no-interaction --no-progress --prefer-dist
# --no-scripts --ignore-platform-reqs, then the CycloneDX plugin into a
# temp COMPOSER_HOME (composer global config ... allow-plugins...,
# composer global require cyclonedx/cyclonedx-php-composer:^6.2), then
# composer CycloneDX:make-sbom --output-format=JSON --output-reproducible
# --validate --omit=dev --output-file=sbom.cdx.json (the template's
# defaults: omit_dev true, output sbom.cdx.json). The Composer cache is
# pointed at $COMPOSER_CACHE_DIR when the caller set it, else the
# repository root's .composer-cache, which the must-fail-sbom job in
# .gitlab-ci.yml saves under a fixed key, so repeat pipelines skip the
# download. One result line per case goes to stdout; a fixture's output is
# printed only for a case that went wrong. Run it with
#
#   docker run --rm -v "$(pwd):/app" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-sbom-fails.sh
#
# Its twin, check-sbom-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/sbom/template.yml"

# A cache the caller set wins; CI falls back to the repository root's
# .composer-cache, which the must-fail-sbom job saves under a fixed key.
export COMPOSER_CACHE_DIR="${COMPOSER_CACHE_DIR:-$ROOT/.composer-cache}"

status=0
fail() {
  echo "check-sbom-fails: $1" >&2
  status=1
}

# count <text> <literal>: how many times the literal appears in the text.
# Pure shell: the image ships BusyBox grep, whose -o reports one match per
# line, so counting with grep -o would undercount.
count() {
  n=0
  t=$1
  p=$2
  while [ "${t#*"${p}"*}" != "$t" ]; do
    n=$((n + 1))
    t=${t#*"$p"}
  done
  printf '%s' "$n"
}

[ -f "$TPL" ] || fail "template missing: templates/sbom/template.yml"
[ -f "$ROOT/tests/sbom-clean/composer.json" ] || fail "clean fixture missing: tests/sbom-clean"
[ -f "$ROOT/tests/sbom-fails/composer.json" ] || fail "must-fail fixture missing: tests/sbom-fails"
[ "$status" -eq 0 ] || exit 1

# (a) the job keeps the plain install and plugin lines, and both make-sbom
# branches keep --validate (the omit_dev=true branch keeps --omit=dev), so
# Composer's exit code is the job result: no tee, no pipe, no swallowed
# exit code.
grep -Fxq -- '    - composer install --no-interaction --no-progress --prefer-dist --no-scripts --ignore-platform-reqs' "$TPL" \
  || fail "sbom job does not run composer install plainly (no tee, no pipe)"
grep -Fxq -- '    - composer global require cyclonedx/cyclonedx-php-composer:^6.2' "$TPL" \
  || fail "sbom job does not run composer global require plainly (no tee, no pipe)"
sbom_lines=$(grep -F 'CycloneDX:make-sbom' "$TPL" || true)
[ -n "$sbom_lines" ] || fail "sbom job does not run make-sbom"
makes=$(count "$sbom_lines" 'CycloneDX:make-sbom')
validates=$(count "$sbom_lines" '--validate')
[ "$makes" -eq 2 ] || fail "sbom job does not carry both make-sbom branches"
[ "$validates" -eq 2 ] || fail "a make-sbom branch lost --validate"
printf '%s\n' "$sbom_lines" | sed 's/; *else.*$//' | grep -qF -- '--omit=dev' \
  || fail "the omit_dev=true branch lost --omit=dev"
if grep 'composer' "$TPL" | grep -Eq '\|\||\| *tee|; *true'; then
  fail "a composer line swallows the exit code (||, | tee or ; true)"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The CycloneDX plugin installs into a temp COMPOSER_HOME, so the image's
# global state is never touched.
export COMPOSER_HOME="$tmp/composer-home"
mkdir -p "$COMPOSER_HOME"

# run <name> <dir>: copy the fixture to a temp dir, run the template's own
# commands there (omit_dev true, output sbom.cdx.json), keep the log and
# the exit code.
run() {
  name=$1
  dir=$2
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  (cd "$work" \
    && composer install --no-interaction --no-progress --prefer-dist --no-scripts --ignore-platform-reqs \
    && composer global config --no-plugins allow-plugins.cyclonedx/cyclonedx-php-composer true \
    && composer global require cyclonedx/cyclonedx-php-composer:^6.2 \
    && composer CycloneDX:make-sbom --output-format=JSON --output-reproducible --validate --omit=dev --output-file=sbom.cdx.json) > "$tmp/$name.log" 2>&1
  echo $?
}

# clean: the template's commands exit 0, and the SBOM lists psr/log but
# not the dev-only psr/container.
code=$(run clean tests/sbom-clean)
ok=1
[ "$code" -eq 0 ] || { fail "sbom clean: exit $code, expected 0"; ok=0; }
[ -f "$tmp/clean/sbom.cdx.json" ] || { fail "sbom clean: sbom.cdx.json missing"; ok=0; }
grep -Fq 'psr/log' "$tmp/clean/sbom.cdx.json" || { fail "sbom clean: the SBOM does not list psr/log"; ok=0; }
if grep -Fq 'psr/container' "$tmp/clean/sbom.cdx.json"; then
  fail "sbom clean: the SBOM lists the dev package psr/container"
  ok=0
fi
if [ "$ok" -eq 1 ]; then
  echo "sbom clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/clean.log" >&2
fi

# must-fail: composer install refuses the broken lock, so the template's
# commands exit non-zero.
code=$(run mustfail tests/sbom-fails)
ok=1
[ "$code" -ne 0 ] || { fail "sbom must-fail: exit 0, expected non-zero"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "sbom must-fail: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/mustfail.log" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "check-sbom-fails: ok"
fi
exit "$status"
