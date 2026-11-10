#!/bin/sh
# check-dependency-cache.sh: do the components and this repository's own
# pipeline keep their dependency downloads cached?
#
# The stack's rule (2026-11-07): every dependency download is cached or
# proxied, so a busy day of pipelines never gets the runner's address rate
# limited by Docker Hub, Packagist or npm. Four practices, checked in one
# pass:
#
#   * A component whose image default comes from Docker Hub has the
#     image_prefix input, defaulting to the group's Dependency Proxy
#     (${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}), and every job image is
#     $[[ inputs.image_prefix ]]/$[[ inputs.image ]].
#   * A component whose jobs run composer install, update, require or
#     create-project, or npm ci or install, has a cache: block and points
#     the tool at it (COMPOSER_CACHE_DIR; NPM_CONFIG_CACHE, npm_config_cache
#     or --cache).
#   * Every cache: block in a component template has when: always, so a
#     failed job still saves the packages that finished downloading.
#   * In .gitlab-ci.yml, every Docker Hub job image starts with
#     ${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/, and no component include
#     passes an image that already carries the proxy (the component adds it,
#     and twice is a path Docker Hub has never heard of).
#
# Images on other registries (mcr.microsoft.com, quay.io) are left alone:
# GitLab's Dependency Proxy serves Docker Hub only.
#
# Plain grep/awk/sed, so it needs no yq and runs in the alpine image and on
# any Linux or macOS box. A cache is a preflight check for the network: it
# shows up on the day the network does not.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

PROXY='${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}'
PREFIXED='$[[ inputs.image_prefix ]]/$[[ inputs.image ]]'

status=0

fail() {
  echo "check-dependency-cache: $1" >&2
  status=1
}

# is_docker_hub REF: true when REF names a Docker Hub image, that is, when
# nothing in front of the first slash looks like a registry host.
is_docker_hub() {
  ref=${1%%@*}
  case $ref in
    */*) first=${ref%%/*} ;;
    *) return 0 ;;
  esac
  case $first in
    *.*|*:*|localhost) return 1 ;;
  esac
  return 0
}

# input_default SPEC KEY: the default of input KEY in the spec document,
# without surrounding quotes.
input_default() {
  printf '%s\n' "$1" | awk -v key="$2" '
    $0 ~ ("^    " key ":[[:blank:]]*$") { inblock = 1; next }
    inblock {
      if (/^    [A-Za-z_]/ || /^[^ ]/) { inblock = 0; next }
      if (/^      default:/) {
        sub(/^      default:[[:blank:]]*/, "")
        gsub(/^"|"$/, "")
        print
        exit
      }
    }'
}

# job_images JOBS: every job image value in a jobs document, inline
# (`image: X`) or block (`image:` then `name: X`), one per line.
job_images() {
  printf '%s\n' "$1" | awk '
    /^  image:[ \t]*$/ { block = 1; next }
    block {
      block = 0
      if ($0 ~ /^    name:/) { v = $0; sub(/^    name:[ \t]*/, "", v); print v }
      next
    }
    /^  image:[ \t]+/ { v = $0; sub(/^  image:[ \t]*/, "", v); print v }'
}

composer_pattern='(^|[[:space:](])composer[[:space:]]+(install|update|require|create-project|global[[:space:]]+require)'
npm_pattern='(^|[[:space:](])npm[[:space:]]+(ci|install)'

