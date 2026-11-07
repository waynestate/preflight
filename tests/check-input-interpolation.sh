#!/bin/sh
# check-input-interpolation.sh: do the templates hand their inputs to the
# job's shell the way GitLab interpolates them?
#
# GitLab replaces only the $[[ inputs.name ]] form before the job runs. Any
# other mention of inputs. reaches the job's shell as literal text: $([[
# inputs.name ]]) is a command substitution that runs [[ inputs.name ]],
# which fails in POSIX sh (and prints nothing in bash), so the variable ends
# up empty and whatever depends on it never runs. This test scans every
# template for $([[ (or $( [[) and for inputs. references that are not
# inside $[[ ... ]].
#
# Plain grep and awk, so it needs no yq and runs in the mikefarah/yq image
# and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-input-interpolation: $1" >&2
  status=1
}

for tpl in "$ROOT"/templates/*/template.yml; do
  [ -f "$tpl" ] || continue
  name=${tpl#"$ROOT/templates/"}
  name=${name%/template.yml}

  # A $([[ is a command substitution running the [[ test, not an
  # interpolation. $( [[ with a space is the same mistake.
  bad=$(grep -nE '\$\(\[+\[' "$tpl" || true)
  if [ -n "$bad" ]; then
    fail "$name: shell command substitution where an interpolation belongs:"
    printf '%s\n' "$bad" | sed 's/^/  /' >&2
  fi

  # Every inputs.<name> reference must sit inside $[[ ... ]].
  bad=$(awk '
    {
      line = $0
      while (match(line, /inputs\.[A-Za-z_][A-Za-z0-9_-]*/)) {
        ref = substr(line, RSTART, RLENGTH)
        before = substr(line, 1, RSTART - 1)
        after = substr(line, RSTART + RLENGTH)
        if (before !~ /\$\[\[[ \t]*$/ || after !~ /^[ \t]*\]\]/) {
          printf "%d: %s is not inside \$[[ ... ]]: %s\n", FNR, ref, $0
        }
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$tpl")
  if [ -n "$bad" ]; then
    fail "$name: inputs. reference outside an interpolation:"
    printf '%s\n' "$bad" | sed 's/^/  /' >&2
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-input-interpolation: ok"
fi
exit "$status"
