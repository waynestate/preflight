#!/bin/sh
# check-php-matrix.sh: does php-test keep its parallel: matrix wiring?
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
# the second. This script reads the documents with awk and checks them with
# plain grep/awk/sed, so it needs no yq and runs in the alpine image and on
# any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TPL="$ROOT/templates/php-test/template.yml"

if [ ! -f "$TPL" ]; then
  echo "templates/php-test/template.yml not found at $TPL" >&2
  exit 1
fi

status=0

fail() {
  echo "check-php-matrix: $1" >&2
  status=1
}

# The jobs document is everything after the last `---` line; the spec
# document is everything before it.
sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
if [ -z "$sep" ]; then
  fail "no `---` separator between the spec and jobs documents"
  exit 1
fi
spec=$(awk -v n="$sep" 'NR < n' "$TPL")
jobs=$(awk -v n="$sep" 'NR > n' "$TPL")

# The matrix block: three consecutive lines in the jobs document. Each
# line is checked on its own so the missing piece is named, then the three
# are required to sit next to each other.
if ! printf '%s\n' "$jobs" | grep -Fxq -- '  parallel:'; then
  fail "php-test job has no parallel: line"
fi
if ! printf '%s\n' "$jobs" | grep -Fxq -- '    matrix:'; then
  fail "php-test job has no matrix: line"
fi
if ! printf '%s\n' "$jobs" | grep -Fxq -- '      - PHP_VERSION: $[[ inputs.php_versions ]]'; then
  fail "php-test matrix does not feed the php_versions input"
fi
if ! printf '%s\n' "$jobs" | awk '
  $0 == "  parallel:" { p = 1; next }
  p && $0 == "    matrix:" { m = 1; next }
  m && $0 == "      - PHP_VERSION: $[[ inputs.php_versions ]]" { found = 1; exit }
  { p = 0; m = 0 }
  END { exit !found }'; then
  fail "the parallel:, matrix: and PHP_VERSION lines are not consecutive"
fi

# The spec must declare php_versions as an array with a non-empty default
# list. The block runs from the input key to the next four-space key.
block=$(printf '%s\n' "$spec" | awk '
  /^    php_versions:[[:blank:]]*$/ { inblock = 1; next }
  inblock {
    if (/^    [A-Za-z_]/ || /^[^ ]/) { inblock = 0; next }
    print
  }')
if [ -z "$block" ]; then
  fail "the spec does not declare the php_versions input"
else
  if ! printf '%s\n' "$block" | grep -Eq '^      type:[[:blank:]]*array[[:blank:]]*$'; then
    fail "the php_versions input is not type: array"
  fi
  default=$(printf '%s\n' "$block" | sed -nE 's/^      default:[[:blank:]]*//p')
  if [ -z "$default" ]; then
    fail "the php_versions input has no default: list"
  else
    compact=$(printf '%s' "$default" | tr -d '[:space:]')
    if [ "$compact" = "[]" ]; then
      fail "the php_versions default: list is empty"
    fi
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "check-php-matrix: ok"
fi
exit "$status"
