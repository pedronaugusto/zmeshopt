# zmeshopt

Zig bindings for [meshoptimizer](https://github.com/zeux/meshoptimizer), a
mesh optimization library: indexing and remapping, vertex cache, overdraw and
fetch optimization, simplification, index, vertex and meshlet compression,
meshlet building, and the analyzers that measure the results.

## Usage

The block below is a region of [`examples/usage.zig`](examples/usage.zig),
which the tests build and run; the gate fails if this copy has drifted from
it.

<!-- BEGIN GENERATED zig build docs -- usage -->
```zig
const zmeshopt = @import("zmeshopt");

// Route meshoptimizer's temporary allocations through a Zig allocator
// (optional; the default is operator new/delete, and the setting is
// process-wide and permanent).
zmeshopt.setAllocator(std.heap.page_allocator);

// A call that refuses leaves a frame here naming the call and why.
var failure: zmeshopt.Failure = .{};

// A 32x32 grid as unindexed triangle soup: 6144 corners, mostly shared.
const soup = try generateGridSoup(arena, 32);

// 1. Index: collapse duplicate vertices, then remap both buffers.
const remap = try arena.alloc(u32, soup.len);
const unique = try zmeshopt.generateVertexRemap(Vertex, remap, null, soup, &failure);
const vertices = try arena.alloc(Vertex, unique);
const indices = try arena.alloc(u32, soup.len);
try zmeshopt.remapVertexBuffer(Vertex, vertices, soup, remap, &failure);
try zmeshopt.remapIndexBuffer(indices, null, remap, &failure);

// 2. Optimize: vertex cache order, then overdraw, then fetch locality.
try zmeshopt.optimizeVertexCache(indices, indices, vertices.len, &failure);
try zmeshopt.optimizeOverdraw(Vertex, indices, indices, vertices, 1.05, &failure);
_ = try zmeshopt.optimizeVertexFetch(Vertex, vertices, indices, vertices, &failure);

const cache = try zmeshopt.analyzeVertexCache(indices, vertices.len, 16, 0, 0, &failure);

// 3. Simplify: a quarter-size LOD within 1% of the mesh extents.
const lod_buffer = try arena.alloc(u32, indices.len);
const lod = try zmeshopt.simplify(Vertex, lod_buffer, indices, vertices, indices.len / 4, 0.01, .{}, &failure);

// 4. Meshlets for GPU-driven rendering.
const max_vertices = 64;
const max_triangles = 96;
const meshlet_buffer = try arena.alloc(zmeshopt.Meshlet, try zmeshopt.buildMeshletsBound(indices.len, max_vertices, max_triangles, &failure));
const meshlet_vertices = try arena.alloc(u32, indices.len);
const meshlet_triangles = try arena.alloc(u8, indices.len);
const meshlets = try zmeshopt.buildMeshlets(Vertex, meshlet_buffer, meshlet_vertices, meshlet_triangles, indices, vertices, max_vertices, max_triangles, 0.25, &failure);
const bounds = try zmeshopt.computeMeshletBounds(
    Vertex,
    zmeshopt.meshletVertexSlice(meshlets[0], meshlet_vertices),
    zmeshopt.meshletTriangleSlice(meshlets[0], meshlet_triangles),
    vertices,
    &failure,
);

// 5. Compress both buffers for storage or transmission.
const encoded_vertices_buffer = try arena.alloc(u8, zmeshopt.encodeVertexBufferBound(Vertex, vertices.len));
const encoded_vertices = try zmeshopt.encodeVertexBuffer(Vertex, encoded_vertices_buffer, vertices, &failure);
const encoded_indices_buffer = try arena.alloc(u8, try zmeshopt.encodeIndexBufferBound(indices.len, vertices.len, &failure));
const encoded_indices = try zmeshopt.encodeIndexBuffer(encoded_indices_buffer, indices, &failure);
```
<!-- END GENERATED -->

## Install

Requires Zig 0.17.0:

```sh
zig fetch --save git+https://github.com/pedronaugusto/zmeshopt#main
```

Then in `build.zig`:

```zig
const zmeshopt_dep = b.dependency("zmeshopt", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zmeshopt", zmeshopt_dep.module("zmeshopt"));
```

Forward `optimize` as shown, or a release executable links a Debug library.
A C or C++ host links the library and includes upstream's own header, which
the artifact installs:

```zig
exe.root_module.linkLibrary(zmeshopt_dep.artifact("zmeshopt"));  // then #include <meshoptimizer.h>
```

zmeshopt depends on aegis, which its manifest pins; the Zig toolchain
compiles the vendored C++.

## Features

- Every function `meshoptimizer.h` declares is bound, the experimental ones
  included and marked, and every struct and option enum is mirrored under
  Zig names (`meshopt_Meshlet` is `Meshlet`; option masks are packed structs
  of bools). A compile-time check fails the build if a layout, signature,
  enumerator or flag drifts from the header, or if a header function is not
  bound.
- An idiomatic layer over every extern, re-exported flat under upstream's
  name minus `meshopt_`: counts come from slices, and vertex streams are a
  `comptime` vertex type whose stride the compiler checks.
- Upstream's preconditions, which upstream only asserts, are checked before
  every call in every build. A call that refuses returns `zmeshopt.Error`
  and pushes a frame onto the caller's `zmeshopt.Failure` naming the call
  and the reason, a decoder's telling apart a foreign header, truncated
  bytes and an encoding that does not end where the bytes do.
- The decoders take their bytes as `zmeshopt.Encoded`, aegis's mark for
  untrusted input, and each has a fuzz target.
- Upstream's temporary allocations can go through any `std.mem.Allocator`
  (`setAllocator`). Upstream's hook is process-wide, so the setting is too,
  as are the codec versions `encodeIndexVersion` and `encodeVertexVersion`
  set.
- The C++-only helpers `quantizeUnorm` and `quantizeSnorm` reimplemented in
  Zig.
- meshoptimizer v1.2 vendored in `libs/meshoptimizer`, unmodified; a check
  proves it byte for byte against upstream at the pinned commit.
- Build options: `-Dshared=true` for a shared library, `-Dsimd=false` for
  upstream's scalar kernels, `-Dsanitize_c=true` for the C++ under Zig's
  undefined-behaviour sanitizer.

| | |
|---|---|
| Indexing | vertex remap generation and application, position remap, shadow, adjacency, tessellation and provoking-vertex index buffers |
| Optimizers | vertex cache (direct, strip and FIFO), overdraw, vertex fetch |
| Simplification | attribute-aware, with update, sloppy, points, pruning, scale |
| Compression | index, index sequence, vertex and meshlet codecs, attribute filters both ways |
| Clusters | meshlet builders, cluster and sphere bounds, partitioning, spatial sorting and clustering |
| Analyzers | vertex cache, vertex fetch, overdraw, coverage |
| Other | triangle strips, opacity micromaps, tangents, quantization |
| The raw C surface | `zmeshopt.c` |

Nine functions whose caller shapes Zig 0.16.0 miscompiled on linux and macos
cross through clang-compiled forwarders, which the idiomatic layer uses on
every target; calling those nine through `zmeshopt.c` directly bypasses the
forwarders. The forwarders' verdicts were measured on Zig 0.16.0; whether
0.17.0 still needs them on linux and macos is not established. zmeshopt
handles no file format. [docs/design.md](docs/design.md) has the forwarders
and the tests that hold them, the refusals, what upstream does that the
binding cannot change, and how the vendored copy is checked and updated.

## Testing

```sh
bay test
```

runs the gate: formatting, structure, lint and documentation, the checks in
`ci/`, a consumer build, and the suite three times, against the C++ under
Zig's undefined-behaviour sanitizer, without it, and with the scalar kernels.
The suite holds the ABI check with a test for each kind of drift it must
name, the forwarder canaries, behavioural tests per area that pin values,
the decoders' fuzz properties, the C smoke test against the installed
header, the shared library, the examples, and the bench, each row once.
`bay dev bench` times simplification, meshlets, coverage, vertex cache order
and both decoders against the same upstream work called directly from C.

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

## Licence

MIT, see [LICENSE](LICENSE). Vendored meshoptimizer is MIT, copyright Arseny
Kapoulkine.
