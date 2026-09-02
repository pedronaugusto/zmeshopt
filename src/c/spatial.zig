//! meshoptimizer C declarations: spatial sorting and clustering.
//!
//! Mirrors the spatial sort region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Generates a remap table (old vertex -> new vertex) ordering points for
/// spatial locality; apply with `meshopt_remapVertexBuffer`.
pub extern fn meshopt_spatialSortRemap(destination: [*]u32, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) void;

/// Reorders triangles for spatial locality into a new index buffer; the
/// result can feed other functions such as `meshopt_optimizeVertexCache`.
pub extern fn meshopt_spatialSortTriangles(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) void;

/// Reorders points into spatial clusters of `cluster_size` (only the last
/// chunk is smaller), writing a new index buffer of `vertex_count` elements.
pub extern fn meshopt_spatialClusterPoints(destination: [*]u32, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, cluster_size: usize) void;
