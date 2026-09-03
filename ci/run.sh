#!/usr/bin/env bash
#
# zmeshopt — the CI matrix, run locally.
#
# This mirrors .github/workflows/ci.yml (ci/check-mirror.sh holds the claim) so
# a failure can be reproduced and fixed on your own machine instead of in a
# pull request. Install it as a pre-push hook with ci/install-hooks.sh.
#
# What the hosted run has that this cannot: the suite executed on Linux,
# macOS and Windows (this executes it on the host it runs on and
# cross-compiles the rest), the MSVC test arm, and the vendor-integrity job,
# which needs the network.
#
# Usage:
#   ci/run.sh                 # full matrix
#   ci/run.sh --quick         # native Debug only, for the inner loop
#   ci/run.sh --list          # name every step and run none of them
#   ci/run.sh --drift-target=<triple>
#                             # full matrix, and prove the ABI guard fires on
#                             # that ABI too. Out of the default because it
#                             # rebuilds once per mutation and this file is a
#                             # pre-push hook; the hosted abi-drift-msvc job
#                             # runs it on every push, and a release should
#                             # run it here.
#
# Exits non-zero if any step fails, after running every step — a single
# failure should not hide the others.

set -uo pipefail
cd "$(dirname "$0")/.."

# Overridable so a caller can point at a specific toolchain or a wrapper (a
# build lock, a timing shim) without editing this file. ci/check-abi-drift.sh
# reads the same variable. Used unquoted below on purpose: a wrapper is more
# than one word.
ZIG="${ZIG:-zig}"

QUICK=0
DRIFT_TARGET=

# --list names every step this script would run, one per line, and runs none
# of them. ci/measurements.sh counts those lines, so README's step count is
# the number of steps rather than the number of `run` lines: a step inside a
# loop is one line and several steps.
LIST=0

for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    --list) LIST=1 ;;
    --drift-target=*) DRIFT_TARGET=${arg#*=} ;;
    *) printf 'ci/run.sh: unknown argument %s
' "$arg" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
else
  RED=; GREEN=; DIM=; BOLD=; OFF=
fi

PASSED=0
FAILED=0
FAILED_NAMES=()

# run <name> <command...>
run() {
  local name="$1"; shift
  if [ $LIST -eq 1 ]; then printf '%s\n' "$name"; return 0; fi
  printf '  %-46s' "$name"
  local start output status
  start=$(date +%s)
  output=$("$@" 2>&1)
  status=$?
  local elapsed=$(( $(date +%s) - start ))

  if [ $status -eq 0 ]; then
    printf '%sok%s %s(%ds)%s\n' "$GREEN" "$OFF" "$DIM" "$elapsed" "$OFF"
    PASSED=$((PASSED + 1))
  else
    printf '%sFAILED%s %s(%ds)%s\n' "$RED" "$OFF" "$DIM" "$elapsed" "$OFF"
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$name")
    printf '%s' "$output" | sed 's/^/      | /' | head -40
  fi
}

section() { [ $LIST -eq 1 ] || printf '\n%s%s%s\n' "$BOLD" "$1" "$OFF"; }

[ $LIST -eq 1 ] ||
  printf '%szmeshopt local CI%s  %s%s%s\n' "$BOLD" "$OFF" "$DIM" "$($ZIG version)" "$OFF"

#-----------------------------------------------------------------------------
section 'Hygiene'
#-----------------------------------------------------------------------------

# Only our own Zig sources: libs/meshoptimizer is vendored verbatim and must
# not be reformatted, or the next re-vendor becomes an unreadable diff.
run 'zig fmt (src, examples, tests, build.zig)' \
  $ZIG fmt --check src examples tests/consumer build.zig

# Comment blocks stay short and stay out of the narrative register.
run 'comment standard' ci/check-comments.sh

# Every extern has an idiomatic caller or a reasoned excuse, both directions,
# and the two reimplemented inline helpers have a ledger row with a live test.
run 'coverage (Zig surface, both directions)' ci/check-coverage.sh

# Every number README.md publishes, recomputed and compared, and no other
# number in any document written by hand. It builds once (the test count is
# what the build reports, not a grep), so it sits with the tests rather than
# with the one-second checks above.
run 'documented numbers' ci/check-docs.sh

