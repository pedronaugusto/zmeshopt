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
whose CALLER shape Zig 0.16.0's self-hosted backends were measured
miscompiling — see "The ABI shim and its canaries" below. The forwarders add
no behaviour and are scheduled for retirement by a gate, not by memory. A
new function is:

1. An extern in the matching `src/c/*.zig` region module, mirroring the header
   declaration exactly, with a doc comment that states the sizing contract
   (`destination` must hold N elements) and marks `MESHOPTIMIZER_EXPERIMENTAL`
   functions as such.
2. An idiomatic wrapper in the matching `src/*.zig` area file.
3. A flat re-export from `src/zmeshopt.zig` under the upstream name minus the
   `meshopt_` prefix.
4. A behavioural test that pins a value, not merely "it ran".

`zig build test` then holds the whole chain: the ABI cross-check, the
late-float count pin, and `ci/check-coverage.sh` fails if the extern has no
idiomatic caller.

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
  leading floats upstream reads. The C stride is `@sizeOf(V)`.
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
`meshopt_CoverageStatistics` return arrived garbled on x86_64-linux and
aarch64-macos under **both** the self-hosted and LLVM backends. Windows was
measured clean throughout — its ABI returns a 16-byte struct through a
hidden pointer rather than the float registers the others misclassify. The
idiomatic layer therefore crosses the 9 affected
functions through `src/abi_shim.c` — floats first, the struct return as an
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

## Before you call it done

`zig build test` is the bar — it runs the oracle, the canaries, the
behavioural suite, the C smoke test and the examples. `ci/run.sh` before
pushing; `ci/check-abi-drift.sh` if you touched the oracle or the externs,
and on both ABIs (`-Dtarget=x86_64-windows-msvc`) for a release.
