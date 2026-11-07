#!/bin/sh
# check-renovate-squire-kit.sh: do the preset's Squire kit commands and the
# renovate component's allow-list agree, and does the allow-list stay tight?
#
# Renovate runs a repository's postUpgradeTasks only when each compiled
# command matches a pattern in the runner's allowedCommands. Preflight owns
# both halves: the waynestate/squire rule in renovate/default.json carries
# the two commands, and templates/renovate/template.yml writes the two
# patterns into config.js when squire_kit_tasks is on. This test:
#
#   * compiles the preset's commands the way Renovate does, for sample
#     upgrades (the replace helper, newVersion, packageFileDir), and checks
#     each one matches an allowed pattern;
#   * checks hostile variants (another package, a shell tail, ../ paths,
#     another squire command, another binary) match none;
#   * checks the rule installs php and composer, that postUpgradeTasks sits
#     only in the waynestate/squire rule, that no shell executor is turned
#     on, and that the kit-files rule switches Renovate off in the files
#     Squire writes (except Squire's own templates/).
#
# The patterns use only ERE syntax that RE2 reads the same way (anchors,
# classes, groups, +, *, ?), so grep -E answers what Renovate's RE2 would.
# POSIX sh, grep, sed and awk; no yq or jq. It runs in the mikefarah/yq
# image and on any Linux or macOS box. Its twin, check-renovate-squire-kit.ps1,
# does the same on Windows.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PRESET="$ROOT/renovate/default.json"
TPL="$ROOT/templates/renovate/template.yml"
status=0

fail() {
  echo "check-renovate-squire-kit: $1" >&2
  status=1
}

for f in "$PRESET" "$TPL"; do
  if [ ! -f "$f" ]; then
    echo "check-renovate-squire-kit: missing ${f#"$ROOT"/}" >&2
    exit 1
  fi
done

# The commands of the waynestate/squire rule, one per line, JSON quotes and
# trailing commas stripped. They carry no JSON escapes.
commands=$(awk '
  /"postUpgradeTasks"/ { inTasks = 1 }
  inTasks && /"commands"/ { inCmds = 1; next }
  inCmds && /^[[:space:]]*\]/ { inCmds = 0; inTasks = 0 }
  inCmds { line = $0; sub(/^[[:space:]]*"/, "", line); sub(/",?[[:space:]]*$/, "", line); print line }
' "$PRESET")
count=$(printf '%s\n' "$commands" | grep -c . || true)
if [ "$count" -ne 2 ]; then
  fail "the waynestate/squire rule must carry exactly two postUpgradeTasks commands, found $count"
fi

# postUpgradeTasks appears once, inside the waynestate/squire rule.
tasks=$(grep -c '"postUpgradeTasks"' "$PRESET" || true)
if [ "$tasks" -ne 1 ]; then
  fail "renovate/default.json must carry postUpgradeTasks exactly once (the waynestate/squire rule), found $tasks"
fi
if ! awk '
  /"matchDepNames".*"waynestate\/squire"/ { key = NR }
  key > 0 && NR > key && NR - key <= 8 && /"postUpgradeTasks"/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$PRESET"; then
  fail "postUpgradeTasks is not inside the waynestate/squire rule"
fi

# The rule installs the tools its commands need.
if ! awk '
  /"installTools"/ { key = NR }
  key > 0 && NR > key && NR - key <= 4 {
    if (/"php"/) p = 1
    if (/"composer"/) c = 1
  }
  END { exit (p && c) ? 0 : 1 }
' "$PRESET"; then
  fail "the waynestate/squire postUpgradeTasks must install php and composer (installTools)"
fi

# Each template expression is one Renovate compiles the way this test does.
uniq='{{{replace '"'"'[^A-Za-z0-9_-]'"'"' '"'"'-'"'"' repository}}}-{{{replace '"'"'[^A-Za-z0-9_-]'"'"' '"'"'-'"'"' packageFile}}}'
cmd1=$(printf '%s\n' "$commands" | sed -n 1p)
cmd2=$(printf '%s\n' "$commands" | sed -n 2p)
want1="composer create-project --no-dev --no-interaction --no-progress --no-scripts waynestate/squire /tmp/renovate-squire/$uniq {{{newVersion}}}"
want2="php /tmp/renovate-squire/$uniq/bin/squire update --path={{{packageFileDir}}}"
if [ "$cmd1" != "$want1" ]; then
  fail "command 1 is not the expected one: $cmd1"
fi
if [ "$cmd2" != "$want2" ]; then
  fail "command 2 is not the expected one: $cmd2"
fi

