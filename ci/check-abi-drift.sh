#!/usr/bin/env bash
#
# zmeshopt — mutation test for the ABI cross-check.
#
# `src/abi_check.zig` compares every extern declaration in `src/c/` against
# the real vendored `meshoptimizer.h` by reflection. It is the one test in
# this repo that cannot test itself: a refactor that quietly makes it vacuous
# — a name filter that matches nothing, a sweep that silently skips a
# category — looks exactly like a passing build. The coverage floors in
# `abi_check.zig` catch the crude version of that. Only mutation catches the
# subtle one.
#
# So this applies one deliberate drift at a time, asserts the build is
# REFUSED with the guard's own message, and reverts. Each mutation is a
# distinct kind of skew, chosen because it is the kind a human review would
# miss. Three of them mutate the VENDORED header — always restored, and a
# leftover would be caught by both the trap sweep here and ci/verify-vendor.sh.
#
# Out of `ci/run.sh --quick` — it rebuilds once per mutation and takes
# minutes. The full `ci/run.sh` does run it, as does CI.
#
# Usage:
#   ci/check-abi-drift.sh                     # the host's default ABI
#   ci/check-abi-drift.sh -Dtarget=<triple>   # that ABI instead
#
# Any argument given is appended to every `zig build test` below. The one
# that matters is `-Dtarget`: the oracle compares src/c/ against @cImport of
# the header AS PREPROCESSED FOR A TARGET, so a guard proved to fire on one
# ABI is not proved to fire on another — a C enum is `int` under MSVC and
# `unsigned int` under the Itanium ABI, and meshopt_EncodeExpMode crosses
# that boundary.

set -uo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/.."

pass=0

ZIG=${ZIG:-zig}

# The arm every build in this run is proved on, carried in one place so the
# clean-tree precheck, each mutation and the final summary cannot disagree
# about which ABI the count belongs to.
ARM="$*"
ZIG_TEST="$ZIG build test${ARM:+ $ARM}"
BUILD="$ZIG_TEST"
fail=0
backups=()

restore() {
  local f
  for f in "${backups[@]:-}"; do
    [ -n "$f" ] && [ -f "$f.bak" ] && mv "$f.bak" "$f"
  done
  backups=()
}
# A killed run must not leave a mutated source behind. EXIT covers the paths
# a signal handler does not — an error exit, the shell dying with its parent;
# INT/TERM keep the exit status. SIGKILL cannot be trapped at all, so the
# stale-backup sweep below is the other half.
trap restore EXIT
trap 'restore; exit 130' INT TERM HUP QUIT

# A previous run that was killed outright left its .bak beside the file it
# had mutated, and this run would then measure a mutated tree and save the
# mutation as its own backup. Recover first, and say so.
stale=$(find . -name '*.bak' -not -path './.zig-cache/*' -not -path './.git/*')
if [ -n "$stale" ]; then
  printf 'recovering from a killed run:\n' >&2
  while read -r bak; do
    [ -n "$bak" ] || continue
    printf '  restoring %s\n' "${bak%.bak}" >&2
    mv "$bak" "${bak%.bak}"
  done <<< "$stale"
fi

# try <description> <file> <from> <to>
#
# Asserts the ABI cross-check refuses the mutation, by its own message.
try() {
  expect 'zmeshopt ABI drift: [^"]*' "$@"
}

# expect <signal> <description> <file> <from> <to>
#
# `signal` is a grep pattern the output must contain. Requiring a specific
# signal rather than merely a non-zero exit is the whole point: a mutation
# that fails for an unrelated reason — a typo in the replacement, a stale
# anchor landing somewhere odd — would otherwise count as a guard doing its
# job.
expect() {
  local signal="$1" what="$2" file="$3" from="$4" to="$5"

  cp "$file" "$file.bak"
  backups=("$file")

  # A stale anchor and a helper that could not run mean opposite things: the
  # first is a mutation to rewrite, the second says nothing about the guard
  # at all. newline= on both ends keeps the mutated file byte-faithful. The
  # three inputs travel in the ENVIRONMENT, not argv: given `python3 - <path>`
  # the Windows `py` launcher reads the shebang of the PATH argument instead
  # of passing it through.
  local applied
  applied=$(MUT_FILE="$file" MUT_FROM="$from" MUT_TO="$to" python3 <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["MUT_FILE"])
before, after = os.environ["MUT_FROM"], os.environ["MUT_TO"]
with open(p, encoding="utf-8", newline="") as f:
    s = f.read()
if before not in s:
    print("ANCHOR_MISSING")
    raise SystemExit(0)
with open(p, "w", encoding="utf-8", newline="") as f:
    f.write(s.replace(before, after, 1))
print("APPLIED")
PY
  )
  case "$applied" in
    APPLIED) ;;
    ANCHOR_MISSING)
      printf '  ANCHOR STALE  %s\n' "$what"
      fail=$((fail + 1))
      restore
      return
      ;;
    *)
      printf '  TOOL FAILED   %s\n' "$what"
      printf '                the mutation never applied; nothing learned\n'
      fail=$((fail + 1))
      restore
      return
      ;;
  esac

  local out status
  out=$(eval "$BUILD" 2>&1)
  status=$?
  restore

  if [ $status -eq 0 ]; then
    printf '  NOT CAUGHT    %s\n' "$what"
    fail=$((fail + 1))
    return
  fi

  local msg
  msg=$(printf '%s' "$out" | grep -m1 -oE "$signal")
  if [ -z "$msg" ]; then
    printf '  WRONG FAILURE %s\n' "$what"
    printf '                expected to see: %s\n' "$signal"
    printf '%s\n' "$out" | tail -5 | sed 's/^/      | /'
    fail=$((fail + 1))
    return
  fi

  printf '  caught        %s\n' "$what"
  printf '                -> %s\n' "$msg"
  pass=$((pass + 1))
}

