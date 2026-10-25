# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html); before
1.0 the minor is the breaking one.

## [Unreleased]

### Changed

- Builds on Zig 0.17.0, which `build.zig.zon` now requires. The ABI
  cross-check reads the vendored header through the build's translate-c
  step, since 0.17 removes `@cImport`, and walks the 0.17 reflection lists.
- The development gate is preflight's, run with `bay test`: formatting,
  structure layers, lint, documentation drift, the tests under the C
  sanitizer, without it and with the scalar kernels, the shared library, the
  C smoke test, the examples and a consumer build. Every check that was a
  shell script is a Zig program or a test.
- The ABI guard (`src/testing/abi.zig`) returns what drifted instead of
  stopping the build at the first comparison, so its drift proofs are
  ordinary comptime tests, one per kind of drift, that run on every target
  the gate compiles for instead of rewriting the tree and rebuilding. The
  canaries move to `src/testing/canary.zig`, with a test that a mirror
  echoing a wrong value is caught.
- The vendored tree is compared byte for byte against upstream fetched by
  URL and hash at the commit the vendor record names, and `build.zig`'s
  translation units are held to it in both directions.

### Fixed

- An allocation the allocator installed by `installZigAllocator` refused
  came back to upstream as null, which upstream stores and uses unchecked
  (`meshoptimizer.h:1183-1185`): undefined behaviour. It now stops the
  program with a panic naming the size refused and why upstream cannot take
  it. The adapter's unreachable branches stop in every build through
  `aegis.assert.never`, and aegis is a dependency.

### Removed

- `ci/*.sh`, `tools/` and `tests/consumer`. The consumer build is
  preflight's consumer check over `ci/consumer.zig`; the C consumer is the C
  smoke test, which links the same artifact.
- `docs/` from the package's paths: no consumer's build reads it.

## [0.2.0] - 2026-09-04

### Fixed

Precondition fixes only. No signature, ABI or behaviour change for a caller
that was already inside the C contract; a caller that was outside it now gets
a named panic in safe builds where it used to get an upstream abort, a wrong
answer, or a heap write.

- `contract.checkVertex` enforced three of upstream's four stride rules and
  had no way to state the fourth: every position-taking entry point asserts a
  stride of at most `256` bytes, so a vertex struct over that compiled clean
  and aborted inside the C library. It is a `@compileError` now, as the
  vertex codec's own ceiling always was.
- The entry points that read a vertex as opaque bytes rather than as leading
  floats — the remap generator and applier, the fetch optimizer, the fetch
  analyzer — never went through a contract at all, though upstream bounds
  their `vertex_size` at both ends too. `contract.checkVertexSize` states
  that rule: no stride clause, because these read whole vertices.
- The equality-key entry points took a `key_bytes` bounded only against the
  vertex, not against upstream's own `1` to `256`, and their multi-stream
  siblings accepted an empty stream list, a zero-byte key and a key wider
  than the stride it is read at. `streamsSupported` now states the whole
  rule for the three of them.
- The meshlet builders' shared gate kept only the upper half of upstream's
  two-sided limits, so a `max_vertices` of `0`, `1` or `2` and a
  `max_triangles` of `0` reached a builder that cannot fit one triangle. The
  limits are a predicate (`withinMeshletLimits`) rather than a run of
  asserts, because the same contract gates five entry points and a partial
  copy of it was the defect.
- `buildMeshletsBound` forwarded its arguments unchecked, which is the one
  place that cannot: upstream divides by `max_vertices - 2`, so `2` is a
  divide by zero and less than that wraps, and a caller sizes an array from
  whatever comes back. It states its own preconditions now.
- The gate never saw the `meshlets` array at all — the one meshlet
  destination whose size is a computed bound rather than a length upstream
  can derive — so an undersized one was a heap write inside the C builder,
  before the wrapper's slice-out could notice. It is asserted against the
  bound, taken with `min_triangles` for the flexible builders as the header
  requires.
- Whole-mesh index buffers are asserted to be whole triangles wherever
  upstream asserts it, instead of only where a wrapper happened to divide by
  3: the builders, simplifiers, cache and overdraw optimizers, stripifier,
  spatial sort, adjacency, tessellation, provoking, shadow and filter index
  generators, tangent generator, analyzers, opacity measurement, cluster
  bounds and the index codec.

## [0.1.1] - 2026-09-03

### Fixed

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

## [0.1.0] - 2026-09-02

### Added

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

[Unreleased]: https://github.com/pedronaugusto/zmeshopt/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/pedronaugusto/zmeshopt/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/pedronaugusto/zmeshopt/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/pedronaugusto/zmeshopt/releases/tag/v0.1.0
