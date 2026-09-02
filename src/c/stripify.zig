//! meshoptimizer C declarations: triangle strip conversion.
//!
//! Mirrors the stripifier region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Converts a (vertex-cache-optimized) triangle list to a strip, stitching
/// with `restart_index` (0xffff / 0xffffffff) or, when it is 0, degenerate
/// triangles; returns the strip length. Size `destination` with
/// `meshopt_stripifyBound`.
pub extern fn meshopt_stripify(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize, restart_index: u32) usize;

/// Worst-case output size for `meshopt_stripify`.
pub extern fn meshopt_stripifyBound(index_count: usize) usize;

/// Converts a triangle strip back to a triangle list; returns the list
/// length. Size `destination` with `meshopt_unstripifyBound`.
pub extern fn meshopt_unstripify(destination: [*]u32, indices: [*]const u32, index_count: usize, restart_index: u32) usize;

/// Worst-case output size for `meshopt_unstripify`.
pub extern fn meshopt_unstripifyBound(index_count: usize) usize;
