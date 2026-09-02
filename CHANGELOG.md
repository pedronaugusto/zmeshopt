# Changelog

Each entry says what the old shape could not express, so a port has the reason
and not only the diff. Versions follow [semantic versioning](https://semver.org);
before 1.0 the minor is the breaking one.

## 0.1.0

First release. Complete bindings for meshoptimizer v1.2 — every function the
header declares, the experimental surface included — with:

- Hand-written externs (`src/c/*.zig`, one module per header region) proved
  against the vendored header by a comptime reflective cross-check
  (`src/abi_check.zig`) whose reverse sweep makes completeness a build
  property, and whose own vigilance is proved by `ci/check-abi-drift.sh`.
- An idiomatic slice-based layer over all of it: counts derived from slice
  lengths, `comptime`-typed vertex streams, error unions for the codec
  conventions, and a Zig-allocator adapter for upstream's process-global
  allocation hook.
- An ABI shim (`src/abi_shim.c`) for the two caller shapes Zig 0.16.0 was
  measured miscompiling — a float after more than 6 integer-class parameters
  (self-hosted x86-64 backend), and the all-float `CoverageStatistics`
  return (the LLVM backend too, everywhere it crosses in registers).
  The affected functions cross through clang-compiled forwarders on every
  backend, because a wrong argument must be impossible to ship, not merely
  detected. Canaries (`tests/abi_canary.c` + `src/abi_canary_test.zig`)
  hard-assert the shim path bit-exact everywhere, and a toolchain watch
  asserts the raw shapes stay broken where measured — a fixed backend turns
  the suite red with "retire the shim" as the meaning.
- A consumer package (`tests/consumer/`) driving the module and the C artifact
  the way a downstream `b.dependency` does, examples that are built AND run,
  generated README numbers, and the family CI matrix.
