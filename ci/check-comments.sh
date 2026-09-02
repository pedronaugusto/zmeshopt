#!/usr/bin/env bash
#
# Refuses comment blocks that have stopped being reference documentation.
# Length per block, not density: a file where every declaration carries two
# crisp lines is correct at any percentage. Only our own sources — the
# vendored tree is upstream's to comment.
#
#   ci/check-comments.sh

set -uo pipefail
cd "$(dirname "$0")/.."

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; OFF=$'\033[0m'
else RED=; GREEN=; OFF=; fi

MAX_DECL=6      # comment lines directly above one declaration
MAX_HEADER=14   # the block at the top of a file
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

for f in src/*.zig src/c/*.zig examples/*.zig tests/*.c tests/consumer/src/* build.zig; do
  [ -f "$f" ] || continue
  awk -v F="$f" -v MD="$MAX_DECL" -v MH="$MAX_HEADER" '
    BEGIN { run = 0; start = 0; first = 1 }
    /^[[:space:]]*(\/\/|\/\*|\*)/ {
      if (run == 0) { start = NR; banner = 0 }
      if ($0 ~ /^[[:space:]]*\/\/={4,}/) banner = 1
      run++; next
    }
    {
      if (run > 0) {
        # A //===---===// banner heads a whole section, not one declaration,
        # and is where conventions covering everything below it belong.
        cap = ((first && start <= 3) || banner) ? MH : MD
        if (run > cap) printf "%s:%d: %d comment lines in one block (max %d)\n", F, start, run, cap
        first = 0; run = 0
      }
    }
    END { if (run > MD) printf "%s:%d: %d trailing comment lines\n", F, start, run }
  ' "$f" >> "$work/long"

  # Narrative register. These read as a person talking, not as documentation.
  LC_ALL=C grep -nEi '^[[:space:]]*(//|///|//!|\*|/\*).*(\bwe\b|\bour\b|\bnote that\b|\bworth (stating|noting|saying)\b|\bused to be\b|\bthey used to\b|\bit used to\b|\bthe reason (is|it)\b|\bwhich is why\b|\bthat is why\b|\bturns out\b|\bin practice this\b|\bdo not be\b|\byou might (think|expect)\b|\bit is tempting\b)' "$f" |
    sed "s|^|$f:|" >> "$work/voice"
done

fails=0
if [ -s "$work/long" ]; then
  sort -t: -k1,1 "$work/long" | head -40 | sed 's/^/  /' >&2
  printf '%s%d over-long comment block(s)%s\n' "$RED" "$(grep -c . "$work/long")" "$OFF" >&2
  fails=$((fails + 1))
fi
if [ -s "$work/voice" ]; then
  head -30 "$work/voice" | sed 's/^/  /' >&2
  printf '%s%d narrative comment line(s)%s\n' "$RED" "$(grep -c . "$work/voice")" "$OFF" >&2
  fails=$((fails + 1))
fi

[ "$fails" -ne 0 ] && exit 1
printf '%sOK%s  no over-long or narrative comment blocks\n' "$GREEN" "$OFF"