# A clean tree first: a mutation is only evidence if the unmutated build
# passes.
if ! eval "$ZIG_TEST" >/dev/null 2>&1; then
  echo "the unmutated build already fails; fix that before reading this script's output"
  exit 1
fi

echo "drift the ABI cross-check must refuse${ARM:+, on $ARM}:"

# Two same-sized fields exchanged. cone_apex and cone_axis are both
# float[3], so the offset SEQUENCE of meshopt_Bounds is unchanged and every
# positional check and every offsets-only digest passes this — while every
# cluster's cone apex is read as its axis.
try "same-sized fields swapped" src/c/clusterize.zig \
"$(printf '    cone_apex: [3]f32,\n    cone_axis: [3]f32,')" \
"$(printf '    cone_axis: [3]f32,\n    cone_apex: [3]f32,')"

# A callback parameter widened. The custom-remap callback crosses as a bare
# function pointer with no upstream typedef; only a comparison that recurses
# INTO pointed-to function types can see this one.
try "a callback parameter widened (u32 -> u64)" src/c/remap.zig \
'pub const RemapCallback = *const fn (context: ?*anyopaque, a: u32, b: u32) callconv(.c) c_int;' \
'pub const RemapCallback = *const fn (context: ?*anyopaque, a: u64, b: u32) callconv(.c) c_int;'

try "a parameter dropped from a function" src/c/simplify.zig \
'pub extern fn meshopt_simplifyScale(vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) f32;' \
'pub extern fn meshopt_simplifyScale(vertex_positions: [*]const f32, vertex_count: usize) f32;'

try "a parameter widened (f32 -> f64)" src/c/cache.zig \
'pub extern fn meshopt_optimizeOverdraw(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, threshold: f32) void;' \
'pub extern fn meshopt_optimizeOverdraw(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, threshold: f64) void;'

try "an enumerator renumbered" src/c/encode_filters.zig \
'    shared_component = 2,' \
'    shared_component = 20,'

try "an enum tag narrowed (c_uint -> u8)" src/c/encode_filters.zig \
'pub const EncodeExpMode = enum(c_uint) {' \
'pub const EncodeExpMode = enum(u8) {'

# Two mask bits exchanged. The anonymous enum upstream spells these in has
# no C type to pair with, so only the per-bit enumerator reconstruction can
# see prune sitting on regularize's bit.
try "two mask bits exchanged" src/c/simplify.zig \
"$(printf '    prune: bool = false,\n    /// More regular triangle sizes and shapes, at some cost to geometric and\n    /// attribute quality (`meshopt_SimplifyRegularize`).\n    regularize: bool = false,')" \
"$(printf '    regularize: bool = false,\n    prune: bool = false,')"

# A mask flag renamed. The reconstruction meshopt_Simplify + RegularizeLite
# names an enumerator the header never declared; a mask check that only
# verified the bits IT knows about would let an invented flag through.
try "a mask flag renamed to something upstream lacks" src/c/simplify.zig \
'    regularize_light: bool = false,' \
'    regularize_lite: bool = false,'

# The reverse direction: the header declares something src/c/ does not.
try "an extern deleted" src/c/stripify.zig \
'pub extern fn meshopt_stripifyBound(index_count: usize) usize;' \
''

# A Zig helper wearing an exported symbol's name. The forward sweep skips
# non-extern functions and the reverse sweep asks whether the name exists;
# only demanding EXTERN declarations closes the gap between them.
try "an extern replaced by a Zig helper of the same name" src/c/index_codec.zig \
'pub extern fn meshopt_encodeIndexBufferBound(index_count: usize, vertex_count: usize) usize;' \
'pub fn meshopt_encodeIndexBufferBound(index_count: usize, vertex_count: usize) usize {
    _ = vertex_count;
    return index_count;
}'

# Header-side mutations: the vendored header is what @cImport reads, so a
# drift IN UPSTREAM at the next re-vendor looks exactly like this.
try "a struct field added in the header only" libs/meshoptimizer/src/meshoptimizer.h \
"$(printf 'struct meshopt_Stream\n{\n\tconst void* data;')" \
"$(printf 'struct meshopt_Stream\n{\n\tunsigned int intruder;\n\tconst void* data;')"

