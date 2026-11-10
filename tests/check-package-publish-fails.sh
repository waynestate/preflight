#!/bin/sh
# check-package-publish-fails.sh: do the package-publish component's
# offline guards still stop a bad release?
#
# The package-publish component checks the tag and the package name before
# it touches the registry: a tag that is not a semantic version and a
# project root without a composer.json must both fail the job. This script
# checks that the template keeps those guards (the semver grep -Eq line,
# the "is not a semantic version" message with its exit 1, and the
# "composer.json not found" message), then extracts the template's first
# two script blocks (the tag guard and the composer.json guard; they hold
# no $[[ inputs ]] and so run as plain sh) and performs them on copies of
# the fixtures in a temp dir:
#
#   tests/package-publish-badtag, CI_COMMIT_TAG=not-a-version
#       exit 1, the output names "is not a semantic version"
#       (the must-fail case)
#   tests/package-publish-nocomposer, CI_COMMIT_TAG=1.2.3
#       exit 1, the output names "composer.json not found"
#       (the must-fail case)
#   tests/package-publish-badtag, CI_COMMIT_TAG=v1.2.3
#       exit 0 (the clean case)
#
# It runs inside the template's image (composer:2.11.1, pinned by digest in
# templates/package-publish/template.yml), which ships the php the name
# guard needs, plus curl. Then it runs the template's whole script, with
# its two inputs filled in, against a fake registry (php -S on 127.0.0.1)
# for the moved-version path: see (c) below for the six cases. Nothing
# leaves the container. One result line per case goes to stdout; a
# fixture's output is printed only for a case that went wrong.
# Run it with
#
#   docker run --rm -v "$(pwd):/app" -w /app \
#     composer:2.11.1@sha256:8de2184c6de224f4689e8f80ed5f5edaf0030b6b8b7839a22a2bcb6722ac87d0 \
#     sh tests/check-package-publish-fails.sh
#
# Its twin, check-package-publish-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/package-publish/template.yml"

