# zmeshopt design

zmeshopt binds meshoptimizer, a C++ mesh optimization library with a pure C
interface, for Zig. Its facts are here: how it is built, what upstream does
that it cannot change, and how each claim is checked.

## Layers

Thinnest first, each importing only the ones before it (`ci/layers.zig` is
the map the gate holds):

1. **The externs**, `src/c/*.zig`: one module per region of
   `meshoptimizer.h`, in header order, mirroring every type and function the
   header declares. `src/c.zig` lists them as `modules`, the list the ABI
   check walks.
2. **The forwarders**, `src/shim.zig` over `src/abi_shim.c`: the caller-shape
   seam described under [The ABI shim](#the-abi-shim). `extern fn` appears in
   these two layers and in the test-only `src/testing/` alone.
3. **The contracts**: `src/check.zig`, the boundary's checks;
   `src/failure.zig`, what a refusal leaves for the caller; and
   `src/contract.zig`, the compile-time vertex rules.
4. **The idiomatic layer**, one file per area (`src/remap.zig`,
   `src/simplify.zig`, ...): slices, checked preconditions and refusals,
   plus the allocator adapter (`src/memory.zig`) and the C++-only quantize
   helpers reimplemented in Zig (`src/quantize.zig`).
5. **The bindings**, `src/zmeshopt.zig`: everything above re-exported flat
   under upstream's name minus `meshopt_`, and `zmeshopt.c` for the raw
   surface.

The library is upstream's translation units, listed in `build.zig` rather
than globbed, plus `src/abi_shim.c`. It is static by default; `-Dshared=true`
builds a shared library through upstream's export seam, `MESHOPTIMIZER_API`
(`meshoptimizer.h:17-20`), which the gate builds. The Zig module compiles no
C, and depends on aegis for its refusal frames and its mark for untrusted
input.

Build options, each mirrored into the `zmeshopt_options` module so the Zig
side cannot disagree with how the C++ was compiled:

- `-Dsanitize_c=true` compiles the C++ with Zig's undefined-behaviour
  sanitizer. It is off by default and not tied to `optimize`: the sanitizer
  calls into a runtime linked only into a compilation that is itself
  sanitized, so a consumer who did not forward `optimize` would get an
  undefined `__ubsan_handle_*` symbol naming nothing they can act on.
- `-Dsimd=false` compiles upstream's scalar kernels
  (`MESHOPTIMIZER_NO_SIMD`). Codegen only: no type changes layout with it.
- `-Dshared=true`, above.

`MESHOPTIMIZER_NO_WRAPPERS` is always defined: it drops the header's C++
template wrappers, which re-spell functions the C interface already exports.
No configuration macro changes a type's layout, so there is no configuration
a caller and the library could disagree about.

## The vendored upstream

| | |
|---|---|
| Source | <https://github.com/zeux/meshoptimizer> |
| Version | 1.2 (`MESHOPTIMIZER_VERSION 1020`, `src/meshoptimizer.h:15`) |
| Tag | `v1.2` |
| Commit | `9d9890c73011d75920af614485296d1e03e95448` |
| Commit date | 2026-06-29 |
| License | MIT (`libs/meshoptimizer/LICENSE.md`) |

Taken: the whole of upstream's `src/` directory, every translation unit and
the one public header, and `LICENSE.md`. Left out: `demo/` and `tools/`
(upstream's demo and the gltfpack and wasm tooling), `extern/` (third-party
code those use), `gltf/` (gltfpack), `js/` (the JavaScript distribution), and
upstream's build and repository documentation, which `build.zig` and this
file supersede.

`libs/meshoptimizer` is upstream at that commit, unmodified. `ci/vendor.zig`
(`bay dev check-vendor`) holds that: the development build fetches upstream
at the commit by URL and hash (the dev dependency `meshoptimizer`), and the
check compares every taken path byte for byte with no exclusion list,
refuses anything beside them, requires this file to name the commit
`build.zig.zon` pins, and requires `build.zig` to compile every vendored
translation unit and name none that is missing. `.gitattributes` marks the
tree `-text`, so a Windows checkout does not rewrite its line endings.

### Re-vendoring

1. Copy upstream's `src/` and `LICENSE.md` at the new tag over
   `libs/meshoptimizer/`.
2. Re-pin the dev dependency at the new commit (`bay add --dev --name
   meshoptimizer "git+https://github.com/zeux/meshoptimizer?ref=<tag>#<commit>"`)
   and update the table above; `bay dev check-vendor` refuses a record that
   does not name the pinned commit.
3. Update `meshopt_sources` in `build.zig`; the vendor check refuses a
   translation unit vendored but not compiled.
4. `bay test`. The ABI check fails over any signature, layout or flag that
   changed, and over a header function no extern binds.
5. Re-read [What upstream does](#what-upstream-does-and-what-zmeshopt-does-about-it)
   and update what changed with the binding.

## What upstream does, and what zmeshopt does about it

**Two exported functions are not in the header, and are not bound.**
`meshopt_simplifyEdge` (`src/simplifier.cpp:2344`) and
`meshopt_optimizeVertexCacheTable` (`src/vcacheoptimizer.cpp:169`) have
external linkage and no declaration in `meshoptimizer.h`; the second takes a
`meshopt::VertexScoreTable*`, a C++ type, so it is not C-callable. They are
upstream's internal seams under the public functions. The header is the
contract, and the binding stops at it.

**Two helpers exist only as C++ inline functions.** `meshopt_quantizeUnorm`
and `meshopt_quantizeSnorm` sit behind `#ifdef __cplusplus`
(`meshoptimizer.h:1005-1021`), so there is no symbol to bind and a C host
never had them. `src/quantize.zig` reimplements both operation for
operation; `ci/coverage.zig` reads the header's inline helpers and requires
each to have a Zig declaration and a test on record.

**The experimental surface is marked, not separated.**
`MESHOPTIMIZER_EXPERIMENTAL` expands to `MESHOPTIMIZER_API`
(`meshoptimizer.h:32-33`), and upstream reserves the right to change those
functions between minor versions. They are bound, and each carries the
marker in its doc comment.

**Upstream asserts its preconditions, and its asserts compile out.** A
short destination or a count that is not whole triangles is an `assert` in
upstream's C++, gone in a release build, where the call then writes past the
buffer. zmeshopt checks each precondition before the call, in every build;
see [Refusals](#refusals).

**Three settings are process-wide.** Upstream holds them in globals, so
setting one changes every later call in every thread, and none may be set
while another thread calls in:

- the allocator hook, `meshopt_setAllocator` (`meshoptimizer.h:1000`), with
  no way to read the previous hooks back; see
  [The caller's resources](#the-callers-resources). Its calling convention
  is a macro, `MESHOPTIMIZER_ALLOC_CALLCONV`: `__cdecl` under MSVC, empty
  elsewhere (`meshoptimizer.h:23-27`), which on x86-64 is the one convention
  either way;
- the index codec version every encode writes, `gEncodeIndexVersion`
  (`indexcodec.cpp:16`), which `encodeIndexVersion` sets;
- the vertex codec version every encode that names none writes,
  `gEncodeVertexVersion` (`vertexcodec.cpp:125`), which
  `encodeVertexVersion` sets; `encodeVertexBufferLevel` takes a version per
  call instead.

**A decoder reads bytes from anywhere, and says why it refused.** The index,
vertex and meshlet decoders return `-1` for a header that is not theirs or a
version newer than they read, `-2` for bytes that end before the encoding
does, and `-3` for an encoding that does not end where the bytes do
(`indexcodec.cpp:386-394`, `vertexcodec.cpp:1828-1869`,
`meshletcodec.cpp:366-373`). The frame a refusal pushes names which.

## Refusals

Every call that can refuse takes a `*zmeshopt.Failure` as its last argument
and returns `zmeshopt.Error`, one set for the whole layer: `NotTriangles`,
`BufferTooSmall`, `LengthMismatch` and `OutOfRange` from the boundary's
checks, and `Malformed` for encoded bytes upstream would not decode. A
refusal pushes one `zmeshopt.Frame`, the call (`Call`, upstream's entry point
in snake case) and the reason (`Reason`), so the caller learns which call
refused and why. `Failure` is aegis's `err.Context`, which keeps four frames
and marks a fifth as truncated.

The decoders take their bytes as `zmeshopt.Encoded`, aegis's mark for input
from outside the program, so a parser of untrusted bytes is visible in its
signature. The meshlet decoders take their counts apart from their output
slices, which must have the room upstream writes: it writes whole groups of
four bytes, so each output is its count's bytes rounded up to four.

Two tests in `src/failure.zig` read every module as it is compiled: every
frame pushed inside a public function names that function, and no module
returns one of the set's errors without pushing a frame, nor makes a
`Failure` of its own outside a test.

## The caller's resources

zmeshopt holds no state of its own. Upstream allocates temporaries through
one process-wide hook, by default `operator new` and `delete`.
`setAllocator` routes them through a `std.mem.Allocator`. It is process-wide
because the hook is, and permanent because upstream cannot report the
previous hooks, so a restore could only pretend; set it once at startup,
before other threads call in. The raw hook stays under `zmeshopt.c` for a
host managing the hooks itself.

Upstream frees with `deallocate(ptr)` and no size, and a Zig allocator
needs the size back, so `src/memory.zig` stores a 16-byte header ahead of
each block holding its total size. The header keeps the block 16-aligned, so
no alignment upstream assumes is lowered. It is correct whatever order
upstream frees in (its own `meshopt_Allocator` frees last-in first-out, and
the adapter does not rely on it). Upstream uses every allocation unchecked
(`meshoptimizer.h:1183-1185`), so an allocator that refuses ends the program
with a panic naming the size rather than handing upstream a null. The suite
drives the seam through a counting allocator and requires every allocation
to be freed.

## The ABI check

The externs are hand-written, so nothing in either compiler checks that they
still agree with the header, and a `size_t` narrowed to `c_int` links
cleanly and corrupts. `src/testing/abi.zig` checks it at compile time. The
development build translates `src/abi_shim.h`, which includes the vendored
header (`meshoptimizer_h`, on the test module only), and the check walks
`src/c/` against it by reflection:

- every struct field paired by name with its offset, so two same-sized
  fields swapped are caught though every offset holds;
- every scalar's size, alignment, signedness and kind, an enum or mask by
  its backing integer;
- every function's arity and signature, callbacks signature-deep;
- every enumerator and every mask bit rebuilt from the type's
  `upstream_prefix` and the PascalCased field name, and compared by value;
- `src/shim.zig` against the forwarders' prototypes, both ways.

The sweep runs both ways: a function the header declares that no extern
binds fails the build, so binding every function is a build property. Floors
on the counts keep a sweep that matched nothing from passing. Every
comparison returns what drifted rather than stopping the build, so the
check's own vigilance is proved by tests that hand it one drift each (fields
swapped, a callback parameter widened, a parameter dropped or widened, an
enumerator renumbered, an enum narrowed, mask bits exchanged or renamed, a
header field added, retyped signed or retyped int, a header function no
extern binds or one deleted, a helper named like an export, a shim extern
widened, a forwarder no extern binds) and require it to name the drift. They
are comptime tests, so they hold on every target the gate compiles for, each
with the header laid out for that target. The check and its drift proofs
are a near-copy of zcgltf's.

## The ABI shim

Two caller shapes upstream's interface requires were measured miscompiled by
Zig 0.16.0 in this package's hosted CI (2026-09-02): an `f32` argument after
more than six integer-class parameters arrived as 0 on x86_64-linux under
the self-hosted backend, and the all-float 16-byte
`meshopt_CoverageStatistics` returned by value arrived garbled on
x86_64-linux under both backends and on aarch64-macos under LLVM. Windows
measured exact throughout: its interface returns that struct through a
hidden pointer.

So the functions with those shapes (eight with a late float, and
`meshopt_analyzeCoverage`) cross through `src/abi_shim.c`: forwarders
compiled by clang that take the floats first and return the struct through
an out-parameter, then call upstream. The idiomatic layer calls them on every
backend, so there is one path, tested everywhere. The raw externs stay under
`zmeshopt.c` for a caller who wants the C contract verbatim, and calling
those nine through it reproduces the miscompile where it exists;
`ci/coverage.zig` names each as rerouted.

`src/testing/canary.zig` holds the seam. Its shim canaries pass known values
through C mirrors of the forwarders' shapes and require each to arrive
exactly, on every backend. Its toolchain watch passes them through mirrors of
the raw shapes, against a verdict table per backend and operating system:
where a pair was measured exact it requires exact, where it was measured
broken it requires the miscompile still to be there, so a Zig release that
fixes a backend fails the watch and the shim is retired rather than kept.
The ABI check pins the counts of both shapes, so a re-vendor that brings a
new one is refused until the shim covers it.

**The verdict tables were measured on Zig 0.16.0, and 0.17.0's verdict for
linux and macos is NOT ESTABLISHED.** What is known:

- On Windows under 0.17.0 both shapes arrive exact, as they did on 0.16.0
  (measured, this package's gate).
- Reading the code a 0.17 development build emitted
  (`0.17.0-dev.1978+c961124d9`, 2026-09-03, clang as the oracle) found both
  x86-64 shapes fixed: the late float loads into `xmm0` rather than `xmm6`
  under the self-hosted backend, and the struct returns in `xmm0:xmm1`
  rather than `rax:rdx` under both backends. On aarch64 the struct still
  arrives in `x0`/`x1` where clang uses `s0`-`s3`. That is a read of a
  development build, not a run of 0.17.0.
- One defect accounts for every broken cell: the C ABI classifier does not
  look through array fields. `{ [3]f32, f32 }` is a homogeneous aggregate of
  four floats; four scalar `f32` fields classify correctly on every backend
  and version measured here. Zig's own `test/c_abi/main.zig` opens
  `test "struct [3]f32"` by skipping aarch64 among others (read 2026-09-03).

The shapes the shim itself uses (a leading float, an out-parameter) give the
classifier nothing to get wrong. If the watch fails on linux or macos under
0.17.0, the cells flip to exact and the forwarders it no longer needs are
retired in their own change; the aarch64 struct return keeps
`analyzeCoverage` rerouted until the classifier handles array fields there.

## Binding conventions

The check pairs the two sides by name, so a name off convention fails the
build:

| Zig | C |
|---|---|
| extern `meshopt_simplify` | `meshopt_simplify` |
| type `Meshlet` | `meshopt_Meshlet` |
| `EncodeExpMode.separate` | `meshopt_EncodeExpSeparate` |
| `SimplifyOptions.lock_border` | `meshopt_SimplifyLockBorder` |

Upstream's option enums are anonymous, so a mask is a `packed struct` of
bools whose `upstream_prefix` plus each PascalCased field name rebuilds the
enumerator it is checked against.

The idiomatic layer's rules:

- **Counts come from slices.** Where the C contract fixes a buffer's length
  (a remap generator's `destination` has one entry per vertex), the wrapper
  takes the slice and derives the count. Where it cannot (a scratch buffer
  sized by a `Bound` function), the wrapper checks the slice against the
  bound and the doc comment gives the formula.
- **Vertex streams are `comptime V`.** A wrapper over per-vertex data takes
  `comptime V: type` and `[]const V`; the stride is `@sizeOf(V)`.
  `src/contract.zig` refuses at compile time a `V` that cannot carry the
  leading floats upstream reads, or whose size exceeds the stride ceiling
  every entry point asserts.
- **A precondition is carried over whole.** Where upstream asserts a range,
  the wrapper checks both ends; where it asserts whole triangles, so does
  every wrapper that takes an index buffer. A parameter whose range is known
  at compile time, such as the quantize helpers' bit counts, is a
  compile-time parameter and the range a compile error.
- **Answers stay values.** A refusal is an error with a frame; a count, a
  bound or a statistic is returned. Codec versions are enums.
- **In-place aliasing is documented where upstream allows it** (the cache,
  overdraw and fetch optimizers), with the upstream line that shows it.

A new function is an extern in its region module, a wrapper in its area, a
flat re-export, and a test that pins a value; `ci/coverage.zig` fails an
extern no wrapper calls and no excuse names.

`build.zig.zon`'s version is the version's one home; `version()` reports it
through the build's options module.

## EXT_meshopt_compression

zmeshopt handles no file format. A glTF document carrying
`EXT_meshopt_compression` needs a parser for its buffer views, and the host
decodes each compressed view by its mode and filter with this package's
decoders.

## The bench

`bay dev bench` times simplification, meshlets, coverage, vertex cache order
and both decoders through the idiomatic layer (`bench/binding.zig`), against
the same upstream work looped in C (`bench/baseline.c`), through shakedown in
ReleaseFast. The three calls the idiomatic layer routes through the shim get
a third row looping the forwarder from C, so the hop alone is the difference
of two rows that differ in nothing else. The C twin takes floats first, as
the shim spells them, so no row crosses a shape the shim exists for. The
gate runs every row once; timings are evidence, never a correctness gate.

## Testing

`bay test` runs preflight's gate: formatting, the layer map, glint with the
gated rules, the documentation regions, test imports, package paths, the
version and the changelog, a fuzz target for every parser of untrusted
input, the checks in `ci/`, a consumer build with fetching off, then the
suite three times, against the C++ under Zig's undefined-behaviour
sanitizer, without it, and with the scalar kernels under the sanitizer:

- the ABI check and its drift proofs, and the canaries;
- behavioural tests per area that pin values (cache statistics,
  simplification error bounds, codec round trips) rather than that a call
  returned; index codec round trips compare triangles rotation-normalized,
  since the codec may rotate a triangle's corners;
- refusal tests that pin the error, and for the codecs the frame;
- the fuzz properties in `src/testing/fuzz.zig`, one per decoder and codec
  version reader: whatever bytes arrive and whatever counts are asked for, a
  decoder decodes with no frame or refuses with one, and guard words after
  every destination survive. Under `bay fuzz` Zig's fuzzer drives the same
  properties;
- the C smoke test, which includes `<meshoptimizer.h>` through the
  artifact's installed header with no Zig in the picture, the shared
  library, the examples, built and run, and the bench, each row once.

The development build reaches zmeshopt as a dependency, so the artifact,
header and module tested are the ones a consumer gets. README.md's counts
are generated by `ci/measurements.zig` (`bay dev measurements`), and
`ci/numbers.zig` refuses a number written by hand in a document unless it
says why it cannot go stale. A count proves presence, not correctness: the
ABI check and the behavioural tests hold correctness, and `ci/coverage.zig`
the idiomatic layer's reach, one extern at a time.

## Contributing

- `libs/meshoptimizer` is upstream verbatim; the vendor check refuses an
  edit. Behaviour zmeshopt needs that upstream lacks lives in `src/`, and a
  fix to upstream belongs upstream.
- New source files are added to the explicit lists in `build.zig`; there
  are no globs, so nothing starts compiling by accident.
- Comments state contracts, not narrative; `ci/comments.zig` holds the
  register and the block caps.
- `bay test` is the bar, and the gate is the same in CI.