# The allowed patterns, from config.js in the template: the quoted strings
# between "allowedCommands: squireKitTasks ? [" and "] : []", with the JS
# escape \\ turned back into \.
patterns=$(awk '
  /allowedCommands: squireKitTasks \? \[/ { inList = 1; next }
  inList && /\] : \[\]/ { inList = 0 }
  inList { line = $0; sub(/^[[:space:]]*"/, "", line); sub(/",?[[:space:]]*$/, "", line); print line }
' "$TPL" | sed 's/\\\\/\\/g')
pcount=$(printf '%s\n' "$patterns" | grep -c . || true)
if [ "$pcount" -ne 2 ]; then
  fail "templates/renovate/template.yml must allow exactly two commands, found $pcount"
fi
if ! grep -qF 'const squireKitTasks = $[[ inputs.squire_kit_tasks ]];' "$TPL"; then
  fail "config.js does not take the allow-list switch from the squire_kit_tasks input"
fi
if ! grep -qE '^    squire_kit_tasks:' "$TPL" || ! awk '
  /^    squire_kit_tasks:/ { inBlock = 1; next }
  inBlock && /^    [A-Za-z_]/ { inBlock = 0 }
  inBlock && /^      type: boolean/ { t = 1 }
  inBlock && /^      default: false/ { d = 1 }
  END { exit (t && d) ? 0 : 1 }
' "$TPL"; then
  fail "the squire_kit_tasks input must be a boolean that defaults to false"
fi
if grep -q 'allowShellExecutorForPostUpgradeCommands' "$PRESET" "$TPL"; then
  fail "the shell executor must stay off: commands run as plain argument lists"
fi

# matches <command>: exit 0 when an allowed pattern matches the command.
matches() {
  printf '%s\n' "$patterns" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    if printf '%s\n' "$1" | grep -qE -- "$p"; then
      echo yes
    fi
  done | grep -q yes
}

# compile <command> <repository> <packageFile> <packageFileDir> <newVersion>
compile() {
  repo_seg=$(printf '%s' "$2" | sed 's/[^A-Za-z0-9_-]/-/g')
  file_seg=$(printf '%s' "$3" | sed 's/[^A-Za-z0-9_-]/-/g')
  printf '%s\n' "$1" \
    | sed "s#{{{replace '\[^A-Za-z0-9_-\]' '-' repository}}}#$repo_seg#g" \
    | sed "s#{{{replace '\[^A-Za-z0-9_-\]' '-' packageFile}}}#$file_seg#g" \
    | sed "s#{{{packageFileDir}}}#$4#g; s#{{{newVersion}}}#$5#g"
}

# Sample upgrades: repository|packageFile|packageFileDir|newVersion.
for sample in \
  'enterprise-apps/creed|deploy/.squire.json|deploy|0.5.0' \
  'group/sub/app|.squire.json||1.12.0' \
  'enterprise-apps/preflight|tests/squire-kit-fixture/.squire.json|tests/squire-kit-fixture|0.6.0'; do
  IFS='|' read -r repo file dir ver <<EOF
$sample
EOF
  for raw in "$cmd1" "$cmd2"; do
    compiled=$(compile "$raw" "$repo" "$file" "$dir" "$ver")
    case $compiled in
      *'{{'*) fail "a template expression was left uncompiled: $compiled" ;;
    esac
    if ! matches "$compiled"; then
      fail "allowedCommands does not allow the preset's command: $compiled"
    fi
  done
done

# Hostile variants: each must match no allowed pattern.
pre='composer create-project --no-dev --no-interaction --no-progress --no-scripts'
sq='php /tmp/renovate-squire/enterprise-apps-creed-deploy--squire-json/bin/squire'
while IFS= read -r bad; do
  [ -n "$bad" ] || continue
  if matches "$bad"; then
    fail "allowedCommands must not allow: $bad"
  fi
done <<EOF
$pre waynestate/squire /tmp/renovate-squire/x 0.5.0; id
$pre waynestate/squire /tmp/renovate-squire/x 0.5.0 && id
$pre waynestate/squire-evil /tmp/renovate-squire/x 0.5.0
$pre other/package /tmp/renovate-squire/x 0.5.0
$pre --repository=https://example.com waynestate/squire /tmp/renovate-squire/x 0.5.0
$pre waynestate/squire /tmp/renovate-squire/../x 0.5.0
$pre waynestate/squire /tmp/renovate-squire/a/b 0.5.0
$pre waynestate/squire /home/x 0.5.0
$pre waynestate/squire /tmp/renovate-squire/x dev-main
composer create-project waynestate/squire /tmp/renovate-squire/x 0.5.0
$sq update --path=../etc
$sq update --path=/etc
$sq update --path=a/../b
$sq update --path=.hidden
$sq update --path=deploy \$(id)
$sq update --path=deploy; id
$sq init --force --path=deploy
$sq update --dry-run --path=deploy
php /tmp/renovate-squire/../evil/bin/squire update --path=deploy
php /tmp/renovate-squire/x/evil.php update --path=deploy
php -r system('id');
sh -c id
EOF

# The kit-files rule: Renovate leaves the files Squire writes alone, apart
# from Squire's own source templates, and they move with a Squire release.
if ! awk '
  index($0, "\"**/docker-compose.squire.yml\"") { key = NR }
  key > 0 && NR >= key && NR - key <= 4 {
    if (index($0, "\"**/docker-compose.squire.yml\"")) c = 1
    if (index($0, "\"**/.squire/**\"")) s = 1
    if (index($0, "\"!/^templates\\\\/(common|vue|raw|laravel|static)\\\\//\"")) t = 1
    if (/"enabled":[[:space:]]*false/) e = 1
  }
  END { exit (c && s && t && e) ? 0 : 1 }
' "$PRESET"; then
  fail "the kit-files rule (docker-compose.squire.yml and .squire/ off, Squire's templates/ kept) is missing or incomplete"
fi

if [ "$status" -eq 0 ]; then
  echo "check-renovate-squire-kit: ok"
fi
exit "$status"
