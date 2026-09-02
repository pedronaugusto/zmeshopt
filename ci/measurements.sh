#!/usr/bin/env bash
#
# zmeshopt — recompute every number the documentation claims.
#
# Every count README.md publishes comes from here and from nowhere else: the
# README carries a generated block that ci/check-docs.sh rebuilds from this
# script and refuses to let drift. A hand-written count is not allowed to
# exist, so there is nothing left that can quietly go stale.
#
# Usage:
#   ci/measurements.sh            # human-readable
#   ci/measurements.sh --kv       # KEY<TAB>VALUE<TAB>DESCRIPTION
#   ci/measurements.sh --markdown # the table README.md's generated block holds
#
# ZIG overrides the compiler used by the one measurement that has to build.
# Nothing here uses `bc`: it is absent from Git Bash, and an absent bc produced
# an EMPTY count rather than an error.

set -euo pipefail
cd "$(dirname "$0")/.."

MODE=${1:-}
ZIG=${ZIG:-zig}

#-----------------------------------------------------------------------------
# The measurements. Each is `emit KEY VALUE DESCRIPTION`, and the description
# is what the README prints, so a measurement is described once.
#-----------------------------------------------------------------------------

keys=()
values=()
descriptions=()
emit() {
  keys+=("$1")
  values+=("$2")
  descriptions+=("$3")
}

sum() { awk '{ total += $1 } END { print total + 0 }'; }

# build.zig.zon is the version's one home; src/zmeshopt.zig's version() test
# receives it as a build option and fails if the two disagree.
emit version "$(sed -n 's/^ *\.version = "\([^"]*\)".*/\1/p' build.zig.zon)" \
  'version (one home: `build.zig.zon`)'

# The upstream C surface and its Zig mirror. src/abi_check.zig's reverse sweep
# fails the build if any header export lacks an extern, so the two counts can
# only disagree through a bug in this script.
header=libs/meshoptimizer/src/meshoptimizer.h
header_fns=$(grep -cE '^MESHOPTIMIZER_(API|EXPERIMENTAL)' "$header")
emit upstream_entry_points "$header_fns" \
  'upstream C entry points (`MESHOPTIMIZER_API`/`_EXPERIMENTAL` in the vendored header)'

externs=$(grep -hc '^pub extern fn meshopt_' src/c/*.zig | sum)
emit zig_externs "$externs" 'Zig externs (`pub extern fn` in `src/c/*.zig`)'

emit experimental_fns "$(grep -c '^MESHOPTIMIZER_EXPERIMENTAL' "$header")" \
  'of them marked experimental by upstream, bound and labelled'

# What the build reports, not what a grep for `test` finds: a test behind a
# build option would be counted by the grep and never run.
#
# The output is captured before it is parsed, rather than piped straight into
# sed. Piped, a failing build sends its own diagnosis INTO the pipe, `set -e`
# ends this script with nothing on any stream, and ci/check-docs.sh reports
# "generator failed" followed by an empty stderr — a build error rendered as a
# documentation error, naming nothing to act on.
if ! build_log=$(${ZIG} build test --summary all 2>&1); then
  printf '%s\n' "$build_log" >&2
  printf '\nci/measurements.sh: `%s build test` failed, output above.\n' "$ZIG" >&2
  printf 'The test count is what the build reports, so no number here can\n' >&2
  printf 'be recomputed until it passes.\n' >&2
  exit 1
fi
test_count=$(printf '%s\n' "$build_log" |
  sed -n 's/.*run test zmeshopt-tests \([0-9][0-9]*\) pass.*/\1/p' | head -1)
emit zig_tests_run "$test_count" 'Zig tests `zig build test` executes'
emit c_smoke_assertions "$(grep -c '^ *assert(' tests/c_smoke.c)" \
  'assertions in the standalone C smoke test'

# What one configuration compiles.
emit upstream_translation_units \
  "$(grep -cE '^ *"libs/meshoptimizer/src/[a-z]+\.cpp",' build.zig)" \
  'vendored meshoptimizer translation units `build.zig` compiles'
emit zig_source_lines "$(cat src/*.zig src/c/*.zig | wc -l | tr -d ' ')" \
  'Zig source lines (`src/`)'

# One `try` or `expect` per mutation. check-abi-drift.sh counts the same
# declarations and refuses to report success unless it ran that many, so this
# count cannot overstate the proof.
emit abi_drift_mutations "$(grep -cE '^(try|expect) ' ci/check-abi-drift.sh)" \
  'deliberate drifts `ci/check-abi-drift.sh` must refuse'
# From ci/run.sh itself, which names every step it would run and runs none.
# Counting `run` lines instead is wrong: the cross-compilation loop is one
# line and several steps.
emit ci_checks "$(bash ci/run.sh --list | grep -c .)" 'steps `ci/run.sh` runs'
emit ci_cross_targets \
  "$(sed -n '/^for target in/,/^do$/p' ci/run.sh | grep -cE '^ +[a-z0-9_]+-')" \
  'further targets `ci/run.sh` cross-compiles'

#-----------------------------------------------------------------------------
# Output
#-----------------------------------------------------------------------------

# A measurement that silently produces nothing is worse than a wrong one: it
# renders as an empty cell and reads as "not applicable". An empty value here
# is what a changed `zig build` summary format looks like from the outside.
for i in "${!keys[@]}"; do
  if [ -z "${values[$i]}" ]; then
    printf 'measurement %s produced no value; its source has changed shape\n' \
      "${keys[$i]}" >&2
    exit 1
  fi
done

if [ "$MODE" = "--kv" ]; then
  for i in "${!keys[@]}"; do
    printf '%s\t%s\t%s\n' "${keys[$i]}" "${values[$i]}" "${descriptions[$i]}"
  done
  exit 0
fi

if [ "$MODE" = "--markdown" ]; then
  printf '| | |
|---:|---|
'
  for i in "${!keys[@]}"; do
    printf '| **%s** | %s |
' "${values[$i]}" "${descriptions[$i]}"
  done
  exit 0
fi

for i in "${!keys[@]}"; do
  printf '%-26s %8s  %s\n' "${keys[$i]}" "${values[$i]}" "${descriptions[$i]}"
done

if [ "$header_fns" != "$externs" ]; then
  printf '\nupstream_entry_points and zig_externs must match: the reverse sweep\n'
  printf 'in src/abi_check.zig pairs them at build time, so a difference is a\n'
  printf 'bug in this script.\n'
  exit 1
fi
