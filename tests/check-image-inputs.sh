#!/bin/sh
# check-image-inputs.sh: is every job image an input, and do the php: defaults
# name a Debian release?
#
# Two practices from BEST_PRACTICES.md, checked in one pass:
#
#   * 2.10: every job's image: is an input. A hard-coded image means the
#     component cannot move to WSU-controlled or Citadel-matching images
#     without a new major version.
#   * 4.10: a default php: tag names the Debian release (for example
#     -cli-trixie). The bare cli tag silently follows whichever Debian
#     release the image maintainers choose.
#
# The templates are YAML documents separated by `---`: the spec (inputs)
# before the last separator, the jobs after it. Some templates start with a
# comment header, so the jobs document is everything after the last `---`
# line, not the first. This script reads the documents with awk and checks
# them with plain grep/awk/sed, so it needs no yq and runs in the alpine
# image and on any Linux or macOS box.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0

fail() {
  echo "check-image-inputs: $1" >&2
  status=1
}

# Debian release names the official php images use in their tags.
debian_releases='stretch|buster|bullseye|bookworm|trixie|forky'

for tpl in "$ROOT"/templates/*/template.yml; do
  [ -f "$tpl" ] || continue
  name=$(basename "$(dirname "$tpl")")

  # The jobs document is everything after the last `---` line; the spec
  # document is everything before it.
  sep=$(grep -nE '^---[[:blank:]]*$' "$tpl" | tail -n 1 | cut -d: -f1)
  if [ -z "$sep" ]; then
    fail "$name: no `---` separator between the spec and jobs documents"
    continue
  fi
  spec=$(awk -v n="$sep" 'NR < n' "$tpl")
  jobs=$(awk -v n="$sep" 'NR > n' "$tpl")

  # 2.10: every job image: is the image input.
  image_lines=$(printf '%s\n' "$jobs" | grep -E '^  image:' || true)
  if [ -z "$image_lines" ]; then
    fail "$name: no job image: line found"
  else
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      value=$(printf '%s\n' "$line" | sed -E 's/^  image:[[:blank:]]*//')
      if [ "$value" != '$[[ inputs.image ]]' ]; then
        fail "$name: job image is not the image input: $value"
      fi
    done <<EOF
$image_lines
EOF
  fi

  # The spec must define the image input with a default.
  default=$(printf '%s\n' "$spec" | awk '
    /^    image:[[:blank:]]*$/ { inblock = 1; next }
    inblock {
      if (/^    [A-Za-z_]/ || /^[^ ]/) { inblock = 0; next }
      if (/^      default:/) { sub(/^      default:[[:blank:]]*/, ""); print; exit }
    }')
  if [ -z "$default" ]; then
    fail "$name: the image input has no default"
  else
    default=${default#\"}
    default=${default%\"}
    # 4.10: a default php: tag names the Debian release.
    case $default in
      php:*)
        tag=${default%%@*}
        tag=${tag#php:}
        if ! printf '%s\n' "$tag" | grep -qE "(^|[-])(${debian_releases})([-.]|$)"; then
          fail "$name: default php: tag does not name a Debian release: $default"
        fi
        ;;
    esac
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-image-inputs: ok"
fi
exit "$status"
