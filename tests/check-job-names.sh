#!/bin/sh
# check-job-names.sh: do the job-name templates take their job key from a
# job_name input?
#
# A component included twice must not merge into one job: these templates
# name the job with $[[ inputs.job_name ]] and promise a default through a
# job_name input (PREFLIGHT-14). Part A covers five templates; part B extends
# TEMPLATES below.
#
# The template is two YAML documents separated by `---`: the spec before the
# last separator, the jobs after it. Some templates start with a comment
# header, so the split happens at the last `---` line, not the first. This
# script reads the documents with awk and checks them with plain grep, so it
# needs no yq and runs in the mikefarah/yq image and on any Linux or macOS
# box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TEMPLATES="pint phpstan eslint sbom renovate proctor php-test composer-audit package-publish secret-detection a11y squire-kit portability"

status=0

fail() {
  echo "check-job-names: $1" >&2
  status=1
}

for name in $TEMPLATES; do
  tpl="$ROOT/templates/$name/template.yml"
  if [ ! -f "$tpl" ]; then
    fail "$name: no template at templates/$name/template.yml"
    continue
  fi

  # The jobs document is everything after the last `---` line.
  sep=$(grep -nE '^---[[:blank:]]*$' "$tpl" | tail -n 1 | cut -d: -f1)
  if [ -z "$sep" ]; then
    fail "$name: no '---' separator between the spec and jobs documents"
    continue
  fi
  spec=$(awk -v n="$sep" 'NR < n' "$tpl")
  jobs=$(awk -v n="$sep" 'NR > n' "$tpl")

  # The job key must be exactly $[[ inputs.job_name ]].
  if ! printf '%s\n' "$jobs" | grep -Fxq '"$[[ inputs.job_name ]]":'; then
    fail "$name: jobs document has no \"\$[[ inputs.job_name ]]\" job key"
  fi

  # The spec must declare the job_name input with a non-empty default:.
  if ! printf '%s\n' "$spec" | grep -qE '^    job_name:'; then
    fail "$name: spec does not declare a job_name input"
  else
    def=$(printf '%s\n' "$spec" | awk '
      /^    job_name:/ { in_job = 1; next }
      in_job {
        if ($0 ~ /^    [A-Za-z_][A-Za-z0-9_-]*:/) { in_job = 0; next }
        if ($0 ~ /^      default:/) {
          v = $0
          sub(/^      default:[[:space:]]*/, "", v)
          sub(/[[:space:]]*$/, "", v)
          print v
          exit
        }
      }
    ')
    if [ -z "$def" ]; then
      fail "$name: job_name input has no non-empty default"
    fi
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-job-names: ok"
fi
exit "$status"
