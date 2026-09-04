# Adding surface to zmeshopt

How a function gets bound, written down so every one of them comes out the
same shape. This is the contract a change has to satisfy. Today the surface is
complete — the reverse sweep in `src/abi_check.zig` proves it — so "adding
surface" means a re-vendor brought new functions, and this is what they must
look like.

## The header is the ABI; the shim is not a binding layer

meshoptimizer's entire public surface is `extern "C"` functions in one pure-C
header, so unlike zozz and zjolt there is no `ffi/` layer here: nothing to
write in C++, no static_assert axis, no config-id handshake (no macro changes
a type's layout — see [UPSTREAM.md](UPSTREAM.md)). What does exist is
`src/abi_shim.c`: 9 clang-compiled forwarders re-spelling the signatures
whose CALLER shape Zig 0.16.0 was measured miscompiling — see "The ABI shim
and its canaries" below. The forwarders add no behaviour and are scheduled
for retirement by a gate, not by memory. A new function is:

1. An extern in the matching `src/c/*.zig` region module, mirroring the header
   declaration exactly, with a doc comment that states the sizing contract
   (`destination` must hold N elements) and marks `MESHOPTIMIZER_EXPERIMENTAL`
   functions as such.
2. An idiomatic wrapper in the matching `src/*.zig` area file.
3. A flat re-export from `src/zmeshopt.zig` under the upstream name minus the
   `meshopt_` prefix.
4. A behavioural test that pins a value, not merely "it ran".

`zig build test` then holds the ABI cross-check and the late-float count
pin; `ci/check-coverage.sh` fails if the extern has no idiomatic caller.

## Naming, which is load-bearing

`src/abi_check.zig` pairs the two sides by name with no hand-maintained list,
so a name that breaks convention is a build failure, not a style nit:

| Zig side | C side |
|---|---|
| extern fn `meshopt_simplify` | `meshopt_simplify` (the C name itself) |
| type `Foo` | `meshopt_Foo` |
| enum `EncodeExpMode`'s field `separate` | `meshopt_EncodeExpSeparate` |
| mask `SimplifyOptions`'s field `lock_border` | `meshopt_SimplifyLockBorder` |

Enum and mask types carry an `upstream_prefix` decl; the oracle PascalCases
each field name onto it to reconstruct the C enumerator, because upstream's
option enums are anonymous — there is no C type name to pair against, only
the enumerators themselves. The idiomatic layer re-exports functions under
the prefix-stripped name (`simplify`, `buildMeshlets`), keeping upstream's
camelCase so its documentation stays searchable.

## The idiomatic layer's rules

- **Counts come from slices.** Where the C contract fixes a buffer's length
  (`destination.len == vertex_count` for remap generators), the wrapper takes
  the slice and derives the count; where it cannot (a bound-sized scratch
  buffer), the sizing rule is a `std.debug.assert` with the formula in the doc
  comment. No wrapper takes a count a slice already knows.
- **Vertex streams are `comptime V`.** A wrapper over per-vertex data takes
  `comptime V: type` and `[]const V`, and `src/contract.zig`'s `checkVertex`
  refuses at compile time a `V` whose size or alignment cannot carry the
  leading floats upstream reads, or whose size exceeds the stride ceiling
  every entry point asserts. The C stride is `@sizeOf(V)`.
- **A precondition is carried over whole.** Where upstream asserts a range,
  the wrapper asserts both ends of it, not just the end a caller is likely to
  reach; where it asserts that an index buffer is whole triangles, so does
  every wrapper that takes one.
- **Codec conventions become error unions.** Encoders returning 0 for "buffer
  too small" return `error.BufferTooSmall` or the written prefix slice;
  decoders returning nonzero return `error.Malformed`. Version knobs are
  enums (`IndexCodecVersion`, `VertexCodecVersion`), not bare ints.
- **In-place aliasing is documented where upstream allows it** (the cache,
  overdraw and fetch optimizers), with the upstream file:line that proves it.
- **A C++-only inline helper is reimplemented in Zig**, mirrored operation for
  operation from the header, and listed in `tools/zig_reimpl.txt` with its
  test — `ci/check-coverage.sh` verifies the row names a live `pub fn` and a
  live test.

## The allocator adapter, and where it deviates

`meshopt_setAllocator` is process-global — every thread, the whole library —
and its `deallocate` receives only the pointer. A `std.mem.Allocator` needs
the size back, so `src/memory.zig` stores a size-prefix header ahead of each
block (16-byte aligned, so any downstream alignment assumption upstream makes
still holds).

Upstream's own C++ `meshopt_Allocator` frees LIFO, and an earlier design here
mirrored that with a fixed-depth stack. The prefix header replaced it: it is
correct whether or not upstream keeps that discipline, costs one header per
temporary allocation, and cannot overflow a depth pinned to an
implementation detail. `installZigAllocator` is irreversible by design —
upstream gives no way to read the previous hooks back, so "restore" could
only pretend; the raw `setAllocator` remains for a caller managing hooks
itself.

## The version has one home

`build.zig.zon` `.version` — and nowhere else. zozz mirrors its version into
`ffi/zozz_core.h` because a C consumer needs a version macro; zmeshopt owns no
C header (upstream's carries upstream's version), so the zon field is the
single source. `build.zig` reads it into the options module, `version()`
re-exports it, and a test compares the two so the mirror cannot rot. README's
version cell is generated by `ci/measurements.sh` from the same field.

## The ABI shim and its canaries

Two caller shapes upstream's ABI requires were measured miscompiled by Zig
0.16.0 (this repo's own hosted CI, 2026-09-02): an f32 argument after more
than 6 integer-class parameters arrived as 0 on x86_64-linux under the
self-hosted x86-64 backend, and the all-float 16-byte
`meshopt_CoverageStatistics` return arrived garbled on x86_64-linux under
**both** the self-hosted and LLVM backends and on aarch64-macos under the
LLVM backend, the only one measured there. Windows was measured clean
throughout — its ABI returns a 16-byte struct through a hidden pointer
rather than the float registers the others misclassify. The idiomatic layer
therefore crosses the 9 affected functions through `src/abi_shim.c` — floats first, the struct return as an
out-parameter — on every backend: one code path, tested everywhere. Each
rerouted extern carries its excuse row in `tools/zig_surface_exceptions.txt`.

Three gates hold the seam. `src/abi_check.zig` classifies every signature,
pins the late-float count, and sweeps `src/shim.zig` against `src/abi_shim.h`
both ways. `src/abi_canary_test.zig` hard-asserts the shim shapes arrive
bit-exact on every backend, and its toolchain watch asserts the RAW shapes
still misbehave where they were measured broken — so a Zig release that fixes
a backend fails the watch loudly, and the shim is retired instead of
fossilising. A re-vendor that adds a late-float function fails the pin and
must extend the shim, its prototypes and both canary sets in one change.

### What Zig 0.17 retires, and what it does not

Measured 2026-09-03 against `0.17.0-dev.1978+c961124d9`, by reading the code
each compiler emits for these shapes with the clang Zig ships as the oracle:
both x86-64 halves are fixed, the aarch64 half is not. The late float loads
into `xmm0` rather than `xmm6` under the self-hosted backend, and
`meshopt_CoverageStatistics` comes back in `xmm0:xmm1` rather than `rax:rdx`
under both backends. On aarch64 it still arrives in `x0`/`x1` where clang
uses `s0`-`s3`.

One defect explains every row of the verdict table in
`src/abi_canary_test.zig`: the C ABI classifier does not look through ARRAY
fields. `{ [3]f32, f32 }` is a homogeneous aggregate of four floats and
belongs in the float registers; a struct of four scalar `f32` classifies
correctly on every backend and version measured here, so the array field is
the whole variable. Upstream implemented array fields for x86-64 on
2026-07-27 and has not yet done aarch64 — `test "struct [3]f32"` in Zig's own
`test/c_abi/main.zig` opens by skipping aarch64, arm, hexagon, mips64 and
powerpc, which is where that work is tracked.

None of this is urgent, because the shapes the shim actually uses are
classified correctly by both versions: a leading float and an out-parameter
have nothing for the classifier to get wrong. What 0.17 changes is the
canary. The moment the pin moves, `test (ubuntu-latest)` fails — the
retirement gate firing as designed — and the answer is to flip the two x86-64
verdict cells to `.exact` and delete the 8 late-float forwarders.
`analyzeCoverage`'s reroute stays until aarch64 is implemented upstream.


## Before you call it done

`zig build test` is the bar — it runs the oracle, the canaries, the
behavioural suite, the C smoke test and the examples. `ci/run.sh` before
pushing; `ci/check-abi-drift.sh` if you touched the oracle or the externs,
and on both ABIs (`-Dtarget=x86_64-windows-msvc`) for a release.
