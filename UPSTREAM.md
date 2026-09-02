# Vendored upstream

`libs/meshoptimizer` is a pinned copy of upstream **meshoptimizer**, unmodified.

| | |
|---|---|
| Source | <https://github.com/zeux/meshoptimizer> |
| Version | 1.2 (`MESHOPTIMIZER_VERSION 1020`, `src/meshoptimizer.h:6`) |
| Tag | `v1.2` |
| Commit | `9d9890c73011d75920af614485296d1e03e95448` |
| Date | 2026-06-29 |
| License | MIT (`libs/meshoptimizer/LICENSE.md`) |

## What was taken, and what was left behind

Taken: the whole of upstream's `src/` directory, **verbatim and entire** — the
20 translation units and the single public header — plus `LICENSE.md`.

| Left out | Reason |
|---|---|
| `demo/`, `tools/` | Upstream's demo and the gltfpack/wasm tooling around the library. |
| `extern/` | Third-party code (cgltf, fast_obj, sdefl and friends) used only by the demo and tools above. None of it is part of the library. |
| `gltf/` | gltfpack, a standalone tool built on the library. |
| `js/` | The JavaScript/WebAssembly distribution. |
| CMake/Bazel/config glue | Superseded by `build.zig`. |

Nothing is excluded from inside `src/`. That is worth stating plainly, because
it is what lets `ci/verify-vendor.sh` diff the vendored tree against upstream
with **no exclusion list at all** — "unmodified" means byte-identical, rather
than identical-modulo-a-list that could itself fall out of date.

Which translation units actually compile is decided explicitly in `build.zig`
(`meshopt_sources`), never by a directory glob — though for this upstream the
answer is "all 20", and the list exists so a re-vendor cannot silently change
that.

## The header is the C ABI

Unlike a C++ upstream, meshoptimizer's entire public surface is
`extern "C"` functions declared in one pure-C header (`src/meshoptimizer.h`).
There is no shim layer in this repository: the hand-written externs in
`src/c/*.zig` mirror that header directly, and `src/abi_check.zig` `@cImport`s
it (in the test module only) to prove the mirror, field by field and function
by function.

No configuration macro changes a type's layout. `MESHOPTIMIZER_NO_SIMD`
changes codegen only, and `MESHOPTIMIZER_NO_WRAPPERS` removes the C++-only
inline template layer (`src/meshoptimizer.h:1031`) that a C consumer never
sees. So there is no config-id handshake here, because there is no
configuration a caller and the library could disagree about.

## Known upstream behaviour

Recorded so a future re-vendor can check whether any of it has changed, and so
the choices made here are not mistaken for omissions.

**Two exported functions are not in the header, and are not bound.**
`meshopt_simplifyEdge` (`src/simplifier.cpp:2344`) and
`meshopt_optimizeVertexCacheTable` (`src/vcacheoptimizer.cpp:169`) have
external linkage but no declaration in `meshoptimizer.h` — the second takes a
`meshopt::VertexScoreTable*`, a C++ type, so it is not even C-callable.
They are upstream's internal seams (the public `meshopt_simplify*` and
`meshopt_optimizeVertexCache*` functions forward to them). The header is the
contract; this binding stops at it.

**The allocator hook is process-global, and its calling convention is a
macro.** `meshopt_setAllocator` (`src/meshoptimizer.h:1000`) swaps the
allocation functions for the whole library, in every thread at once.
`MESHOPTIMIZER_ALLOC_CALLCONV` is `__cdecl` under MSVC and empty elsewhere
(`src/meshoptimizer.h:23-27`) — the same thing on x86-64, where `__cdecl` is
the one calling convention. Upstream's own C++ `meshopt_Allocator` documents
the deallocation order: blocks are freed in reverse allocation order (LIFO),
which is what makes a stack-shaped Zig adapter sound.

**The experimental surface is marked, not separated.**
`MESHOPTIMIZER_EXPERIMENTAL` expands to `MESHOPTIMIZER_API`
(`src/meshoptimizer.h:32-33`); upstream reserves the right to change those
functions between minor versions. They are bound here — completeness is the
point of this package — and each one carries the marker in its doc comment, so
a consumer can grep for what a re-vendor is allowed to break.

## Re-vendoring procedure

`ci/verify-vendor.sh` fetches the pinned commit and diffs it against `libs/`,
so the claim that this copy is unmodified is checked rather than asserted. It
runs as its own CI job. Run it after any step below.

1. Clone upstream at the new tag; copy `src/` and `LICENSE.md` over
   `libs/meshoptimizer/`, re-applying the exclusions above.
2. Update the table at the top of this file, and the three constants at the top
   of `ci/verify-vendor.sh`. The script refuses to run unless the tag and
   commit both appear in this file, so the two cannot drift.
3. Re-check `meshopt_sources` in `build.zig` against the new `src/` listing.
   Adding a source is a deliberate act; the list exists so a re-vendor cannot
   silently change what compiles.
4. `zig build test`. `src/abi_check.zig` fails the build if any bound
   function's signature, any struct's layout or any flag's value has changed —
   and its reverse sweep fails it if the new header declares a function this
   binding does not.
5. Re-read the "known upstream behaviour" section above and check whether any
   of it has changed. If it has, update the binding and the note together.
