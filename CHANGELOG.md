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
- The late-float caller-codegen canary (`tests/abi_canary.c` +
  `src/late_float_canary_test.zig`): the affected upstream signatures are
  called through test-only C mirrors and every argument asserted bit-exact,
  because a known Zig backend miscompilation of that shape must turn the suite
  red rather than ship wrong meshes.
- A consumer package (`tests/consumer/`) driving the module and the C artifact
  the way a downstream `b.dependency` does, examples that are built AND run,
  generated README numbers, and the family CI matrix.
