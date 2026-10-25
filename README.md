# zmeshopt

[![CI](https://github.com/pedronaugusto/zmeshopt/actions/workflows/ci.yml/badge.svg)](https://github.com/pedronaugusto/zmeshopt/actions/workflows/ci.yml)

Zig bindings for [meshoptimizer](https://github.com/zeux/meshoptimizer):
indexing and remapping, vertex cache and overdraw optimization,
simplification, index and vertex compression, meshlet building, and the
analyzers that measure the results. Upstream is vendored at v1.2 and is
unmodified — see [UPSTREAM.md](UPSTREAM.md).

## Usage

The block below is a region of [`examples/usage.zig`](examples/usage.zig),
which `zig build examples` builds and runs; `ci/readme_usage.sh` extracts it
and CI compares the result against this file.

<!-- BEGIN GENERATED zig build docs -- usage -->
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
const unique = try zmeshopt.generateVertexRemap(Vertex, remap, null, soup);
const vertices = try arena.alloc(Vertex, unique);
const indices = try arena.alloc(u32, soup.len);
try zmeshopt.remapVertexBuffer(Vertex, vertices, soup, remap);
try zmeshopt.remapIndexBuffer(indices, null, remap);

// 2. Optimize: vertex cache order, then overdraw, then fetch locality.
try zmeshopt.optimizeVertexCache(indices, indices, vertices.len);
try zmeshopt.optimizeOverdraw(Vertex, indices, indices, vertices, 1.05);
_ = try zmeshopt.optimizeVertexFetch(Vertex, vertices, indices, vertices);

const cache = try zmeshopt.analyzeVertexCache(indices, vertices.len, 16, 0, 0);

// 3. Simplify: a quarter-size LOD within 1% of the mesh extents.
const lod_buffer = try arena.alloc(u32, indices.len);
const lod = try zmeshopt.simplify(Vertex, lod_buffer, indices, vertices, indices.len / 4, 0.01, .{});

// 4. Meshlets for GPU-driven rendering.
const max_vertices = 64;
const max_triangles = 96;
const meshlet_buffer = try arena.alloc(zmeshopt.Meshlet, try zmeshopt.buildMeshletsBound(indices.len, max_vertices, max_triangles));
const meshlet_vertices = try arena.alloc(u32, indices.len);
const meshlet_triangles = try arena.alloc(u8, indices.len);
const meshlets = try zmeshopt.buildMeshlets(Vertex, meshlet_buffer, meshlet_vertices, meshlet_triangles, indices, vertices, max_vertices, max_triangles, 0.25);
const bounds = try zmeshopt.computeMeshletBounds(
    Vertex,
    zmeshopt.meshletVertexSlice(meshlets[0], meshlet_vertices),
    zmeshopt.meshletTriangleSlice(meshlets[0], meshlet_triangles),
    vertices,
);

// 5. Compress both buffers for storage or transmission.
const encoded_vertices_buffer = try arena.alloc(u8, zmeshopt.encodeVertexBufferBound(Vertex, vertices.len));
const encoded_vertices = try zmeshopt.encodeVertexBuffer(Vertex, encoded_vertices_buffer, vertices);
const encoded_indices_buffer = try arena.alloc(u8, try zmeshopt.encodeIndexBufferBound(indices.len, vertices.len));
const encoded_indices = try zmeshopt.encodeIndexBuffer(encoded_indices_buffer, indices);
```
<!-- END GENERATED -->

## Install

```sh
zig fetch --save git+https://github.com/pedronaugusto/zmeshopt#v0.2.0
```

```zig
const zmeshopt_dep = b.dependency("zmeshopt", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zmeshopt", zmeshopt_dep.module("zmeshopt"));
```

A C or C++ host links the library and includes upstream's own header instead:

```zig
exe.root_module.linkLibrary(zmeshopt_dep.artifact("zmeshopt"));  // then #include <meshoptimizer.h>
```

Requires Zig 0.16.0. zmeshopt has no package dependencies and the vendored C++
is compiled by the Zig toolchain, so there is nothing else to install.

Forward `optimize` as shown. zmeshopt does not turn on Zig's C sanitizer for
you (see [Build options](#build-options)), so a mismatched build mode is a size
difference rather than an unresolved `__ubsan_handle_*` symbol — but a Debug
library inside a release executable is still not what you meant.

## The API

`zmeshopt` re-exports every wrapper flat, under upstream's name minus the
`meshopt_` prefix — `simplify`, `buildMeshlets`, `encodeVertexBuffer` — so
upstream's documentation stays searchable.

| Area | What it covers |
|---|---|
| Indexing | vertex remap generation and application, position remap, shadow and adjacency index buffers, tessellation patches, the provoking-vertex reorder |
| Optimizers | vertex cache (direct, strip and FIFO), overdraw, vertex fetch |
| Simplification | attribute-aware, sloppy, points, pruning, with scale and error reporting |
| Compression | index and vertex codecs with their decoders, the meshlet codec, per-attribute filters in both directions |
| Clusters | meshlet builders and culling bounds, cluster partitioning, spatial sorting and clustering |
| Analyzers | vertex cache, overdraw, coverage, vertex fetch |
| Other | triangle strips, opacity micromaps, tangent generation, quantization |

Every function `meshoptimizer.h` declares at v1.2 has an extern in `src/c/`
and an idiomatic wrapper above it, the experimental surface included; each
experimental function carries the marker in its doc comment, because upstream
reserves the right to change those between minor versions. Both halves are
gated: the reverse sweep in `src/abi_check.zig` fails the build over a header
function with no extern, and `ci/check-coverage.sh` fails over an extern with
no idiomatic caller.

Two things sit outside that. `meshopt_simplifyEdge` and
`meshopt_optimizeVertexCacheTable` have external linkage but no declaration in
the header — upstream's internal seams, and the second takes a C++ type, so it
is not C-callable. `meshopt_quantizeUnorm` and `meshopt_quantizeSnorm` are
C++-only inline helpers with no symbol to bind, so they are reimplemented in
Zig and held to the header by `ci/check-coverage.sh` through
[`tools/zig_reimpl.txt`](tools/zig_reimpl.txt).

The raw externs stay public under `zmeshopt.c` for a caller who wants the C
contract verbatim. One caveat comes with them: the functions listed in
[`tools/zig_surface_exceptions.txt`](tools/zig_surface_exceptions.txt) have a
caller shape the toolchain was measured miscompiling, so calling *those*
through `zmeshopt.c` reproduces the miscompile on the affected targets,
silently. The idiomatic layer routes around it.

zmeshopt handles no file format. For glTF documents carrying
`EXT_meshopt_compression` it supplies the decode half only; see
[docs/interop.md](docs/interop.md).

## Design

### Counts come from slices

meshoptimizer passes every buffer as pointer + count + stride. Where the C
contract fixes a buffer's length — a remap generator's `destination` has one
entry per input vertex — the wrapper takes the slice and derives the count
from `len`. Where the length is a caller promise no type can carry, such as a
worst-case scratch buffer sized by a `Bound` function, the rule is a
`std.debug.assert` with the formula in the doc comment, so a violation is a
named panic in safe builds instead of a heap write in all of them. Both ends
of every range upstream asserts are checked, and so is the whole-triangles
rule on any index buffer that stands for a mesh.

Vertex data is a `comptime V: type` and a `[]const V`; the stride is
`@sizeOf(V)`. `src/contract.zig` refuses at compile time a `V` that cannot
carry the leading floats upstream reads — too small, misaligned, or not a
multiple of the scalar size — or that exceeds the stride ceiling upstream
asserts. Functions that read only positions take the same `V` and use its
leading three floats, which is upstream's `vertex_positions` + stride
contract.

Upstream's return codes become error unions where they signal failure
(`error.BufferTooSmall` from an encoder given too little room,
`error.Malformed` from a decoder given bad input) and stay plain values where
they are answers. Codec format versions are enums, so an invalid version is
unrepresentable rather than an assert inside upstream.

### Allocators

`installZigAllocator` routes upstream's temporary allocations through a
`std.mem.Allocator`. It covers every allocation upstream makes through its own
hook, and nothing else: the hook is process-wide, so the install is too, and
it is irreversible, because upstream gives no way to read the previous hooks
back. Install once at startup, before other threads call in. The raw
`setAllocator` remains for a C host passing `malloc`/`free`-shaped functions.

Upstream frees with `deallocate(ptr)` and no size, while a Zig allocator
requires the size back, so `src/memory.zig` stores a size header ahead of each
block; [BINDING.md](BINDING.md) has the layout and its cost. The suite drives
the seam through a counting allocator and requires every allocation to have
been freed.

### The ABI guard

The externs are hand-written rather than produced by translate-c, so the
wrapper gets the types it wants and the shipped module never compiles C.
Nothing in either compiler checks that those declarations still agree with
`meshoptimizer.h`, and a `size_t` narrowed to `c_int` links cleanly and
corrupts. `src/abi_check.zig` closes that: a comptime `@cImport` of the
vendored header, in the test module only, compared against `src/c/*.zig` by
reflection — every field, signature, enumerator and flag bit, paired by name.
A declaration it cannot classify is a compile error. `ci/check-abi-drift.sh`
proves the guard is not vacuous by drifting the externs deliberately, one
mutation at a time, and requiring each to be refused; it runs on the
linux-gnu ABI and on MSVC's, because the header is compared as laid out for a
target. [docs/abi-guard.md](docs/abi-guard.md) has the details.

Below what any declaration can express, Zig 0.16.0 was measured — by this
repo's CI — miscompiling two caller shapes upstream's ABI requires: a float
passed after many integer-class parameters, and an all-float small-struct
return. The affected functions cross through `src/abi_shim.c`, clang-compiled
forwarders that re-spell each shape into a measured-safe one, on every
backend. Canaries assert the shim path argument for argument, and a toolchain
watch asserts the raw shapes stay broken where they were measured broken, so a
Zig release that fixes a backend turns the suite red and the shim is retired
rather than kept. [BINDING.md](BINDING.md) has the measurements and the single
defect underneath both shapes.

### Build options

- `-Dsanitize_c=true` compiles the C++ with Zig's undefined-behaviour
  sanitizer; zmeshopt's own CI runs Debug both ways. It is off by default
  because the sanitizer emits calls into a runtime linked only into a
  compilation that is itself sanitized, so a consumer who forgets to forward
  `optimize` would get an `undefined symbol: __ubsan_handle_*` link failure
  naming nothing they can act on.
- `-Dsimd=false` compiles upstream's scalar codec paths
  (`MESHOPTIMIZER_NO_SIMD`). Codegen only — no type changes layout with it,
  which is why there is no configuration handshake; see
  [UPSTREAM.md](UPSTREAM.md).
- `-Dshared=true` builds the C library as a shared object.
- Source lists are explicit, never globs, so a re-vendor cannot silently
  change what compiles. Options are declared once and mirrored into a Zig
  `options` module, so the wrapper cannot disagree with how the C++ was
  compiled.

## Platforms

| | Suite executed by CI | Compile-checked by CI |
|---|---|---|
| Linux | x86_64 (glibc) | + aarch64, musl |
| macOS | aarch64 | + x86_64 |
| Windows | x86_64, both the gnu and the MSVC ABI | + aarch64 |

Every job in that matrix passed on run
[`34779620826`](https://github.com/pedronaugusto/zmeshopt/actions/runs/34779620826).

Pending: measured against a Zig 0.17 dev build, both x86-64 miscompiles the
shim works around are fixed, so those forwarders retire at the next toolchain
pin bump — the canary's toolchain watch fails until they do.
`analyzeCoverage`'s reroute stays until Zig's C ABI classifier looks through
array fields on aarch64.

## Testing

```sh
zig build test        # the ABI cross-check, the canaries, the behavioural
                      # suite, and the examples, which are built and run
zig build test-c      # the installed header and library alone, from C
ci/run.sh             # the whole matrix, the same steps CI runs
ci/run.sh --quick     # native Debug only, for the inner loop
ci/install-hooks.sh   # run ci/run.sh before every push
```

The behavioural tests pin values — cache statistics, simplification error
bounds, codec roundtrips — rather than asserting that a call returned. Codec
roundtrips compare triangles rotation-normalized, because the index codec is
free to rotate a triangle's corners.

```sh
zig build --build-file tests/consumer/build.zig run
```

builds zmeshopt the way a downstream package does, through `b.dependency`,
which resolves the artifact by scanning the dependency's install step and the
header by its installed spelling — neither exercised by anything in `src/`.

`ci/run.sh` reports every failure rather than stopping at the first. What only
the hosted run has is the suite on the other two operating systems, the MSVC
test arm, the vendor-integrity job, which needs the network, and the drift
proof's second ABI — locally that one is opt-in
(`ci/run.sh --drift-target=x86_64-windows-msvc`), because it rebuilds once per
mutation.

### By the numbers

<!-- BEGIN GENERATED zig build measurements -->
| | |
|---:|---|
| **0.2.0** | version (one home: `build.zig.zon`) |
| **85** | C entry points (`MESHOPTIMIZER_API` and `MESHOPTIMIZER_EXPERIMENTAL` in the vendored header), each with its Zig extern |
| **8** | of them marked experimental by upstream, bound and labelled |
| **9** | forwarders in `src/abi_shim.c` for the two caller shapes Zig 0.16.0 miscompiled |
| **17** | deliberate drifts the ABI guard must name (`src/testing/abi.zig`) |
| **8** | assertions in the standalone C smoke test |
| **20** | vendored meshoptimizer translation units `build.zig` compiles |
<!-- END GENERATED -->

`ci/measurements.sh` recomputes each of those from the tree and
`ci/check-docs.sh` fails the build if what is committed differs, or if a
top-level document states any other number by hand. A count proves presence,
not correctness; [docs/measurements.md](docs/measurements.md) has what these
do not say and where the gate is blind.

## Contributing

Issues and pull requests are welcome. `libs/meshoptimizer` is vendored
verbatim and must not be edited; run `ci/run.sh` before pushing.
[docs/contributing.md](docs/contributing.md) has the rest,
[BINDING.md](BINDING.md) the contract for how surface is shaped.

## Licence

MIT, see [LICENSE](LICENSE). Vendored meshoptimizer is MIT, copyright Arseny
Kapoulkine.
