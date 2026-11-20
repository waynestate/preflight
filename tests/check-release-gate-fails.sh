#!/bin/sh
# check-release-gate-fails.sh: does the release-gate component still pass a
# tag whose commit the default branch already tested, and fail one it never
# saw?
#
# The release-gate job is the D-125 proof for tag pipelines: it asks the
# GitLab API, with the job token, for a successful pipeline of the tagged
# commit on the default branch, and when the token may not read pipelines
# it falls back to git: fetch the default branch and check the commit is an
# ancestor of it. This check renders the template's own script lines (its
# component.* values as stand-ins) and runs them with sh -e, the way the
# runner does, in a temp dir whose checkout is a tiny git repo with a bare
# origin, and whose curl is a fake script first on PATH that answers with
# whatever the case sets in FAKE_CURL_CODE and FAKE_CURL_BODY:
#
#   api-passes        HTTP 200, a successful pipeline exists   exit 0
#   api-empty         HTTP 200, the list is empty              non-zero, names the missing pipeline
#   fallback-on-main  HTTP 403, the commit is on main          exit 0, names the fallback and the release procedure
#   fallback-off-main HTTP 403, the commit is off main         non-zero
#
# The CI variables the script reads are set per case (CI_API_V4_URL,
# CI_PROJECT_ID, CI_JOB_TOKEN as a dummy, CI_COMMIT_SHA, CI_COMMIT_TAG,
# CI_DEFAULT_BRANCH); the dummy token must never reach the output. One
# result line per case goes to stdout; a case's output is printed only
# when it went wrong.
#
# It runs inside the template's image (composer:2.11.1, pinned by digest in
# templates/release-gate/template.yml). Run it with
#
#   docker run --rm -v "$(pwd):/app:ro" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-release-gate-fails.sh
#
# Its twin, check-release-gate-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/release-gate/template.yml"

