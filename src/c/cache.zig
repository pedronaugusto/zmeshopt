//! meshoptimizer C declarations: vertex cache, overdraw and vertex fetch
//! optimizers.
//!
//! Mirrors the optimizer region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Reorders indices to reduce GPU vertex shader invocations. Call per draw
/// range if the index buffer holds several.
pub extern fn meshopt_optimizeVertexCache(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize) void;

/// Vertex cache optimizer tuned for strip-like orders: worse cache results
/// than `meshopt_optimizeVertexCache`, better strip length and compression.
pub extern fn meshopt_optimizeVertexCacheStrip(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize) void;

/// Vertex cache optimizer for FIFO caches: ~3x faster, inferior results.
/// `cache_size` should be below the actual GPU cache size.
pub extern fn meshopt_optimizeVertexCacheFifo(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize, cache_size: u32) void;

/// Reorders indices to reduce overdraw. `indices` must already be the OUTPUT
/// of `meshopt_optimizeVertexCache`, not the original mesh. `threshold` is
/// how much cache efficiency may degrade (1.05 = up to 5%).
pub extern fn meshopt_optimizeOverdraw(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, threshold: f32) void;

/// Reorders vertices (and rewrites `indices` in place) to reduce GPU memory
/// fetches; returns the number of unique vertices. Single-stream only — for
/// multiple streams use `meshopt_optimizeVertexFetchRemap`.
pub extern fn meshopt_optimizeVertexFetch(destination: *anyopaque, indices: [*]u32, index_count: usize, vertices: *const anyopaque, vertex_count: usize, vertex_size: usize) usize;

/// Generates a vertex fetch remap table instead of reordering directly;
/// returns the number of unique vertices. Apply with the remap functions.
pub extern fn meshopt_optimizeVertexFetchRemap(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize) usize;
