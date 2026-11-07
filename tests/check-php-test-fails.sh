#!/bin/sh
# check-php-test-fails.sh: does the php-test component still fail a bad app
# and pass a clean one?
#
# The php-test component passes the tool's exit code through: the job runs
# the test_command after composer install, so a non-zero exit fails the job.
# This script checks that the template keeps the test command as its own
# script line (no pipe, no || true), then runs the two fixtures:
#
#   tests/fixture-app     exit 0, reports OK (the clean case)
#   tests/php-test-fails  non-zero exit, names test_must_fail
#                         (the must-fail case)
#
# It runs inside the template's image (php:8.3-cli-trixie, the template's
# default for PHP 8.3, the stack's floor), where it performs the template's
# own steps from templates/php-test/template.yml: apt-get unzip and git,
# Composer 2.10.3 from getcomposer.org with its SHA-384 verified, then for
# each fixture a copy in a temp dir, composer install
# --no-interaction --no-progress, vendor/bin/phpunit. One result line per
# case goes to stdout; a fixture's output is printed only for a case that
# went wrong. Run it with
#
#   docker run --rm -v "$(pwd):/app" -w /app php:8.3-cli-trixie \
#     sh tests/check-php-test-fails.sh
#
# Its twin, check-php-test-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/php-test/template.yml"

status=0
fail() {
  echo "check-php-test-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/php-test/template.yml"
[ -f "$ROOT/tests/fixture-app/composer.json" ] || fail "clean fixture missing: tests/fixture-app"
[ -f "$ROOT/tests/php-test-fails/composer.json" ] || fail "must-fail fixture missing: tests/php-test-fails"
[ "$status" -eq 0 ] || exit 1

# (a) the job runs the test command as its own script line, so the exit
# code is the job result: no pipe, no || true.
grep -Fxq -- '    - $[[ inputs.test_command ]]' "$TPL" \
  || fail "php-test job does not run the test command as its own script line (no pipe, no || true)"

# The php:*-cli images do not ship Composer, unzip or git, so the template
# installs them first (templates/php-test/template.yml). Do the same here,
# in a temp dir, because the repository may be bound read-only.
BOOTSTRAP=$(cat <<'EOF'
set -e
bootstrap_dir=$(mktemp -d)
trap 'rm -rf "$bootstrap_dir"' EXIT
cd "$bootstrap_dir"
apt-get update && apt-get install -y --no-install-recommends unzip git
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') !== trim(file_get_contents('https://composer.github.io/installer.sig'))) { unlink('composer-setup.php'); exit(1); }"
php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer --version=2.10.3
rm composer-setup.php
EOF
)
if ! bootstrap_log=$(sh -c "$BOOTSTRAP" 2>&1); then
  printf '%s\n' "$bootstrap_log" >&2
  echo "check-php-test-fails: the composer bootstrap failed (the template's own steps)" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run <name> <dir>: copy the fixture to a temp dir, run the template's own
# commands there, keep the log and the exit code.
run() {
  name=$1
  dir=$2
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  (cd "$work" && composer install --no-interaction --no-progress && vendor/bin/phpunit) > "$tmp/$name.log" 2>&1
  echo $?
}

# clean: the fixture's test passes and PHPUnit exits 0.
code=$(run clean tests/fixture-app)
ok=1
[ "$code" -eq 0 ] || { fail "php-test clean: exit $code, expected 0"; ok=0; }
grep -Fq "OK (" "$tmp/clean.log" || { fail "php-test clean: the output does not report OK"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "php-test clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/clean.log" >&2
fi

# must-fail: the fixture fails and names the failing test.
code=$(run mustfail tests/php-test-fails)
ok=1
[ "$code" -ne 0 ] || { fail "php-test must-fail: exit 0, expected non-zero"; ok=0; }
grep -Fq "ExampleTest::test_must_fail" "$tmp/mustfail.log" || { fail "php-test must-fail: the output does not name test_must_fail"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "php-test must-fail: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/mustfail.log" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "check-php-test-fails: ok"
fi
exit "$status"
