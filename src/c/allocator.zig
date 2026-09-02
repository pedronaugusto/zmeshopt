//! meshoptimizer C declarations: the allocation hook.
//!
//! Mirrors the allocator region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.
//!
//! `MESHOPTIMIZER_ALLOC_CALLCONV` is `__cdecl` under MSVC and empty
//! elsewhere (`meshoptimizer.h:23-27`) — on x86-64 both spell the one
//! C calling convention, which is what `callconv(.c)` produces.

pub const AllocateFn = *const fn (size: usize) callconv(.c) ?*anyopaque;
pub const DeallocateFn = *const fn (ptr: ?*anyopaque) callconv(.c) void;

/// Replaces operator new/delete for ALL temporary allocations in the library,
/// process-wide, in every thread at once. NOT thread safe: must not run
/// concurrently with any other meshopt_ function. Allocate/deallocate are
/// always called in stack (LIFO) order — the last pointer allocated is the
/// first deallocated. See `src/memory.zig` for the Zig-allocator adapter
/// built on that contract.
pub extern fn meshopt_setAllocator(allocate: AllocateFn, deallocate: DeallocateFn) void;