status=0
fail() {
  echo "check-package-publish-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/package-publish/template.yml"
[ -f "$ROOT/tests/package-publish-badtag/composer.json" ] || fail "fixture missing: tests/package-publish-badtag"
[ -f "$ROOT/tests/package-publish-nocomposer/README.md" ] || fail "fixture missing: tests/package-publish-nocomposer"
[ "$status" -eq 0 ] || exit 1

# (a) the template keeps the offline guards: the semver grep -Eq line, the
# two failure messages, and an exit 1 right after the semver message.
want_semver=$(cat <<'EOF'
      if ! printf '%s\n' "$tag" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'; then
EOF
)
grep -Fxq -- "$want_semver" "$TPL" \
  || fail "the template dropped the semver guard's grep -Eq line"
msg_line=$(grep -nF -- 'is not a semantic version' "$TPL" | head -n 1 | cut -d: -f1)
if [ -z "$msg_line" ]; then
  fail "the template dropped the semver guard's message"
else
  [ "$(sed -n "$((msg_line + 1))p" "$TPL")" = "        exit 1" ] \
    || fail "the semver guard no longer exits 1 after its message"
fi
grep -Fq -- 'composer.json not found in the project root.' "$TPL" \
  || fail "the template dropped the composer.json guard's message"

# (b) the jobs document is everything after the last `---` line; its first
# two `|` script blocks are the tag guard and the composer.json guard.
# Strip their six-space block indent so they run as plain sh.
sep=$(grep -nE '^---[[:blank:]]*$' "$TPL" | tail -n 1 | cut -d: -f1)
[ -n "$sep" ] || { fail "no '---' separator between the spec and jobs documents"; exit 1; }
guards=$(awk -v n="$sep" '
  NR > n && /^    - \|$/ { blocks++; if (blocks > 2) exit }
  NR > n && blocks >= 1 && blocks <= 2 {
    if ($0 ~ /^    - /) next
    if ($0 ~ /^  [A-Za-z"]/) exit
    line = $0
    sub(/^      /, "", line)
    print line
  }
' "$TPL")
[ -n "$guards" ] || { fail "no script blocks extracted from the template"; exit 1; }
printf '%s\n' "$guards" | grep -Fq -- 'is not a semantic version' \
  || { fail "the extracted guards lost the tag guard"; exit 1; }
printf '%s\n' "$guards" | grep -Fq -- 'composer.json not found' \
  || { fail "the extracted guards lost the composer.json guard"; exit 1; }
if printf '%s\n' "$guards" | grep -Fq -- '$[['; then
  fail "the extracted guards hold an input interpolation; they no longer run as plain sh"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$guards" > "$tmp/guards.sh"

# run <name> <dir> <tag>: copy the fixture to a temp dir, run the
# template's own guards there, keep the log and the exit code.
run() {
  name=$1
  dir=$2
  tag=$3
  work="$tmp/$name"
  cp -R "$ROOT/$dir" "$work"
  (cd "$work" && CI_COMMIT_TAG="$tag" sh "$tmp/guards.sh") > "$tmp/$name.log" 2>&1
  echo $?
}

# must-fail: a tag that is not a semantic version stops the release.
code=$(run badtag tests/package-publish-badtag not-a-version)
ok=1
[ "$code" -ne 0 ] || { fail "package-publish badtag: exit 0, expected non-zero"; ok=0; }
grep -Fq "is not a semantic version" "$tmp/badtag.log" || { fail "package-publish badtag: the output does not name the semver guard"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "package-publish badtag: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/badtag.log" >&2
fi

# must-fail: a project root without a composer.json stops the release.
code=$(run nocomposer tests/package-publish-nocomposer 1.2.3)
ok=1
[ "$code" -ne 0 ] || { fail "package-publish nocomposer: exit 0, expected non-zero"; ok=0; }
grep -Fq "composer.json not found in the project root." "$tmp/nocomposer.log" || { fail "package-publish nocomposer: the output does not name the composer.json guard"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "package-publish nocomposer: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/nocomposer.log" >&2
fi

# clean: a semantic tag and a usable composer.json pass the offline guards.
code=$(run clean tests/package-publish-badtag v1.2.3)
ok=1
[ "$code" -eq 0 ] || { fail "package-publish clean: exit $code, expected 0"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "package-publish clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/clean.log" >&2
fi

# (c) the registry path, against a fake registry. GitLab overwrites a
# Composer version quietly when the same tag is published again from another
# commit, so the job reads the registry first and refuses a moved version.
# The whole jobs script (every `|` block, the version echo line left out)
# runs here with its two inputs filled in, against `php -S` serving the
# shapes GitLab's Composer API documents: the group index with
# "packages": [] and a metadata-url template, and the p2 file keyed by
# version, each version carrying source.reference (the commit). A POST to
# the publish endpoint is logged, never forwarded anywhere.
#
#   moved     1.2.3 is published from another commit: exit 1, no POST
#   moved-v2  the same, in Composer 2's plain list form: exit 1, no POST
#   same      1.2.3 is published from this commit: exit 0, no POST
#   new       only 1.2.2 is published: exit 0, one POST
#   unborn    the package has no p2 file yet (404): exit 0, one POST
#   down      the index answers 500: exit 1, no POST
all_blocks=$(awk -v n="$sep" '
  NR > n && /^    - \|$/ { inblock = 1; next }
  NR > n && /^    - / { inblock = 0; next }
  NR > n && inblock {
    if ($0 ~ /^  [A-Za-z"]/) exit
    line = $0
    sub(/^      /, "", line)
    print line
  }
' "$TPL")
printf '%s\n' "$all_blocks" | grep -Fq -- 'refusing to overwrite it.' \
  || { fail "the template dropped the moved-version refusal"; exit 1; }
printf '%s\n' "$all_blocks" \
  | sed -e 's/\$\[\[ inputs\.read_token_variable \]\]/PREFLIGHT_FAKE_READ_TOKEN/' \
        -e 's/\$\[\[ inputs\.group_id \]\]/42/' > "$tmp/job.sh"
if grep -Fq -- '$[[' "$tmp/job.sh"; then
  fail "the jobs script holds an input interpolation this check does not fill in"
  exit 1
fi

mkdir -p "$tmp/registry"
cat > "$tmp/registry/router.php" <<'PHP'
<?php
// A fake GitLab Composer registry for one scenario at a time.
$dir = __DIR__;
$scenario = trim((string) @file_get_contents($dir . '/scenario'));
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];
$moved = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
$here = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
$send = function (int $code, $body = null): void {
    http_response_code($code);
    header('Content-Type: application/json');
    if ($body !== null) {
        echo json_encode($body, JSON_UNESCAPED_SLASHES);
    }
};
if ($method === 'POST' && $path === '/api/v4/projects/7/packages/composer') {
    file_put_contents($dir . '/posts.log', file_get_contents('php://input') . "\n", FILE_APPEND);
    $send(201, ['message' => '201 Created']);
    return true;
}
if ($method === 'GET' && $path === '/api/v4/group/42/-/packages/composer/packages.json') {
    if ($scenario === 'down') {
        $send(500, ['message' => '500 Internal Server Error']);
        return true;
    }
    $send(200, ['packages' => [], 'metadata-url' => '/api/v4/group/42/-/packages/composer/p2/%package%.json']);
    return true;
}
if ($method === 'GET' && $path === '/api/v4/group/42/-/packages/composer/p2/acme/demo.json') {
    $version = fn (string $v, string $ref): array => ['name' => 'acme/demo', 'version' => $v, 'source' => ['type' => 'git', 'url' => 'https://example.invalid/acme/demo.git', 'reference' => $ref], 'dist' => ['type' => 'zip', 'url' => 'https://example.invalid/acme/demo.zip', 'reference' => $ref]];
    switch ($scenario) {
        case 'moved':
            $send(200, ['packages' => ['acme/demo' => ['1.2.2' => $version('1.2.2', $moved), '1.2.3' => $version('1.2.3', $moved)]]]);
            break;
        case 'moved-v2':
            $send(200, ['packages' => ['acme/demo' => [$version('v1.2.3', $moved), $version('1.2.2', $moved)]]]);
            break;
        case 'same':
            $send(200, ['packages' => ['acme/demo' => ['1.2.3' => $version('1.2.3', $here)]]]);
            break;
        case 'new':
            $send(200, ['packages' => ['acme/demo' => ['1.2.2' => $version('1.2.2', $moved)]]]);
            break;
        default:
            $send(404, ['message' => '404 Not Found']);
    }
    return true;
}
$send(404, ['message' => '404 Not Found']);
return true;
PHP

port=18573
php -S "127.0.0.1:$port" "$tmp/registry/router.php" > "$tmp/registry/server.log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null; rm -rf "$tmp"' EXIT
i=0
until curl --silent --output /dev/null "http://127.0.0.1:$port/"; do
  i=$((i + 1))
  if [ "$i" -gt 50 ]; then
    fail "the fake registry did not start"
    exit 1
  fi
  sleep 0.1
done

# registry <scenario> <expected exit: 0 or 1> <expected POSTs> <text the output must name>
registry() {
  scenario=$1
  want_code=$2
  want_posts=$3
  want_text=$4
  printf '%s\n' "$scenario" > "$tmp/registry/scenario"
  : > "$tmp/registry/posts.log"
  work="$tmp/reg-$scenario"
  cp -R "$ROOT/tests/package-publish-badtag" "$work"
  (
    cd "$work" &&
      CI_COMMIT_TAG=v1.2.3 \
      CI_COMMIT_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
      CI_API_V4_URL="http://127.0.0.1:$port/api/v4" \
      CI_PROJECT_ID=7 \
      CI_JOB_TOKEN=fake-job-token \
      PREFLIGHT_FAKE_READ_TOKEN=fake-read-token \
      sh "$tmp/job.sh"
  ) > "$tmp/reg-$scenario.log" 2>&1
  code=$?
  posts=$(grep -c . "$tmp/registry/posts.log")
  ok=1
  if [ "$want_code" -eq 0 ]; then
    [ "$code" -eq 0 ] || { fail "package-publish $scenario: exit $code, expected 0"; ok=0; }
  else
    [ "$code" -ne 0 ] || { fail "package-publish $scenario: exit 0, expected non-zero"; ok=0; }
  fi
  [ "$posts" -eq "$want_posts" ] || { fail "package-publish $scenario: $posts publish requests, expected $want_posts"; ok=0; }
  grep -Fq -- "$want_text" "$tmp/reg-$scenario.log" || { fail "package-publish $scenario: the output does not say \"$want_text\""; ok=0; }
  if [ "$ok" -eq 1 ]; then
    echo "package-publish $scenario: exit $code, $posts publish requests (expected)"
  else
    sed 's/^/  | /' "$tmp/reg-$scenario.log" >&2
  fi
}

registry moved 1 0 "already published at a different commit (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa); refusing to overwrite it."
registry moved-v2 1 0 "already published at a different commit (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa); refusing to overwrite it."
registry same 0 0 "already published at this commit"
registry new 0 1 "Version 1.2.3 published."
registry unborn 0 1 "acme/demo has no published versions yet."
registry down 1 0 "Reading the Composer registry failed with HTTP 500."

if [ "$status" -eq 0 ]; then
  echo "check-package-publish-fails: ok"
fi
exit "$status"
