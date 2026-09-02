//! meshoptimizer C declarations: meshlet building, meshlet optimization and
//! cluster bounds.
//!
//! Mirrors the clusterizer region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// A small mesh cluster: an 8-bit micro index buffer (`triangles`) into a
/// 32-bit vertex indirection buffer (`vertices`), both packed into two large
/// arrays; this struct holds the offsets and counts into them. Triangle data
/// occupies `[triangle_offset .. triangle_offset + triangle_count*3)`.
pub const Meshlet = extern struct {
    vertex_offset: u32,
    triangle_offset: u32,
    vertex_count: u32,
    triangle_count: u32,
};

/// Cluster bounding volumes for frustum, backface and occlusion culling.
/// The normal cone test (orthographic): `dot(view, cone_axis) >= cone_cutoff`.
/// NOTE the mixed field types: three trailing `i8` snorm fields (decode as
/// `x / 127.0`) follow the floats — a layout the ABI check covers field by
/// field.
pub const Bounds = extern struct {
    /// Bounding sphere.
    center: [3]f32,
    radius: f32,
    /// Normal cone apex, axis and cutoff (`cos(angle/2)`).
    cone_apex: [3]f32,
    cone_axis: [3]f32,
    cone_cutoff: f32,
    /// Axis and cutoff in 8-bit SNORM.
    cone_axis_s8: [3]i8,
    cone_cutoff_s8: i8,
};

/// Splits a mesh into meshlets; returns the meshlet count. Size `meshlets`
/// with `meshopt_buildMeshletsBound`; `meshlet_vertices` and
/// `meshlet_triangles` need `index_count` elements worst case.
/// `max_vertices <= 256`, `max_triangles <= 512`; `cone_weight` 0 when cone
/// culling is unused, else (0..1] to trade cluster size for culling
/// efficiency.
pub extern fn meshopt_buildMeshlets(meshlets: [*]Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, max_triangles: usize, cone_weight: f32) usize;

/// `meshopt_buildMeshlets` without positions, scanning the index buffer in
/// order; optimize for vertex cache first for best results.
pub extern fn meshopt_buildMeshletsScan(meshlets: [*]Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_count: usize, max_vertices: usize, max_triangles: usize) usize;

/// Worst-case meshlet count for the builders. For the flex/spatial builders
/// pass `min_triangles`, not max.
pub extern fn meshopt_buildMeshletsBound(index_count: usize, max_vertices: usize, max_triangles: usize) usize;

/// `meshopt_buildMeshlets` with min/max triangle counts per meshlet
/// (`min_triangles <= max_triangles <= 512`); clusters over the expected size
/// by more than `split_factor` are split when it is > 0.
pub extern fn meshopt_buildMeshletsFlex(meshlets: [*]Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize, cone_weight: f32, split_factor: f32) usize;

/// Meshlet builder optimizing cluster subdivision for raytracing;
/// `fill_weight` trades cluster fill for SAH quality (0.5 is a safe default).
pub extern fn meshopt_buildMeshletsSpatial(meshlets: [*]Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize, fill_weight: f32) usize;

/// Reorders one meshlet's vertices and triangles for locality. The two
/// pointers refer to THIS meshlet's slices (offset by `vertex_offset` /
/// `triangle_offset` when the builders produced them).
pub extern fn meshopt_optimizeMeshlet(meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, triangle_count: usize, vertex_count: usize) void;

/// `meshopt_optimizeMeshlet` with a compression-oriented `level` ([0, 9];
/// 0 is equivalent to the plain function, ~3 is the compression sweet spot).
/// Levels >= 1 may rotate triangle corners, which changes the provoking
/// vertex and affects OMM data.
pub extern fn meshopt_optimizeMeshletLevel(meshlet_vertices: [*]u32, vertex_count: usize, meshlet_triangles: [*]u8, triangle_count: usize, level: c_int) void;

/// Bounding volumes for a cluster given absolute indices (at most 256 unique
/// vertices, `index_count/3 <= 512`). `vertex_count` is the WHOLE mesh's
/// vertex count.
pub extern fn meshopt_computeClusterBounds(indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) Bounds;

/// Bounding volumes for a built meshlet (its vertex/triangle slices).
pub extern fn meshopt_computeMeshletBounds(meshlet_vertices: [*]const u32, meshlet_triangles: [*]const u8, triangle_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) Bounds;

/// Bounding sphere around points (or spheres, when `radii` is not null);
/// only `center` and `radius` of the result are set, the rest is 0.
pub extern fn meshopt_computeSphereBounds(positions: [*]const f32, count: usize, positions_stride: usize, radii: ?[*]const f32, radii_stride: usize) Bounds;

/// Extracts meshlet-local vertex and triangle indices from absolute cluster
/// indices, such that `vertices[triangles[i]] == indices[i]`; returns the
/// unique vertex count (up to 256; `index_count/3 <= 512`).
pub extern fn meshopt_extractMeshletIndices(vertices: [*]u32, triangles: [*]u8, indices: [*]const u32, index_count: usize) usize;