status=0
fail() {
  echo "check-release-gate-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/release-gate/template.yml"
[ "$status" -eq 0 ] || exit 1

# The jobs document is everything after the last `---` line.
sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
[ -n "$sep" ] || { fail "no '---' separator between the spec and jobs documents"; exit 1; }
jobs=$(sed -n "$((sep + 1)),\$p" "$TPL")

# (a) the job keeps the gate honest: it may not be allowed to fail, it runs
# only on tags, it carries the full history the git fallback needs, and the
# script still asks the API with the job token and falls back to
# merge-base, with interruptible and a timeout.
printf '%s\n' "$jobs" | grep -Eq '^  allow_failure:' \
  && fail "the release-gate job has allow_failure; the gate must be able to stop the tag pipeline"
printf '%s\n' "$jobs" | grep -Fxq -- '    - if: $CI_COMMIT_TAG' \
  || fail "the release-gate job no longer runs only on tags"
printf '%s\n' "$jobs" | grep -Fxq -- '    GIT_DEPTH: "0"' \
  || fail 'the release-gate job lost GIT_DEPTH: "0"; the git fallback needs the full history'
printf '%s\n' "$jobs" | grep -Fxq -- '  interruptible: true' \
  || fail "the release-gate job lost interruptible: true"
printf '%s\n' "$jobs" | grep -Eq '^  timeout:' \
  || fail "the release-gate job lost its timeout"
printf '%s\n' "$jobs" | grep -Fq 'JOB-TOKEN: $CI_JOB_TOKEN' \
  || fail "the job no longer authenticates the API call with the job token"
printf '%s\n' "$jobs" | grep -Fq 'merge-base --is-ancestor' \
  || fail "the job lost its git fallback"

# (b) the job's script lines, in order, without the "    - " item marker.
# The gate's body is a block scalar, so a block header switches the
# extractor into block mode: the following lines lose their six-space
# indent and are kept verbatim until the block ends.
script=$(printf '%s\n' "$jobs" | awk '
  /^  script:[ \t]*$/ { inblock = 1; next }
  !inblock { next }
  /^  [A-Za-z_"]/ { exit }
  /^    - / {
    line = $0
    sub(/^    - /, "", line)
    if (line ~ /^[|>][-+]?[ \t]*$/) { blockmode = 1; next }
    blockmode = 0
    print line
    next
  }
  blockmode {
    if ($0 ~ /^[ \t]*$/) { print ""; next }
    if ($0 ~ /^      /) { sub(/^      /, ""); print; next }
    blockmode = 0
    next
  }
')
[ -n "$script" ] || { fail "no script lines extracted from the template"; exit 1; }

# The component.* values are stand-ins: they only feed the banner echo.
script=$(printf '%s\n' "$script" | sed -e 's|\$\[\[ component\.[a-z]* ]]|check|g')
if printf '%s\n' "$script" | grep -Fq -- '$[['; then
  fail "the rendered script still holds an interpolation the check does not fill: $(printf '%s\n' "$script" | grep -F -- '$[[' | head -n 1)"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

# The fake curl, first on PATH: it honors -o FILE, writes FAKE_CURL_BODY to
# the file and prints FAKE_CURL_CODE, standing in for the GitLab API answer.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'FAKE'
#!/bin/sh
out=
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$out" ] || exit 2
printf '%s' "${FAKE_CURL_BODY:-}" > "$out"
printf '%s' "${FAKE_CURL_CODE:-200}"
FAKE
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"

# repo <name> <on-main|off-main>: build $tmp/<name>/origin.git, a bare
# origin whose main holds the seed commit, and $tmp/<name>/work, a checkout
# with origin set. Writes the sha the case should tag to $tmp/<name>/sha:
# on-main tags a commit origin/main already holds, with main moved on past
# it; off-main tags a commit on a side branch that never reached origin.
# The git identity lives in the temp repos only.
repo() {
  name=$1
  kind=$2
  base="$tmp/$name"
  (
    set -e
    mkdir -p "$base/work"
    git init -q --bare "$base/origin.git"
    git init -q "$base/work"
    git -C "$base/work" symbolic-ref HEAD refs/heads/main
    git -C "$base/work" config user.email release-gate-check@example.com
    git -C "$base/work" config user.name "Release Gate Check"
    printf 'seed\n' > "$base/work/seed.txt"
    git -C "$base/work" add seed.txt
    git -C "$base/work" commit -q -m seed
    if [ "$kind" = on-main ]; then
      printf 'more\n' > "$base/work/more.txt"
      git -C "$base/work" add more.txt
      git -C "$base/work" commit -q -m more
      git -C "$base/work" rev-parse HEAD~1 > "$base/sha"
    fi
    git -C "$base/work" remote add origin "$base/origin.git"
    git -C "$base/work" push -q origin HEAD:refs/heads/main
    if [ "$kind" = off-main ]; then
      git -C "$base/work" checkout -q --detach
      printf 'side\n' > "$base/work/side.txt"
      git -C "$base/work" add side.txt
      git -C "$base/work" commit -q -m side
      git -C "$base/work" rev-parse HEAD > "$base/sha"
    fi
  )
}

# run <name> <code> <body> <kind>: build the case's git fixture, run the
# rendered script with sh -e from the work dir, with the CI variables the
# gate reads set and the fake curl answering the case's code and body.
# Keeps the log and the exit code.
run() {
  name=$1
  code=$2
  body=$3
  kind=$4
  repo "$name" "$kind"
  sha=$(cat "$tmp/$name/sha" 2>/dev/null) || sha=
  if [ -z "$sha" ]; then
    echo "could not build the git fixture for $name" > "$tmp/$name.log"
    echo 99
    return
  fi
  printf '%s\n' "$script" > "$tmp/$name.sh"
  (
    cd "$tmp/$name/work"
    export CI_API_V4_URL="https://gitlab.example/api/v4"
    export CI_PROJECT_ID="1234"
    export CI_JOB_TOKEN="fake-job-token-$name"
    export CI_COMMIT_SHA="$sha"
    export CI_COMMIT_TAG="v0.12.0"
    export CI_DEFAULT_BRANCH="main"
    export FAKE_CURL_CODE="$code"
    export FAKE_CURL_BODY="$body"
    sh -e "$tmp/$name.sh"
  ) > "$tmp/$name.log" 2>&1
  echo $?
}

# expect <name> <code> <body> <kind> <zero|nonzero> [pattern]: one case. A
# must-fail case also needs the pattern (an extended regex) in its output,
# so a crashed gate never passes for the finding. The dummy job token must
# never reach the output.
expect() {
  name=$1
  code=$2
  body=$3
  kind=$4
  want=$5
  pattern=${6:-}
  label="release-gate $name"
  rc=$(run "$name" "$code" "$body" "$kind")
  ok=1
  if [ "$want" = zero ]; then
    [ "$rc" -eq 0 ] || { fail "$label: exit $rc, expected 0"; ok=0; }
  else
    [ "$rc" -ne 0 ] || { fail "$label: exit 0, expected non-zero"; ok=0; }
  fi
  if [ -n "$pattern" ] && ! grep -Eq -- "$pattern" "$tmp/$name.log"; then
    fail "$label: the output does not name $pattern"
    ok=0
  fi
  if grep -qF -- "fake-job-token-$name" "$tmp/$name.log"; then
    fail "$label: the job token leaked into the output"
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "$label: exit $rc (expected)"
  else
    sed 's/^/  | /' "$tmp/$name.log" >&2
  fi
}

# api-passes: the API answers 200 with a successful pipeline of this commit
# on the default branch, so the gate passes.
expect api-passes 200 '[{"id": 42, "web_url": "https://gitlab.example/group/project/-/pipelines/42"}]' on-main zero 'already passed this commit'

# api-empty: the API answers 200 with an empty list: the commit was never
# tested on the default branch, so the gate must fail and name the finding.
expect api-empty 200 '[]' on-main nonzero 'no successful pipeline'

# fallback-on-main: the token cannot list pipelines (403), so the gate
# falls back to git; the commit is on the default branch, so it passes,
# with the caveat that green-ness rests on the release procedure.
expect fallback-on-main 403 '' on-main zero 'job token cannot list pipelines.*rests on the release procedure'

# fallback-off-main: the token cannot list pipelines and the commit is not
# on the default branch, so the gate must fail.
expect fallback-off-main 403 '' off-main nonzero 'is not on main'

if [ "$status" -eq 0 ]; then
  echo "check-release-gate-fails: ok"
fi
exit "$status"
