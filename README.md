# zmeshopt

[![CI](https://github.com/pedronaugusto/zmeshopt/actions/workflows/ci.yml/badge.svg)](https://github.com/pedronaugusto/zmeshopt/actions/workflows/ci.yml)

Zig bindings for [meshoptimizer](https://github.com/zeux/meshoptimizer) —
mesh indexing, optimization, simplification, compression, and cluster
(meshlet) building.

- Vendored, pinned upstream meshoptimizer (v1.2). No fork, no patches. See
  [UPSTREAM.md](UPSTREAM.md).
- **Complete.** Every function the upstream header declares is bound — the
  experimental surface included, marked as such — and completeness is a
  compile-time property, not a promise: the ABI cross-check's reverse sweep
  fails the build over an unbound header function.
- **The header is the ABI.** Upstream's public surface is `extern "C"` in
  one pure-C header, so the hand-written Zig externs mirror it directly and
  drift between them is a **build failure**, not a memory-corruption bug:
  every struct field, signature, enumerator and flag bit is cross-checked at
  comptime, with no hand-kept list of what to check. The one C file in
  `src/` is a small ABI shim dodging two measured Zig-backend caller
  miscompiles — itself gate-checked, canary-watched, and scheduled for
  retirement by a failing test rather than by memory (see
  [The ABI guard](#the-abi-guard)).
- An idiomatic slice-based layer over all of it — counts derived from slice
  lengths, `comptime`-typed vertex streams, error unions where upstream
  signals through return codes — plus host allocator injection: upstream's
  temporary allocations can go through your `std.mem.Allocator`.

## Usage

The block below is not written here: it is a region of
[`examples/usage.zig`](examples/usage.zig), which `zig build examples` builds
and RUNS, extracted by `ci/readme_usage.sh` and compared by CI. A snippet in a
README is a claim about how the library is used, and this one is a claim
something executes.

<!-- BEGIN GENERATED ci/readme_usage.sh -->
```zig
const zmeshopt = @import("zmeshopt");

// Route meshoptimizer's temporary allocations through a Zig allocator
// (optional; the default is operator new/delete, and the install is
// process-wide and permanent).
zmeshopt.installZigAllocator(std.heap.page_allocator);

// A 32x32 grid as unindexed triangle soup: 6144 corners, mostly shared.
const soup = try generateGridSoup(arena, 32);

// 1. Index: collapse duplicate vertices, then remap both buffers.
const remap = try arena.alloc(u32, soup.len);
const unique = zmeshopt.generateVertexRemap(Vertex, remap, null, soup);
const vertices = try arena.alloc(Vertex, unique);
const indices = try arena.alloc(u32, soup.len);
zmeshopt.remapVertexBuffer(Vertex, vertices, soup, remap);
zmeshopt.remapIndexBuffer(indices, null, remap);

// 2. Optimize: vertex cache order, then overdraw, then fetch locality.
zmeshopt.optimizeVertexCache(indices, indices, vertices.len);
zmeshopt.optimizeOverdraw(Vertex, indices, indices, vertices, 1.05);
_ = zmeshopt.optimizeVertexFetch(Vertex, vertices, indices, vertices);

const cache = zmeshopt.analyzeVertexCache(indices, vertices.len, 16, 0, 0);

// 3. Simplify: a quarter-size LOD within 1% of the mesh extents.
const lod_buffer = try arena.alloc(u32, indices.len);
const lod = zmeshopt.simplify(Vertex, lod_buffer, indices, vertices, indices.len / 4, 0.01, .{});

// 4. Meshlets for GPU-driven rendering.
const max_vertices = 64;
const max_triangles = 96;
const meshlet_buffer = try arena.alloc(zmeshopt.Meshlet, zmeshopt.buildMeshletsBound(indices.len, max_vertices, max_triangles));
const meshlet_vertices = try arena.alloc(u32, indices.len);
const meshlet_triangles = try arena.alloc(u8, indices.len);
const meshlets = zmeshopt.buildMeshlets(Vertex, meshlet_buffer, meshlet_vertices, meshlet_triangles, indices, vertices, max_vertices, max_triangles, 0.25);
const bounds = zmeshopt.computeMeshletBounds(
    Vertex,
    zmeshopt.meshletVertexSlice(meshlets[0], meshlet_vertices),
    zmeshopt.meshletTriangleSlice(meshlets[0], meshlet_triangles),
    vertices,
);

// 5. Compress both buffers for storage or transmission.
const encoded_vertices_buffer = try arena.alloc(u8, zmeshopt.encodeVertexBufferBound(Vertex, vertices.len));
const encoded_vertices = try zmeshopt.encodeVertexBuffer(Vertex, encoded_vertices_buffer, vertices);
const encoded_indices_buffer = try arena.alloc(u8, zmeshopt.encodeIndexBufferBound(indices.len, vertices.len));
const encoded_indices = try zmeshopt.encodeIndexBuffer(encoded_indices_buffer, indices);
```
<!-- END GENERATED -->

Add it as a dependency and link the module:

```zig
const zmeshopt_dep = b.dependency("zmeshopt", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zmeshopt", zmeshopt_dep.module("zmeshopt"));
```

A C or C++ host takes the library and upstream's own installed header instead:

```zig
exe.root_module.linkLibrary(zmeshopt_dep.artifact("zmeshopt"));  // then #include <meshoptimizer.h>
```

Forward `optimize` as shown. zmeshopt does not turn on Zig's C sanitizer for
you (see [Build hygiene](#build-hygiene)), so a mismatched build mode is a
size difference rather than an unresolved `__ubsan_handle_*` symbol — but a
Debug library inside a release executable is still not what you meant.

## Design

### Counts come from slices

meshoptimizer's C signatures pass every buffer as pointer + count + stride.
The Zig layer keeps the data flow and drops the redundancy: where the C
contract fixes a buffer's length — a remap generator's `destination` has one
entry per input vertex — the wrapper takes the slice and derives the count
from `len`. Where a length is a caller promise the wrapper cannot check at
comptime (a worst-case scratch buffer, sized by a `Bound` function), the rule
is a `std.debug.assert` with the formula in the doc comment, so a violation is
a named panic in safe builds instead of a heap corruption in all of them.

Vertex data is a `comptime V: type` and a `[]const V`: the stride is
`@sizeOf(V)`, and `src/contract.zig` refuses at compile time a `V` that
cannot carry the leading floats upstream reads (too small, misaligned, or not
a multiple of the scalar size). Functions that read only positions take the
same `V` and use its leading three floats, which is exactly upstream's
`vertex_positions` + stride contract.

Upstream's return-code conventions become error unions where they signal
failure — an encoder that returns 0 for "buffer too small" returns
`error.BufferTooSmall`, a decoder that rejects malformed input returns
`error.Malformed` — and stay plain values where they are answers (a count, a
score). Codec format versions are enums, so an invalid version is
unrepresentable rather than an assert inside upstream.

### Allocator injection, honestly scoped

`installZigAllocator` routes upstream's temporary allocations through a
`std.mem.Allocator`. It is process-wide because
[upstream's hook is](https://github.com/zeux/meshoptimizer/blob/v1.2/src/meshoptimizer.h#L1000) —
that is surfaced rather than hidden behind a per-call parameter that could
not be honoured. It is also **irreversible**: upstream gives no way to read
the previous hooks back, so a "restore" could only pretend. Install once, at
startup, before other threads call in; the raw `setAllocator` remains for a C
host passing `malloc`/`free`-shaped functions.

The seam has one wrinkle worth knowing: upstream frees with `deallocate(ptr)`,
no size, while a Zig allocator requires the size back. `src/memory.zig`
bridges that with a size header stored ahead of each block — see
[BINDING.md](BINDING.md) for the design and its trade-offs. The suite's
balance test drives the seam through a counting allocator and requires every
allocation to have been freed, so an unbalanced seam is a test failure.

### The ABI guard

The Zig side hand-writes its `extern` declarations rather than running
translate-c, so the wrapper gets exactly the types it wants and the shipped
module never compiles C. Nothing in either compiler checks that those
declarations still agree with `meshoptimizer.h`, and a `size_t` narrowed to
`c_int` links cleanly and corrupts. `src/abi_check.zig` closes that: a
comptime `@cImport` of the vendored header itself — in the test module only —
compared against `src/c/*.zig` by reflection. Every struct field is paired
**by name** with its own offset; every scalar's size, alignment, signedness
and int-versus-float; every function's arity and full signature, function
pointers signature-deep; every anonymous option enumerator reconstructed by
naming convention and compared by value. A declaration the check cannot
classify is a compile error rather than a silent pass.

The same check sweeps the other direction: a function the header exports that
`src/c/` does not declare — or declares as anything but an extern fn — fails
the build. That sweep is the package's completeness gate; "binds all of
upstream" is enforced, not promised. See [BINDING.md](BINDING.md) for the
naming convention that makes the pairing work.

The guard is the one test here that cannot test itself: a refactor that
quietly makes it vacuous looks exactly like a passing build.
`ci/check-abi-drift.sh` is the answer — deliberate drifts applied one at a
time, each of which must be refused, including the struct-field swap that
leaves every offset unchanged and so defeats any positional comparison, and
four mutations against the coverage gate. It runs as two CI jobs, on the
x86_64-linux-gnu ABI and on MSVC's, because the header is compared *as
preprocessed and laid out for a target*, so a refusal proved on one ABI is
not proved on the other.

One class of hazard lives below anything a declaration can express: Zig
0.16.0 was measured — by this repo's own CI — miscompiling two CALLER shapes
upstream's ABI requires (a float passed after many integer-class parameters,
on the self-hosted x86-64 backend; an all-float small-struct return, under
the LLVM backend as well). The
affected functions cross through `src/abi_shim.c`, clang-compiled forwarders
that re-spell each shape into a measured-safe one, on every backend — one
code path, tested everywhere. Runtime canaries hard-assert the shim path
argument for argument, and a toolchain watch asserts the raw shapes stay
broken where they were measured broken, so a Zig release that fixes a
backend fails the watch — the signal to retire the shim rather than
fossilise it. See [BINDING.md](BINDING.md).

### Build hygiene

- Source lists are explicit, never globs — a re-vendor cannot silently change
  what compiles.
- UBSan is **not** blanket-disabled, and it is **not** on by default either.
  `-Dsanitize_c=true` turns it on and zmeshopt's own CI runs Debug that way.
  It stays off by default because Zig's C sanitizer emits calls into a
  runtime linked only into a compilation that is itself sanitized: a consumer
  who forgets to forward `optimize` would get an `undefined symbol:
  __ubsan_handle_*` link failure naming nothing they can act on. A library
  does not get to decide that its consumers are running a sanitizer.
- `-Dsimd=false` compiles upstream's scalar codec paths
  (`MESHOPTIMIZER_NO_SIMD`). Codegen-only — no type changes layout with it,
  which is why there is no configuration handshake; see
  [UPSTREAM.md](UPSTREAM.md).
- `-Dshared=true` builds the C library as a shared object.
- Build options are declared once and mirrored into a Zig `options` module,
  so the wrapper cannot disagree with how the C++ was compiled.

## Testing

```sh
zig build test
```

runs everything: the ABI cross-check and canaries compile with the suite, the
behavioural tests pin values (cache statistics, simplification error bounds,
codec roundtrips), the C smoke test (`zig build test-c`) proves the installed
header and library stand alone with no Zig in the picture, and the examples
build and RUN. Codec roundtrip tests compare triangles
**rotation-normalized**, because the index codec is free to rotate a
triangle's corners.

```sh
zig build --build-file tests/consumer/build.zig run
```

builds zmeshopt the way a downstream package does — through `b.dependency`,
which resolves the artifact by scanning the dependency's install step and the
header by its installed spelling. Neither is exercised by anything in `src/`,
so both can break while the whole suite stays green. The Zig module and the C
artifact are each driven by a real consumer there.

### By the numbers

<!-- BEGIN GENERATED ci/measurements.sh --markdown -->
| | |
|---:|---|
| **0.1.0** | version (one home: `build.zig.zon`) |
| **85** | upstream C entry points (`MESHOPTIMIZER_API`/`_EXPERIMENTAL` in the vendored header) |
| **85** | Zig externs (`pub extern fn` in `src/c/*.zig`) |
| **8** | of them marked experimental by upstream, bound and labelled |
| **66** | Zig tests `zig build test` executes |
| **8** | assertions in the standalone C smoke test |
| **20** | vendored meshoptimizer translation units `build.zig` compiles |
| **3707** | Zig source lines (`src/`) |
| **22** | deliberate drifts `ci/check-abi-drift.sh` must refuse |
| **23** | steps `ci/run.sh` runs |
| **7** | further targets `ci/run.sh` cross-compiles |
<!-- END GENERATED -->

Not one of those is typed into this file. `ci/measurements.sh` recomputes them
from the tree, `ci/check-docs.sh` regenerates the block and fails the build if
what is committed differs, and the same gate refuses any other hand-written
number in these documents unless `tools/doc_numbers.txt` says why it cannot go
stale. Adding a claim means adding its measurement.

**What the numbers do not say.** A count is a count. Matching extern counts
prove presence, not correctness — the oracle and the behavioural tests hold
that, and `ci/check-coverage.sh` holds the idiomatic layer's reach one extern
at a time. Source lines measure volume, not surface. And the gate itself has
blind spots: a number spelled as a word, a single digit, a number joined to
its neighbour by `-`, `.` or `/` (a date, a byte width), a number inside
`code` — where it is an identifier or a citation rather than a claim — and a
sentence that is wrong without containing a number at all.

### Continuous integration

CI runs the whole suite on **Linux, macOS and Windows**, in every optimize
mode — Debug twice, with the C sanitizer on and off — plus the standalone C
test, the scalar-codec arm, the downstream-consumer build, and on Windows the
MSVC ABI as well as the gnu one. It also cross-compiles the further targets
listed in `ci/run.sh`, verifies the vendored tree byte-for-byte against the
pinned upstream commit, and runs the ABI drift mutation proof on both ABIs.
See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

The same steps run locally, so a failure is reproducible on your machine
before it is a red mark on a pull request. What only the hosted run has is
the suite on the other two operating systems, the MSVC test arm, and the
vendor-integrity job, which needs the network:

```sh
ci/run.sh            # the full matrix
ci/run.sh --quick    # native Debug only, for the inner loop
ci/install-hooks.sh  # run it automatically before every push
```

It reports every failure rather than stopping at the first. The drift proof
runs on this host's ABI; the second arm is opt-in
(`ci/run.sh --drift-target=x86_64-windows-msvc`) because it rebuilds once per
mutation — CI runs it on every push, and a release should run both arms here.

### Platform coverage

| | Suite executed by CI | Compile-checked by CI |
|---|---|---|
| Linux | x86_64 (glibc) | + aarch64, musl |
| macOS | aarch64 | + x86_64 |
| Windows | x86_64, both gnu and MSVC ABI | + aarch64 |

Compiling proves the sources and build graph are portable; only an executed
configuration proves behaviour, which is why the two are separate jobs.

That table describes the matrix, not a promise: **the badge at the top of
this file is the authority on whether those runs have actually happened and
passed.**

## Scope

Everything `meshoptimizer.h` declares, by area: index generation and
remapping (including shadow and adjacency index buffers, tessellation
patches, and the provoking-vertex reorder), vertex cache / overdraw / fetch
optimization, index and vertex buffer compression with their decoders,
per-attribute compression filters and their encoders, simplification
(attribute-aware, sloppy, points, pruning) with scale and error reporting,
triangle strips, efficiency analyzers (cache, overdraw, coverage, fetch),
meshlet building with culling bounds, meshlet compression, cluster
partitioning, spatial sorting and clustering, opacity micromaps, tangent
generation, and quantization — the half-float and exponent helpers as
externs, and the C++-only inline `quantizeUnorm`/`quantizeSnorm` reimplemented
in Zig, held to the header by the coverage ledger
([`tools/zig_reimpl.txt`](tools/zig_reimpl.txt)).

Functions upstream marks experimental are bound and carry the marker in their
doc comments — upstream reserves the right to change them between minor
versions, which is a re-vendor concern the oracle catches, not a reason to be
incomplete. The only exports not bound are the ones not in the header; see
[UPSTREAM.md](UPSTREAM.md).

The idiomatic layer is the intended surface, and `ci/check-coverage.sh`
enforces that it reaches every extern — both directions, so an excuse file
with a stale entry fails too. The raw externs stay public under `zmeshopt.c`
for a caller that wants the C contract verbatim.

Deliberately out of scope: file formats, glTF, and scene handling. Those
belong to a host or to a sibling package — this one binds exactly one
upstream. For glTF documents carrying `EXT_meshopt_compression`, the sibling
[zcgltf](https://github.com/pedronaugusto/zcgltf) parses and this package
decodes; its README documents the pairing contract, and its `tests/interop/`
package runs it end to end, in its CI, against a released zmeshopt.

## Contributing

Issues and pull requests are welcome. Things to know before opening one:

- **`libs/meshoptimizer` is vendored verbatim and must not be edited.**
  Changes there are lost at the next re-vendor. If upstream needs fixing, fix
  it upstream; if zmeshopt needs to work around upstream, do it in `src/` and
  record it in [UPSTREAM.md](UPSTREAM.md).
- **Run `ci/run.sh` before pushing** — or `ci/install-hooks.sh` once, and it
  runs itself. It is the same matrix CI runs.
- **Comments state a contract, not a narrative.** `ci/check-comments.sh`
  enforces two things and will fail a pull request over either: block length
  caps, and the register — documentation, not conversation. The cap never
  justifies dropping a fact: units, ownership, sizing rules, error conditions
  and aliasing guarantees come first; if a block cannot hold them, shorten
  the prose around them.
- [BINDING.md](BINDING.md) is the contract for how surface is shaped.

New source files are added to the explicit lists in `build.zig` deliberately;
there are no globs, so nothing starts compiling by accident.

## Licence

MIT, see [LICENSE](LICENSE). Vendored meshoptimizer is MIT, copyright Arseny
Kapoulkine.
