#!/usr/bin/env bash
#
# zmeshopt — the Zig surface covers the C surface, in both directions.
#
# Whether src/c/ binds everything the header exports is not this script's
# question: src/abi_check.zig's reverse sweep refuses the build over it. What
# nothing else checks is the layer above — an extern with no idiomatic caller
# is unreachable for a Zig host that stays out of `c`, and an exception that
# outlives its reason is a rule about code that no longer exists. Plus the
# inline ledger: upstream helpers that exist only as C++ inline functions
# have no symbol to bind, so each needs a Zig reimplementation on record,
# with the list derived from the header so a re-vendor that adds one fails
# here until it is accounted for.
#
#   ci/check-coverage.sh

set -uo pipefail
cd "$(dirname "$0")/.."

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
else RED=; GREEN=; BOLD=; OFF=; fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fails=0
fail() { printf '%s%s%s\n' "$RED" "$1" "$OFF" >&2; fails=$((fails + 1)); }

#-----------------------------------------------------------------------------
# The Zig surface: every extern reachable from the idiomatic layer.
#-----------------------------------------------------------------------------
grep -h 'pub extern fn meshopt_' src/c/*.zig |
  grep -oE 'meshopt_[A-Za-z0-9_]+' | sort -u > "$work/entrypoints"

# Comments are stripped first: a doc comment NAMING an entry point must not
# count as calling it. src/c/ and c.zig are declarations, abi_check.zig is
# the oracle, and neither is use.
find src -name '*.zig' ! -path 'src/c/*' ! -name 'c.zig' ! -name 'abi_check.zig' \
     ! -name '*_test.zig' -print0 |
  xargs -0 sed -E 's://.*::' |
  grep -oE 'meshopt_[A-Za-z0-9_]+' | sort -u > "$work/wrapped"

awk -F'\t' '/^#/ || !NF { next }
  NF != 2 { printf "  %s: not NAME<TAB>reason\n", $1 > "/dev/stderr"; next }
  length($2) < 10 { printf "  %s: no reason given\n", $1 > "/dev/stderr"; next }
  { print $1 }' tools/zig_surface_exceptions.txt 2>"$work/exc_shape" | sort -u > "$work/excused"
if [ -s "$work/exc_shape" ]; then
  cat "$work/exc_shape" >&2
  fail "$(grep -c . "$work/exc_shape") malformed exception line(s)"
fi

comm -23 "$work/entrypoints" "$work/wrapped" > "$work/unwrapped"
comm -23 "$work/unwrapped" "$work/excused" > "$work/stranded"
if [ -s "$work/stranded" ]; then
  sed 's/^/  /' "$work/stranded" >&2
  fail "$(grep -c . "$work/stranded") entry point(s) with no idiomatic caller"
fi
comm -13 "$work/unwrapped" "$work/excused" > "$work/excess"
if [ -s "$work/excess" ]; then
  sed 's/^/  /' "$work/excess" >&2
  fail "$(grep -c . "$work/excess") excused entry point(s) the idiomatic layer does call, or that no longer exist"
fi

#-----------------------------------------------------------------------------
# The inline ledger. `^inline` in the header, outside the template-wrapper
# region, is a C++-only helper with no linkable symbol; each must map to a
# real Zig declaration and a real test, per tools/zig_reimpl.txt.
#-----------------------------------------------------------------------------
# Scan stops at the first MESHOPTIMIZER_NO_WRAPPERS line: everything from
# there down is the C++ template-wrapper region, which only re-spells
# functions the C ABI already exports.
awk '/MESHOPTIMIZER_NO_WRAPPERS/ { exit }
     /^inline/ { if (match($0, /meshopt_[A-Za-z0-9_]+/))
                   print substr($0, RSTART, RLENGTH) }' \
  libs/meshoptimizer/src/meshoptimizer.h | sort -u > "$work/inline_helpers"

awk -F'\t' '/^#/ || !NF { next }
  NF != 3 { printf "  %s: not NAME<TAB>src/FILE.zig:decl<TAB>test name\n", $1 > "/dev/stderr"; next }
  $2 !~ /^src\/[A-Za-z0-9_]+\.zig:[A-Za-z_][A-Za-z0-9_]*$/ {
    printf "  %s: %s is not src/FILE.zig:decl\n", $1, $2 > "/dev/stderr"; next }
  length($3) < 4 { printf "  %s: names no test\n", $1 > "/dev/stderr"; next }
  { print }' tools/zig_reimpl.txt 2>"$work/reimpl_shape" > "$work/reimpl_rows"
if [ -s "$work/reimpl_shape" ]; then
  cat "$work/reimpl_shape" >&2
  fail "$(grep -c . "$work/reimpl_shape") malformed reimplementation line(s)"
fi

cut -f1 "$work/reimpl_rows" | sort -u > "$work/reimpl_names"
comm -23 "$work/inline_helpers" "$work/reimpl_names" > "$work/unledgered"
if [ -s "$work/unledgered" ]; then
  sed 's/^/  /' "$work/unledgered" >&2
  fail "$(grep -c . "$work/unledgered") C++-only inline helper(s) with no Zig reimplementation on record"
fi
comm -13 "$work/inline_helpers" "$work/reimpl_names" > "$work/reimpl_stale"
if [ -s "$work/reimpl_stale" ]; then
  sed 's/^/  /' "$work/reimpl_stale" >&2
  fail "$(grep -c . "$work/reimpl_stale") ledger line(s) for helpers the header no longer declares inline-only"
fi

while IFS=$'\t' read -r name ref test_name; do
  file=${ref%%:*}; decl=${ref#*:}
  if [ ! -f "$file" ]; then
    printf '  %s: %s does not exist\n' "$name" "$file" >&2
    fail "a ledger file reference points at nothing"
    continue
  fi
  grep -qE "^pub fn $decl\(" "$file" || {
    printf '  %s: %s declares no pub fn %s\n' "$name" "$file" "$decl" >&2
    fail "a ledger declaration reference points at nothing"
  }
  grep -qF "test $test_name {" "$file" || {
    printf '  %s: %s has no test named %s\n' "$name" "$file" "$test_name" >&2
    fail "a ledger test reference points at nothing"
  }
done < "$work/reimpl_rows"

#-----------------------------------------------------------------------------
# Summary.
#-----------------------------------------------------------------------------
printf '%szmeshopt coverage%s\n' "$BOLD" "$OFF"
printf '  %-40s %5d\n' 'entry points declared in src/c/' "$(grep -c . "$work/entrypoints")"
printf '  %-40s %5d\n' '  called by the idiomatic layer' \
  "$(comm -12 "$work/entrypoints" "$work/wrapped" | grep -c .)"
printf '  %-40s %5d\n' '  excused, with a reason' "$(grep -c . "$work/excused")"
printf '  %-40s %5d\n' 'C++-only inline helpers, reimplemented' "$(grep -c . "$work/inline_helpers")"

if [ "$fails" -ne 0 ]; then
  printf '\n%sFAIL%s  %d problem(s)\n' "$RED" "$OFF" "$fails" >&2
  exit 1
fi
printf '\n%sOK%s  every entry point is reachable in Zig or excused\n' "$GREEN" "$OFF"
