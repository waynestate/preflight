#!/bin/sh
# check-secret-detection-fails.sh: does the secret-detection component still
# fail a bad app and pass a clean one?
#
# The secret-detection component passes Gitleaks' exit code through: the job
# runs gitleaks dir plainly, so a non-zero exit fails the job. This script
# checks that the template keeps that plain line (no tee, no pipe, no
# swallowed exit code), takes the config from the template's own heredoc,
# then runs the two cases:
#
#   tests/secret-detection-clean  exit 0 (the clean case, with a fake token
#                                   planted in vendor/ and node_modules/ to
#                                   prove the path allowlist)
#   the same copy plus a token in  non-zero exit, the report names
#   src/config.php                  gitlab-pat, the log carries no value
#                                   (the must-fail case, proving --redact)
#
# The fake token is built at run time, so no secret-shaped string is ever
# committed. It runs inside the template's image (zricethezav/gitleaks,
# pinned by digest in templates/secret-detection/template.yml), where it
# performs the template's own command for each case, in a copy in a temp
# dir. One result line per case goes to stdout; a case's log is printed only
# for a case that went wrong. Run it with
#
#   docker run --rm --entrypoint sh -v "$(pwd):/app" -w /app \
#     zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f \
#     tests/check-secret-detection-fails.sh
#
# Its twin, check-secret-detection-fails.ps1, does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TPL="$ROOT/templates/secret-detection/template.yml"

status=0
fail() {
  echo "check-secret-detection-fails: $1" >&2
  status=1
}

[ -f "$TPL" ] || fail "template missing: templates/secret-detection/template.yml"
[ -f "$ROOT/tests/secret-detection-clean/src/app.php" ] || fail "clean fixture missing: tests/secret-detection-clean"
[ "$status" -eq 0 ] || exit 1

# (a) the job keeps the plain gitleaks dir line, so Gitleaks' exit code is
# the job result: no tee, no pipe, no swallowed exit code.
grep -Fxq -- '      gitleaks dir --redact --no-banner --config="$CONFIG" --report-format=json --report-path="$CI_PROJECT_DIR/gitleaks.json" .' "$TPL" \
  || fail "secret-detection job does not run gitleaks dir plainly (no tee, no pipe)"
if grep 'gitleaks dir' "$TPL" | grep -Eq '\|\||\| *tee|; *true'; then
  fail "a gitleaks dir line swallows the exit code (||, | tee or ; true)"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# (b) take the config from the template itself: the lines between the
# <<'TOML' line and the closing TOML line, with the leading indent stripped.
# A drift in the template's config is what this check runs.
awk '/<<.TOML./ { in_toml = 1; next } in_toml && /^[[:space:]]*TOML[[:space:]]*$/ { in_toml = 0 } in_toml' "$TPL" \
  | sed 's/^[[:space:]]*//' > "$tmp/config.toml"
[ -s "$tmp/config.toml" ] || fail "could not extract the gitleaks config from the template"
CONFIG="$tmp/config.toml"

# The fake token is built at run time, so no secret-shaped string is ever
# committed: the GitLab personal access token prefix, in two pieces, plus a
# 20-character body.
a=glp
b=at-
TOKEN="${a}${b}x7Kq2Lm9Pz4Rt8Vw3Ny6"

# (c) clean: a token planted in vendor/ and node_modules/ stays invisible,
# so the scan exits 0.
work="$tmp/clean"
cp -R "$ROOT/tests/secret-detection-clean" "$work"
mkdir -p "$work/vendor/acme" "$work/node_modules/acme"
printf '%s\n' "<?php" "return '$TOKEN';" > "$work/vendor/acme/key.php"
printf '%s\n' "module.exports = \"$TOKEN\";" > "$work/node_modules/acme/key.js"
(cd "$work" && gitleaks dir --redact --no-banner --config="$CONFIG" --report-format=json --report-path="$work/gitleaks.json" .) > "$tmp/clean.log" 2>&1
code=$?
ok=1
[ "$code" -eq 0 ] || { fail "secret-detection clean: exit $code, expected 0"; ok=0; }
if [ "$ok" -eq 1 ]; then
  echo "secret-detection clean: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/clean.log" >&2
fi

# (d) must-fail: a token in the app's own code is reported, the report names
# gitlab-pat, and the log carries no value (--redact is still in place).
work="$tmp/mustfail"
cp -R "$ROOT/tests/secret-detection-clean" "$work"
printf '%s\n' "<?php" "return '$TOKEN';" > "$work/src/config.php"
(cd "$work" && gitleaks dir --redact --no-banner --config="$CONFIG" --report-format=json --report-path="$work/gitleaks.json" .) > "$tmp/mustfail.log" 2>&1
code=$?
ok=1
[ "$code" -ne 0 ] || { fail "secret-detection must-fail: exit 0, expected non-zero"; ok=0; }
[ -f "$work/gitleaks.json" ] && grep -Fq "gitlab-pat" "$work/gitleaks.json" \
  || { fail "secret-detection must-fail: the report does not name gitlab-pat"; ok=0; }
if grep -Fq "$TOKEN" "$tmp/mustfail.log"; then
  fail "secret-detection must-fail: the log carries the token value (--redact is gone)"
  ok=0
fi
if [ "$ok" -eq 1 ]; then
  echo "secret-detection must-fail: exit $code (expected)"
else
  sed 's/^/  | /' "$tmp/mustfail.log" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "check-secret-detection-fails: ok"
fi
exit "$status"
