# The ABI guard in detail

`src/abi_check.zig` compares the hand-written externs in `src/c/*.zig` against
a comptime `@cImport` of the vendored `meshoptimizer.h`. The header is imported
in the test module only, so the shipped module still compiles no C. This file
records how the comparison works and how it is proved to work; the short
version is in [the README](../README.md).

## What the comparison covers

- Every struct field is paired **by name** with its own offset, not by
  position. A field-for-field comparison that trusted order would pass a
  header whose fields had been swapped.
- Every scalar's size, alignment, signedness, and int-versus-float class.
- Every function's arity and full signature, function pointers compared
  signature-deep.
- Every anonymous option enumerator, reconstructed from the Zig field name by
  the naming convention in [BINDING.md](../BINDING.md) and compared by value.
  Upstream's option enums are anonymous, so there is no C type name to pair
  against — only the enumerators themselves.

There is no hand-kept list of what to check. A declaration the check cannot
classify is a compile error rather than a silent pass, so a new shape of
declaration has to be taught to the guard before it can ship.

The same check sweeps the other direction: a function the header exports that
`src/c/` does not declare — or declares as anything but an extern fn — fails
the build. That sweep is the package's completeness gate.

## Why it needs a mutation test

The guard is the one test here that cannot test itself. A refactor that
quietly makes it vacuous looks exactly like a passing build, so
`ci/check-abi-drift.sh` applies deliberate drifts one at a time and requires
each to be refused. The set includes the struct-field swap that leaves every
offset unchanged — the mutation that defeats any positional comparison — and
four mutations aimed at the coverage gate rather than at a signature.

`ci/measurements.sh` counts the assertions in the script and publishes the
number in the README; the script refuses to report success unless it ran that
many, so the count cannot overstate the proof.

## Why it runs on two ABIs

`src/abi_check.zig` compares `src/c/*.zig` against the header **as preprocessed
and laid out for a target**. A refusal proved on the x86_64-linux-gnu ABI is
not proved on MSVC's, so the drift proof runs as two CI jobs, the second on a
Windows runner because building for the MSVC ABI needs Microsoft's own
headers. Locally the second arm is opt-in — `ci/run.sh
--drift-target=x86_64-windows-msvc` — because it rebuilds once per mutation,
and `ci/run.sh` is installed as a pre-push hook. A release should run both
arms.
