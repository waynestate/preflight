#!/bin/sh
# check-squire-kit.sh: does the squire-kit component still check the kit the
# way its docs promise?
#
# templates/squire-kit/template.yml installs the Squire release a kit
# records and runs `squire init --check` on the kit folder. This test reads
# the template as text and fails when a promise breaks:
#
#   * the job checks the folder in working_dir and fails on drift, with
#     Squire's exit codes (0 match, 1 drift, 2 the check could not run);
#   * the version comes from .squire.json unless squire_version is set, and
#     is a released x.y.z before it reaches Composer;
#   * Composer installs Squire outside the project with --no-dev and
#     --no-scripts, so nothing from the project or Squire's dev tools runs;
#   * squire_version only takes an empty value or x.y.z, and allow_failure
#     reaches the job as a real boolean, false by default;
#   * Preflight's own pipeline runs the component on the fixture kit in
#     tests/squire-kit-fixture, which records a released Squire.
#
# POSIX sh, grep, sed and awk; no yq. It runs in the mikefarah/yq image and
# on any Linux or macOS box. Its twin, check-squire-kit.ps1, does the same on
# Windows. Preflight's own pipeline runs the job itself on the fixture kit.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TPL="$ROOT/templates/squire-kit/template.yml"
FIXTURE="$ROOT/tests/squire-kit-fixture"
status=0

fail() {
  echo "check-squire-kit: $1" >&2
  status=1
}

if [ ! -f "$TPL" ]; then
  echo "check-squire-kit: missing templates/squire-kit/template.yml" >&2
  exit 1
fi

sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
if [ -z "$sep" ]; then
  echo "check-squire-kit: no '---' separator between the spec and jobs documents" >&2
  exit 1
fi
spec=$(awk -v n="$sep" 'NR < n' "$TPL")
jobs=$(awk -v n="$sep" 'NR > n' "$TPL")

# has_line <document> <exact line> <message>
has_line() {
  if ! printf '%s\n' "$1" | grep -qxF -- "$2"; then
    fail "$3"
  fi
}

# The job: the kit folder, the version, the install and the check.
has_line "$jobs" '    - cd "$[[ inputs.working_dir ]]"' "the job does not cd into working_dir"
has_line "$jobs" '  allow_failure: $[[ inputs.allow_failure ]]' "allow_failure is not interpolated as a bare boolean"
has_line "$jobs" '      if [ ! -f .squire.json ]; then' "the job does not stop when the folder has no .squire.json"
has_line "$jobs" '      version="$[[ inputs.squire_version ]]"' "the job does not take squire_version first"
has_line "$jobs" "        version=\$(php -r '\$m = json_decode((string) file_get_contents(\".squire.json\"), true); echo is_array(\$m) && is_string(\$m[\"version\"] ?? null) ? \$m[\"version\"] : \"\";')" "the job does not read the recorded version from .squire.json"
has_line "$jobs" "      if ! printf '%s\\n' \"\$version\" | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+\$'; then" "the job does not insist on a released x.y.z version"
has_line "$jobs" '      if ! composer create-project --no-dev --no-interaction --no-progress --no-scripts --quiet waynestate/squire "$squire_home/squire" "$version"; then' "the job does not install Squire with --no-dev and --no-scripts outside the project"
has_line "$jobs" '      squire_home=$(mktemp -d)' "the job does not install Squire into a temporary folder"
has_line "$jobs" '      php "$squire_home/squire/bin/squire" init --check --path=. || status=$?' "the job does not run squire init --check on the kit folder"
has_line "$jobs" '      exit "$status"' "the job does not exit with squire init --check's code"
if [ "$(printf '%s\n' "$jobs" | grep -c 'exit 2$')" -ne 3 ]; then
  fail "the job must stop with exit 2 when there is no .squire.json, no released version, or no such Squire"
fi
# The job only checks: every run of the Squire it installed is init --check.
if printf '%s\n' "$jobs" | grep -F '$squire_home/squire/bin/squire' | grep -qv -- ' init --check '; then
  fail "the job runs a squire command other than init --check"
fi

# squire_version: empty or x.y.z only, and nothing else.
pattern='^([0-9]+\.[0-9]+\.[0-9]+)?$'
has_line "$spec" "      regex: '$pattern'" "the squire_version input does not carry its regex"
for good in '' 0.5.0 10.20.30; do
  if ! printf '%s\n' "$good" | grep -qE "$pattern"; then
    fail "squire_version regex: '$good' should match"
  fi
done
for bad in 0.5 v0.5.0 dev-main '0.5.0; id' '$(id)' '0.5.0 0.4.0'; do
  if printf '%s\n' "$bad" | grep -qE "$pattern"; then
    fail "squire_version regex: '$bad' must not match"
  fi
done

# allow_failure: a boolean, false by default.
if ! printf '%s\n' "$spec" | awk '
  /^    allow_failure:/ { inBlock = 1; next }
  inBlock && /^    [A-Za-z_]/ { inBlock = 0 }
  inBlock && /^      type: boolean/ { t = 1 }
  inBlock && /^      default: false/ { d = 1 }
  END { exit (t && d) ? 0 : 1 }
'; then
  fail "the allow_failure input must be a boolean that defaults to false"
fi

# The fixture kit and Preflight's own include of it.
if [ ! -f "$FIXTURE/.squire.json" ]; then
  fail "tests/squire-kit-fixture/.squire.json is missing"
elif ! grep -qE '"version": "[0-9]+\.[0-9]+\.[0-9]+"' "$FIXTURE/.squire.json"; then
  fail "tests/squire-kit-fixture/.squire.json does not record a released Squire version"
fi
if ! awk '
  index($0, "/squire-kit@$CI_COMMIT_SHA") { key = NR }
  key > 0 && NR > key && NR - key <= 3 && index($0, "working_dir: tests/squire-kit-fixture") { found = 1 }
  END { exit found ? 0 : 1 }
' "$ROOT/.gitlab-ci.yml"; then
  fail ".gitlab-ci.yml does not run the squire-kit component on tests/squire-kit-fixture"
fi

if [ "$status" -eq 0 ]; then
  echo "check-squire-kit: ok"
fi
exit "$status"
