#!/bin/sh
# check-composer-floor.sh: do the php-test and proctor templates hold the
# same composer_version regex, and does that pattern keep out the Composer
# versions below the stack's floor?
#
# Both components install the Composer named by composer_version (default
# 2.11.1). The stack's floor is 2.9.6 (BEST_PRACTICES 4.6 and 4.9): a
# Composer from before the 2026 security fixes must be refused at pipeline
# creation, not discovered at install time. The pattern accepts 2.9.6 to
# 2.9.x and 2.10.0 and later, and refuses 2.9.5, 2.8.x, 2.0.0 and 3.x.
#
# POSIX sh, no yq: sed pulls the regex line out of each template, and
# grep -E tests the pattern against the sample values. It runs in the
# mikefarah/yq image and on any Linux or macOS box.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-composer-floor: $1" >&2
  status=1
}

# The composer_version regex of one template: the value of the regex: line
# inside its input block, with the single quotes stripped.
pattern_of() {
  tpl=$1
  name=$2

  # The spec document is everything before the last `---` line.
  sep=$(grep -nE '^---[[:blank:]]*$' "$tpl" | tail -n 1 | cut -d: -f1)
  if [ -z "$sep" ]; then
    fail "$name: no \`---\` separator between the spec and jobs documents"
    return 1
  fi
  spec=$(awk -v n="$sep" 'NR < n' "$tpl")

  # The composer_version block: from its line to the next input or document end.
  block=$(printf '%s\n' "$spec" | awk '
    /^    composer_version:[[:blank:]]*$/ { inblock = 1; next }
    inblock {
      if (/^    [A-Za-z_]/ || /^[^ ]/) { inblock = 0; next }
      print
    }')

  # The regex line must be present.
  regex_line=$(printf '%s\n' "$block" | grep -E '^      regex:' || true)
  if [ -z "$regex_line" ]; then
    fail "$name: the composer_version input has no regex line"
    return 1
  fi

  # Pull the pattern out of the quoted value.
  printf '%s\n' "$regex_line" | sed -E "s/^      regex:[[:blank:]]*'//; s/'\$//"
}

php_test_pattern=$(pattern_of "$ROOT/templates/php-test/template.yml" "php-test") || exit 1
proctor_pattern=$(pattern_of "$ROOT/templates/proctor/template.yml" "proctor") || exit 1

if [ "$php_test_pattern" != "$proctor_pattern" ]; then
  fail "the composer_version regex differs between the templates: php-test '$php_test_pattern', proctor '$proctor_pattern'"
  exit 1
fi

for good in 2.9.6 2.9.10 2.10.3 2.11.1 2.20.0; do
  if ! printf '%s\n' "$good" | grep -Eq "$php_test_pattern"; then
    fail "$good should match the composer_version regex"
  fi
done

for bad in 2.9.5 2.8.12 2.0.0 3.0.0 2.10 v2.10.3; do
  if printf '%s\n' "$bad" | grep -Eq "$php_test_pattern"; then
    fail "$bad must not match the composer_version regex"
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-composer-floor: ok"
fi
exit "$status"
