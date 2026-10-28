#!/bin/sh
# check-working-dir-regex.sh: does every working_dir input carry the
# relative-path regex, and does the pattern accept and reject the right
# values?
#
# working_dir lands in a cd "..." line in the job script, so a free string
# is a shell-injection hole. The GitLab input regex constrains it to a
# relative path: the leading-character rule blocks absolute paths (/etc)
# and parent references (../x), and the character class blocks spaces,
# semicolons and $(...). The pattern still allows a/../b; that is a later
# slice, so this test pins the exact regex line instead of re-deriving the
# rule.
#
# POSIX sh, no yq: grep/sed pull the regex line out of each template, and
# grep -E tests the pattern against the sample values. It runs in the
# mikefarah/yq image and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-working-dir-regex: $1" >&2
  status=1
}

# The one regex line every working_dir input must carry, exactly.
expected_regex_line="      regex: '^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$'"

for tpl in "$ROOT"/templates/*/template.yml; do
  [ -f "$tpl" ] || continue
  name=$(basename "$(dirname "$tpl")")

  # The spec document is everything before the last `---` line.
  sep=$(grep -nE '^---[[:blank:]]*$' "$tpl" | tail -n 1 | cut -d: -f1)
  if [ -z "$sep" ]; then
    fail "$name: no \`---\` separator between the spec and jobs documents"
    continue
  fi
  spec=$(awk -v n="$sep" 'NR < n' "$tpl")

  # Only templates that define a working_dir input are checked.
  if ! printf '%s\n' "$spec" | grep -qE '^    working_dir:[[:blank:]]*$'; then
    continue
  fi

  # The working_dir block: from its line to the next input or document end.
  block=$(printf '%s\n' "$spec" | awk '
    /^    working_dir:[[:blank:]]*$/ { inblock = 1; next }
    inblock {
      if (/^    [A-Za-z_]/ || /^[^ ]/) { inblock = 0; next }
      print
    }')

  # The regex line must be present and exactly the expected one.
  regex_line=$(printf '%s\n' "$block" | grep -E '^      regex:' || true)
  if [ -z "$regex_line" ]; then
    fail "$name: the working_dir input has no regex line"
    echo "check-working-dir-regex: $name: FAIL"
    continue
  fi
  if [ "$regex_line" != "$expected_regex_line" ]; then
    fail "$name: the working_dir regex line is not the expected one: $regex_line"
    echo "check-working-dir-regex: $name: FAIL"
    continue
  fi

  # Pull the pattern out of the quoted value.
  pattern=$(printf '%s\n' "$regex_line" | sed -E "s/^      regex:[[:blank:]]*'//; s/'\$//")

  before=$status

  # The default must match.
  default=$(printf '%s\n' "$block" | sed -nE 's/^      default:[[:blank:]]*//p')
  default=${default#\"}
  default=${default%\"}
  if ! printf '%s\n' "$default" | grep -qE "$pattern"; then
    fail "$name: the working_dir default does not match the regex: $default"
  fi

  # Values that must match.
  for good in web/app packages/api; do
    if ! printf '%s\n' "$good" | grep -qE "$pattern"; then
      fail "$name: $good should match the working_dir regex"
    fi
  done

  # Values that must not match.
  for bad in /etc ../x 'a;rm' '$(id)' 'a b'; do
    if printf '%s\n' "$bad" | grep -qE "$pattern"; then
      fail "$name: $bad must not match the working_dir regex"
    fi
  done

  if [ "$status" -eq "$before" ]; then
    echo "check-working-dir-regex: $name: ok"
  else
    echo "check-working-dir-regex: $name: FAIL"
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-working-dir-regex: ok"
fi
exit "$status"