for tpl in "$ROOT"/templates/*/template.yml; do
  [ -f "$tpl" ] || continue
  name=$(basename "$(dirname "$tpl")")

  sep=$(grep -nE '^---[[:blank:]]*$' "$tpl" | tail -n 1 | cut -d: -f1)
  if [ -z "$sep" ]; then
    fail "$name: no --- separator between the spec and jobs documents"
    continue
  fi
  spec=$(awk -v n="$sep" 'NR < n' "$tpl")
  jobs=$(awk -v n="$sep" 'NR > n' "$tpl")

  # Docker Hub images go through image_prefix.
  default=$(input_default "$spec" image)
  if [ -n "$default" ] && is_docker_hub "$default"; then
    prefix_default=$(input_default "$spec" image_prefix)
    if [ "$prefix_default" != "$PROXY" ]; then
      fail "$name: the image default ($default) is on Docker Hub, so the image_prefix input must default to $PROXY (found '$prefix_default')"
    fi
    images=$(job_images "$jobs")
    while IFS= read -r image; do
      [ -n "$image" ] || continue
      if [ "$image" != "$PREFIXED" ]; then
        fail "$name: a Docker Hub job image must be $PREFIXED, found: $image"
      fi
    done <<EOF
$images
EOF
  fi

  # Package downloads are cached. Only code lines count: a comment that
  # mentions an install is not one.
  code=$(printf '%s\n' "$jobs" | grep -v '^[[:blank:]]*#')
  if printf '%s\n' "$code" | grep -Eq "$composer_pattern"; then
    printf '%s\n' "$jobs" | grep -Eq '^  cache:' \
      || fail "$name: runs Composer but has no cache: block"
    printf '%s\n' "$jobs" | grep -Eq '^    COMPOSER_CACHE_DIR:' \
      || fail "$name: runs Composer but does not set COMPOSER_CACHE_DIR"
  fi
  if printf '%s\n' "$code" | grep -Eq "$npm_pattern"; then
    printf '%s\n' "$jobs" | grep -Eq '^  cache:' \
      || fail "$name: runs npm but has no cache: block"
    if ! printf '%s\n' "$jobs" | grep -Eq '^    (NPM_CONFIG_CACHE|npm_config_cache):' \
      && ! printf '%s\n' "$code" | grep -Eq "$npm_pattern"'.*--cache[[:space:]]'; then
      fail "$name: runs npm but points it at no cache (NPM_CONFIG_CACHE, npm_config_cache or --cache)"
    fi
  fi

  # Every cache: block saves even when the job fails.
  if printf '%s\n' "$jobs" | grep -Eq '^  cache:'; then
    printf '%s\n' "$jobs" | awk '
      /^  cache:/ { inblock = 1; next }
      inblock && /^  [A-Za-z_]/ { inblock = 0 }
      inblock && /^    when: always/ { found = 1 }
      END { exit !found }
    ' || fail "$name: cache: block without when: always"
  fi
done

# This repository's own pipeline. Each line of the report is
# "include|VALUE" for an image passed to a component, or "job|NAME|VALUE".
CI="$ROOT/.gitlab-ci.yml"
if [ -f "$CI" ]; then
  report=$(awk '
    /^[^ \t#-]/ { top = $0; sub(/:.*$/, "", top); block = 0 }
    top == "include" {
      if ($0 ~ /^[ \t]+image:[ \t]+/) { v = $0; sub(/^[ \t]+image:[ \t]*/, "", v); print "include|" v }
      next
    }
    /^  image:[ \t]*$/ { block = 1; next }
    block {
      block = 0
      if ($0 ~ /^    name:/) { v = $0; sub(/^    name:[ \t]*/, "", v); print "job|" top "|" v }
      next
    }
    /^  image:[ \t]+/ { v = $0; sub(/^  image:[ \t]*/, "", v); print "job|" top "|" v }' "$CI")
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    kind=${line%%|*}
    rest=${line#*|}
    if [ "$kind" = include ]; then
      case $rest in
        *CI_DEPENDENCY_PROXY*)
          fail ".gitlab-ci.yml: a component include passes an image that already carries the proxy; drop it, the component's image_prefix adds it: $rest"
          ;;
      esac
      continue
    fi
    job=${rest%%|*}
    image=${rest#*|}
    image=${image#\"}
    image=${image%\"}
    case $image in
      "$PROXY"/*) continue ;;
      \$*) continue ;;
    esac
    if is_docker_hub "$image"; then
      fail ".gitlab-ci.yml: job $job pulls $image from Docker Hub; put $PROXY/ in front of it"
    fi
  done <<EOF
$report
EOF
fi

if [ "$status" -eq 0 ]; then
  echo "check-dependency-cache: ok"
fi
exit "$status"
