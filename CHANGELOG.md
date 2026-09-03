# Changelog

Each entry says what the old shape could not express, so a port has the reason
and not only the diff. Versions follow [semantic versioning](https://semver.org);
before 1.0 the minor is the breaking one.

## 0.1.1

Documentation and gates only. The library, its ABI and its behaviour are
unchanged from 0.1.0, so an upgrade is a re-pin and nothing else.

- Three claims the tree did not support are corrected: the C smoke test was
  described as running against the counting allocator, which lives in
  `src/memory.zig` and which that test never installs; the struct-return
  miscompile was scoped to the self-hosted backends, while the first
  shim-carrying CI run measured it under LLVM too; and the drift proof's
  four vendored-header mutations were counted as three.
- `ci/measurements.sh` re-derived the generated numbers and compared them,
  but the comparison sat below the `--kv` and `--markdown` exits, so it had
  never run in CI. It runs before the output now. It has never disagreed.
- The C smoke test was compiled with `libs/meshoptimizer` on its include
  path as well as the installed header, so "proves the installed header"
  was not what it proved. The extra path is gone; `linkLibrary` propagates
  what `installHeader` publishes, and `zig build test-c` passes on both.
- Smaller: the retirement gate named as `src/abi_canary_test.zig` rather
  than `src/shim.zig`, `MESHOPTIMIZER_VERSION` cited at its real line, the
  number gate's two blind spots written down, what only the hosted matrix
  covers stated instead of implied, and `.gitignore` covering the `.bak`
  the drift script leaves when interrupted.

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
  return (the LLVM backend too, on both ABIs measured returning it in
  registers).
  The affected functions cross through clang-compiled forwarders on every
  backend, because a wrong argument must be impossible to ship, not merely
  detected. Canaries (`tests/abi_canary.c` + `src/abi_canary_test.zig`)
  hard-assert the shim path bit-exact everywhere, and a toolchain watch
  asserts the raw shapes stay broken where measured — a fixed backend turns
  the suite red with "retire the shim" as the meaning.
- A consumer package (`tests/consumer/`) driving the module and the C artifact
  the way a downstream `b.dependency` does, examples that are built AND run,
  generated README numbers, and the family CI matrix.
