#!/bin/sh
# check-path-input-regex.sh: do the path-like inputs that reach a shell line
# carry their input regex, and do the patterns accept and reject the right
# values?
#
# phpstan's config and memory_limit, pint's config and sbom's output land in
# unquoted or free positions of a job script line, so a free string is a
# shell-injection hole. The GitLab input regex constrains the path inputs to
# a relative path: the leading-character rule blocks absolute paths (/etc)
# and parent references (../x), and the character class blocks spaces,
# semicolons and $(...). memory_limit takes a PHP size such as 1G, 512M or
# -1. A value outside the regex stops the pipeline at creation. The pattern
# still allows a/../b; that is a later slice (same as working_dir), so this
# test pins the exact regex lines instead of re-deriving the rule. The
# proctor check_path input is checked here too: the job cds into it after
# the install, so it must stay a relative path or be empty. The
# secret-detection config_path input is checked here too: the job hands it
# to gitleaks --config, so it must stay a relative path or be empty, with
# one leading dot allowed for .gitleaks.toml.
#
# test_command, proctor_command and eslint_args stay free on purpose: they
# are arbitrary commands by design.
#
# POSIX sh, no yq: grep/sed pull the regex line out of each template, and
# grep -E tests the pattern against the sample values. It runs in the
# mikefarah/yq image and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-path-input-regex: $1" >&2
  status=1
}

# The expected regex lines, exactly as they must appear in the templates.
path_regex_line="      regex: '^[A-Za-z0-9_-][A-Za-z0-9._/-]*$'"
memory_regex_line="      regex: '^(-1|[0-9]+[KkMmGg]?)$'"
check_path_regex_line="      regex: '^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)?$'"
config_path_regex_line="      regex: '^(\.?[A-Za-z0-9_-][A-Za-z0-9._/-]*)?$'"

# check_input <template> <input name> <expected regex line>
check_input() {
  tpl=$1
  name=$2
  expected=$3

  # The spec document is everything before the last `---` line.
  sep=$(grep -nE '^---[[:blank:]]*$' "$tpl" | tail -n 1 | cut -d: -f1)
  if [ -z "$sep" ]; then
    fail "$name: no \`---\` separator between the spec and jobs documents"
    return
  fi
  spec=$(awk -v n="$sep" 'NR < n' "$tpl")

  # The input block: from its line to the next input or document end.
  block=$(printf '%s\n' "$spec" | awk -v key="$name" '
    index($0, "    " key ":") == 1 { inblock = 1; next }
    inblock {
      if (/^    [A-Za-z_]/ || /^[^ ]/) { inblock = 0; next }
      print
    }')
  if [ -z "$block" ]; then
    fail "$name: the $name input is not defined in the spec"
    return
  fi

  # The regex line must be present and exactly the expected one.
  regex_line=$(printf '%s\n' "$block" | grep -E '^      regex:' || true)
  if [ -z "$regex_line" ]; then
    fail "$name: the $name input has no regex line"
    return
  fi
  if [ "$regex_line" != "$expected" ]; then
    fail "$name: the $name regex line is not the expected one: $regex_line"
    return
  fi

  # Pull the pattern out of the quoted value.
  pattern=$(printf '%s\n' "$regex_line" | sed -E "s/^      regex:[[:blank:]]*'//; s/'\$//")

  # The default must match.
  default=$(printf '%s\n' "$block" | sed -nE 's/^      default:[[:blank:]]*//p')
  default=${default#\"}
  default=${default%\"}
  if ! printf '%s\n' "$default" | grep -qE "$pattern"; then
    fail "$name: the $name default does not match the regex: $default"
  fi
}

for tpl in "$ROOT"/templates/*/template.yml; do
  [ -f "$tpl" ] || continue
  comp=$(basename "$(dirname "$tpl")")

  case $comp in
    phpstan)
      check_input "$tpl" config "$path_regex_line"
      check_input "$tpl" memory_limit "$memory_regex_line"
      ;;
    pint)
      check_input "$tpl" config "$path_regex_line"
      ;;
    proctor)
      check_input "$tpl" check_path "$check_path_regex_line"
      ;;
    sbom)
      check_input "$tpl" output "$path_regex_line"
      ;;
    secret-detection)
      check_input "$tpl" config_path "$config_path_regex_line"
      ;;
  esac
done

# The path pattern accepts the samples.
path_pattern='^[A-Za-z0-9_-][A-Za-z0-9._/-]*$'
for good in phpstan.neon config/phpstan.neon sbom.cdx.json a_b-c/d.json; do
  if ! printf '%s\n' "$good" | grep -qE "$path_pattern"; then
    fail "path regex: $good should match"
  fi
done

# The path pattern rejects the samples.
for bad in /etc/passwd ../x .hidden 'a b' 'a;b' '$(id)'; do
  if printf '%s\n' "$bad" | grep -qE "$path_pattern"; then
    fail "path regex: $bad must not match"
  fi
done

# The check_path pattern accepts the samples.
check_path_pattern='^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)?$'
for good in . deploy a_b-c/d tests/fixture-app ''; do
  if ! printf '%s\n' "$good" | grep -qE "$check_path_pattern"; then
    fail "check_path regex: $good should match"
  fi
done

# The check_path pattern rejects the samples.
for bad in /etc ../x .. .hidden 'a b' 'a;b' '$(id)' 'deploy/..;id'; do
  if printf '%s\n' "$bad" | grep -qE "$check_path_pattern"; then
    fail "check_path regex: $bad must not match"
  fi
done

# The config_path pattern accepts the samples.
config_path_pattern='^(\.?[A-Za-z0-9_-][A-Za-z0-9._/-]*)?$'
for good in .gitleaks.toml gitleaks.toml config/gitleaks.toml .config/gitleaks.toml ''; do
  if ! printf '%s\n' "$good" | grep -qE "$config_path_pattern"; then
    fail "config_path regex: $good should match"
  fi
done

# The config_path pattern rejects the samples.
for bad in /etc/gitleaks.toml ../gitleaks.toml ..gitleaks.toml 'a b.toml' 'x;y' '$(id)'; do
  if printf '%s\n' "$bad" | grep -qE "$config_path_pattern"; then
    fail "config_path regex: $bad must not match"
  fi
done

# The memory_limit pattern accepts the samples.
memory_pattern='^(-1|[0-9]+[KkMmGg]?)$'
for good in 1G 512M -1 2048; do
  if ! printf '%s\n' "$good" | grep -qE "$memory_pattern"; then
    fail "memory_limit regex: $good should match"
  fi
done

# The memory_limit pattern rejects the samples.
for bad in '1G;id' G '1 G' ''; do
  if printf '%s\n' "$bad" | grep -qE "$memory_pattern"; then
    fail "memory_limit regex: $bad must not match"
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-path-input-regex: ok"
fi
exit "$status"
