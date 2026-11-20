#!/bin/sh
# check-component-count.sh: do the docs count the components correctly?
#
# templates/ holds one folder per component, and BEST_PRACTICES.md and
# README.md name how many there are in several places. When a component is
# added, those counts drift: 0.9.0 added composer-ci and the docs still said
# fifteen. This check fails if any part of that contract is broken:
#
#   * the component-list sentence in BEST_PRACTICES.md ("Today it has
#     <word>:") names a different number;
#   * an "All <word> templates" or "The <word> templates" phrase in
#     BEST_PRACTICES.md uses a different word;
#   * the "<Word> on the manifest" line in README.md uses a different word; or
#   * the 7.2 sentence "Every component that runs as a job, X of Y," ends in a
#     word that is not the count.
#
# The script counts the directories under templates/ that hold a template.yml
# and greps the two Markdown files, so it needs no yq and runs on any Linux,
# macOS or Windows box with a POSIX shell. PF_ROOT points the check at another
# copy of the repository; the --self-test mode uses this to prove the guard
# fails when the docs name the wrong number.

set -u

ROOT="${PF_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
BP="$ROOT/BEST_PRACTICES.md"
README="$ROOT/README.md"
TEMPLATES="$ROOT/templates"

status=0
fail() {
  echo "check-component-count: $1" >&2
  status=1
}

if [ ! -f "$BP" ] || [ ! -f "$README" ]; then
  fail "BEST_PRACTICES.md or README.md is missing under $ROOT"
  exit 1
fi
if [ ! -d "$TEMPLATES" ]; then
  fail "templates/ is missing under $ROOT"
  exit 1
fi

# Count the component folders: directories under templates/ holding a template.yml.
count=0
for dir in "$TEMPLATES"/*/; do
  [ -d "$dir" ] || continue
  [ -f "$dir/template.yml" ] && count=$((count + 1))
done
if [ "$count" -lt 1 ] || [ "$count" -gt 30 ]; then
  fail "found $count component folders under templates/, expected between 1 and 30"
  exit 1
fi

# The count as an English word (1 to 30).
case $count in
  1) word=one ;;
  2) word=two ;;
  3) word=three ;;
  4) word=four ;;
  5) word=five ;;
  6) word=six ;;
  7) word=seven ;;
  8) word=eight ;;
  9) word=nine ;;
  10) word=ten ;;
  11) word=eleven ;;
  12) word=twelve ;;
  13) word=thirteen ;;
  14) word=fourteen ;;
  15) word=fifteen ;;
  16) word=sixteen ;;
  17) word=seventeen ;;
  18) word=eighteen ;;
  19) word=nineteen ;;
  20) word=twenty ;;
  21) word=twenty-one ;;
  22) word=twenty-two ;;
  23) word=twenty-three ;;
  24) word=twenty-four ;;
  25) word=twenty-five ;;
  26) word=twenty-six ;;
  27) word=twenty-seven ;;
  28) word=twenty-eight ;;
  29) word=twenty-nine ;;
  30) word=thirty ;;
esac
cap_word="$(printf '%s' "$word" | cut -c1 | tr 'a-z' 'A-Z')$(printf '%s' "$word" | cut -c2-)"

if [ "${1:-}" = "--self-test" ]; then
  # Run the guard against a copy of the repo files whose word is changed to
  # fourteen; it passes only when that run fails.
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  cp "$BP" "$README" "$tmp/"
  cp -R "$TEMPLATES" "$tmp/templates"
  for name in BEST_PRACTICES.md README.md; do
    sed "s/$word/fourteen/g; s/$cap_word/Fourteen/g" "$tmp/$name" > "$tmp/$name.tmp"
    mv "$tmp/$name.tmp" "$tmp/$name"
  done
  script=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
  if PF_ROOT="$tmp" sh "$script"; then
    echo "check-component-count: self-test failed: the guard passed on a copy whose word was changed to fourteen" >&2
    exit 1
  fi
  echo "check-component-count: self-test ok"
  exit 0
fi

# The component-list sentence names the count.
phrase=$(grep -oE 'Today it has [a-z]+:' "$BP" | head -n 1)
if [ -z "$phrase" ]; then
  fail "BEST_PRACTICES.md: no 'Today it has <word>:' sentence in the component list, expected 'Today it has $word:'"
elif [ "$phrase" != "Today it has $word:" ]; then
  fail "BEST_PRACTICES.md: found '$phrase', expected 'Today it has $word:'"
fi

# Every "All <word> templates" and "The <word> templates" phrase uses the count.
for pattern in 'All [a-z]+ templates' 'The [a-z]+ templates'; do
  lead=$(printf '%s\n' "$pattern" | cut -d' ' -f1)
  for w in $(grep -oE "$pattern" "$BP" | awk '{print $2}' | awk '!seen[$0]++'); do
    if [ "$w" != "$word" ]; then
      fail "BEST_PRACTICES.md: found '$lead $w templates', expected the word '$word'"
    fi
  done
done

# The README manifest line uses the capitalised count.
line=$(grep -F 'on the manifest' "$README" | grep -F '<sub>' | head -n 1)
if [ -z "$line" ]; then
  fail "README.md: no '<sub>' line with 'on the manifest', expected '$cap_word on the manifest'"
else
  found=$(printf '%s\n' "$line" | sed -n 's/.*<sub>[^A-Za-z]*\([A-Z][A-Za-z-]*\) on the manifest.*/\1/p')
  if [ "$found" != "$cap_word" ]; then
    fail "README.md: found '${found} on the manifest', expected '$cap_word on the manifest'"
  fi
fi

# The 7.2 sentence "Every component that runs as a job, X of Y," ends in the count.
phrase=$(grep -oE 'Every component that runs as a job, [a-z]+ of [a-z]+,' "$BP" | head -n 1)
if [ -z "$phrase" ]; then
  fail "BEST_PRACTICES.md: no 7.2 sentence 'Every component that runs as a job, X of Y,', expected Y to be '$word'"
else
  y=$(printf '%s\n' "$phrase" | tr -d ',' | awk '{print $NF}')
  if [ "$y" != "$word" ]; then
    fail "BEST_PRACTICES.md: found '$phrase', expected the second word to be '$word'"
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "check-component-count: ok"
fi
exit "$status"