# Signedness, which size and alignment cannot see: same width, same offset,
# and an offset above 2^31 read back as negative.
try "a field's signedness flipped in the header" libs/meshoptimizer/src/meshoptimizer.h \
"$(printf '\tunsigned int vertex_offset;')" \
"$(printf '\tint vertex_offset;')"

# The other half of scalar identity: a 32-bit integer and a 32-bit float are
# the same width, the same alignment, the same offset — and every bit
# pattern that crosses means something else entirely. The float -> int
# direction, on a field the C++ only assigns, so the mutated library still
# compiles and the refusal is the oracle's.
try "a field retyped float -> int in the header" libs/meshoptimizer/src/meshoptimizer.h \
'	float cone_cutoff; /* = cos(angle/2) */' \
'	int cone_cutoff; /* = cos(angle/2) */'

# A new export appearing upstream. The reverse sweep is the completeness
# gate: a re-vendor that brings a new function must fail until src/c/ binds
# it, or "binds all of it" quietly stops being true.
try "a new function declared in the header only" libs/meshoptimizer/src/meshoptimizer.h \
'MESHOPTIMIZER_API size_t meshopt_buildMeshletsBound(size_t index_count, size_t max_vertices, size_t max_triangles);' \
"$(printf 'MESHOPTIMIZER_API size_t meshopt_buildMeshletsBound(size_t index_count, size_t max_vertices, size_t max_triangles);\nMESHOPTIMIZER_API void meshopt_futureThing(unsigned int* destination, size_t count);')"

# The pinned count of late-float signatures — the shapes the runtime canary
# has to mirror. If the pin can drift without a refusal, a ninth affected
# signature could arrive at the next re-vendor with no canary watching it.
expect 'expected 9, found 8' \
  "the late-float signature count drifted" src/abi_check.zig \
'try std.testing.expectEqual(@as(usize, 8), ours.late_float_fns);' \
'try std.testing.expectEqual(@as(usize, 9), ours.late_float_fns);'

# The canary harness itself: a mirror that echoes the wrong value must fail
# the comparison, or the canary proves nothing about argument arrival.
expect "late-float canary: meshopt_simplify" \
  "a canary mirror echoing a wrong value" tests/abi_canary.c \
'    slots[7] = (double)target_error;' \
'    slots[7] = (double)target_error + 1;'

#-----------------------------------------------------------------------------
# The coverage guard.
#
# `ci/check-coverage.sh` answers "is every entry point reachable in Zig, and
# is the inline ledger honest". If it goes vacuous it reports full coverage
# and nobody notices.
#-----------------------------------------------------------------------------
BUILD='bash ci/check-coverage.sh'

if ! bash ci/check-coverage.sh >/dev/null 2>&1; then
  echo
  echo "  SKIPPED       the four coverage mutations"
  echo "                ci/check-coverage.sh already fails, so they would all"
  echo "                report a catch without catching anything."
  fail=$((fail + 1))
else

expect 'entry point\(s\) with no idiomatic caller' \
  "an idiomatic caller removed" src/stripify.zig \
'    return c.meshopt_stripifyBound(index_count);' \
'    return index_count * 2;'

expect 'the idiomatic layer does call' \
  "an excuse written for an entry point that needs none" tools/zig_surface_exceptions.txt \
'# (empty: every extern has an idiomatic caller)' \
"$(printf '# (empty: every extern has an idiomatic caller)\nmeshopt_stripifyBound\tbound size helper, callers can compute it')"

expect 'no Zig reimplementation on record' \
  "an inline-helper ledger row deleted" tools/zig_reimpl.txt \
"$(printf 'meshopt_quantizeUnorm\tsrc/quantize.zig:quantizeUnorm\tquantizeUnorm')" \
"$(printf '#meshopt_quantizeUnorm\tsrc/quantize.zig:quantizeUnorm\tquantizeUnorm')"

expect 'has no test named' \
  "a ledger row naming a test that does not exist" tools/zig_reimpl.txt \
"$(printf 'meshopt_quantizeSnorm\tsrc/quantize.zig:quantizeSnorm\tquantizeSnorm')" \
"$(printf 'meshopt_quantizeSnorm\tsrc/quantize.zig:quantizeSnorm\tquantizeSnormAll')"

fi

BUILD="$ZIG_TEST"

printf '\ncaught: %d   missed: %d   on %s\n' "$pass" "$fail" "${ARM:-the host default ABI}"

# ci/measurements.sh publishes how many mutations this file holds by counting
# its `try` and `expect` lines. A declaration inside a branch that did not
# run would make that number overstate the proof; this makes it mean "ran".
declared=$(grep -cE '^(try|expect) ' "$SELF")
if [ $fail -eq 0 ] && [ $((pass + fail)) -ne "$declared" ]; then
  printf 'ran %d of %d declared mutations; the published count would overstate it\n' \
    "$((pass + fail))" "$declared"
  exit 1
fi

[ $fail -eq 0 ]