# CI runs the scripts in ci/ by path. One committed without its executable bit
# fails there and nowhere else, because every local runner invokes bash first.
run 'every committed script is executable' ci/check-executable.sh

# .gitignore says what does not belong in the history. Being tracked overrides
# every rule in it, so a blanket `git add -A` can put a fetched package or a
# build directory into a public clone forever with nothing to say so.
run 'nothing this repository ignores is tracked' ci/check-ignored.sh

# The claim at the top of this file, held rather than stated.
run 'ci/run.sh mirrors the workflow' ci/check-mirror.sh

#-----------------------------------------------------------------------------
section 'Tests — native'
#-----------------------------------------------------------------------------

# The C sanitizer is opt-in — a library must not force its runtime into a
# consumer's link — so zmeshopt's own Debug run asks for it explicitly. This
# is the run that would catch undefined behaviour reachable from our tests.
run 'test Debug (UBSan on)' \
  $ZIG build test -Doptimize=Debug -Dsanitize_c=true

run 'test Debug (UBSan off)' \
  $ZIG build test -Doptimize=Debug -Dsanitize_c=false

if [ $QUICK -eq 0 ]; then
  for mode in ReleaseSafe ReleaseFast ReleaseSmall; do
    run "test $mode" $ZIG build test -Doptimize="$mode" -Dsanitize_c=false
  done

  # The C boundary on its own, with no Zig in the picture.
  run 'test-c (C ABI standalone)' $ZIG build test-c

  # -Dsimd=false selects upstream's scalar codec paths (codegen-only, no ABI
  # effect); nothing above compiles them.
  run 'test -Dsimd=false (scalar codecs)' \
    $ZIG build test -Dsimd=false -Doptimize=Debug -Dsanitize_c=true

  # Consuming zmeshopt as a dependency is a different code path from building
  # it — artifact registration and installed-header spelling are invisible to
  # the in-repo suite. See tests/consumer/build.zig.
  run 'consumer (module + artifact)' \
    $ZIG build --build-file tests/consumer/build.zig run

  #---------------------------------------------------------------------------
  section 'ABI'
  #---------------------------------------------------------------------------

  # Mutation test for the ABI cross-check itself — see the script's own header
  # for why a check that guards everything else needs one. It rebuilds once
  # per mutation, which is why it is out of the --quick loop.
  run 'abi drift (mutation proof)' ci/check-abi-drift.sh

  # The same proof under a second ABI, opt-in. src/abi_check.zig compares
  # src/c/*.zig against @cImport of the header as preprocessed and laid out
  # FOR A TARGET, so the run above proves the guard fires on this host's ABI
  # and says nothing about another.
  [ -z "$DRIFT_TARGET" ] ||
    run "abi drift ($DRIFT_TARGET)" ci/check-abi-drift.sh -Dtarget="$DRIFT_TARGET"
fi

#-----------------------------------------------------------------------------
if [ $QUICK -eq 0 ]; then
section 'Cross-compilation'
#-----------------------------------------------------------------------------

# Compile-only. These prove the sources and build graph are portable; the
# tests above are what prove behaviour, on this host. CI executes the suite on
# Linux, macOS and Windows as well.
for target in \
  x86_64-linux-gnu \
  aarch64-linux-gnu \
  x86_64-linux-musl \
  x86_64-windows-gnu \
  aarch64-windows-gnu \
  x86_64-macos \
  aarch64-macos
do
  run "build $target" $ZIG build -Dtarget="$target"
done

# x86_64-windows-msvc is absent here because it needs the Microsoft standard
# library, which a non-Windows host does not have. CI covers it natively on a
# Windows runner.

#-----------------------------------------------------------------------------
section 'Build configurations'
#-----------------------------------------------------------------------------

run 'shared library' $ZIG build -Dshared=true
fi

#-----------------------------------------------------------------------------
[ $LIST -eq 0 ] || exit 0
printf '\n'
if [ $FAILED -eq 0 ]; then
  printf '%s%d passed, 0 failed%s\n' "$GREEN" "$PASSED" "$OFF"
  exit 0
fi

printf '%s%d passed, %d FAILED%s\n' "$RED" "$PASSED" "$FAILED" "$OFF"
for name in "${FAILED_NAMES[@]}"; do
  printf '  %s- %s%s\n' "$RED" "$name" "$OFF"
done
exit 1
