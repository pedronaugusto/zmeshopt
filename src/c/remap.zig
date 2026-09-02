//! meshoptimizer C declarations: indexing and remapping.
//!
//! Mirrors the indexing/remap region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly. A declaration belongs to the module named after its header region,
//! so there is nothing to decide and nothing to drift. `src/c.zig` lists every
//! one of these modules and is what the ABI cross-check walks.

/// Vertex attribute stream: each element takes `size` bytes, beginning at
/// `data`, with `stride` controlling the spacing between successive elements
/// (`stride >= size`).
pub const Stream = extern struct {
    data: *const anyopaque,
    size: usize,
    stride: usize,
};

/// Per-vertex equality callback for `meshopt_generateVertexRemapCustom`:
/// returns 1 if the vertices at the two indices are equivalent, 0 otherwise.
pub const RemapCallback = *const fn (context: ?*anyopaque, a: u32, b: u32) callconv(.c) c_int;

/// Generates a vertex remap table (old vertex -> new vertex, no gaps) from
/// binary vertex equality; returns the number of unique vertices.
/// `destination` must hold `vertex_count` elements; `indices` may be null for
/// unindexed input.
pub extern fn meshopt_generateVertexRemap(destination: [*]u32, indices: ?[*]const u32, index_count: usize, vertices: *const anyopaque, vertex_count: usize, vertex_size: usize) usize;

/// `meshopt_generateVertexRemap` over multiple vertex streams
/// (`stream_count` must be <= 16).
pub extern fn meshopt_generateVertexRemapMulti(destination: [*]u32, indices: ?[*]const u32, index_count: usize, vertex_count: usize, streams: [*]const Stream, stream_count: usize) usize;

/// `meshopt_generateVertexRemap` with position equality plus an optional
/// user equality callback (`callback` may be null).
/// `vertex_positions` must have a float3 in the first 12 bytes of each vertex.
pub extern fn meshopt_generateVertexRemapCustom(destination: [*]u32, indices: ?[*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, callback: ?RemapCallback, context: ?*anyopaque) usize;

/// Applies a remap table to a vertex buffer. `destination` must hold the
/// unique vertex count returned by the generateVertexRemap call;
/// `vertex_count` is the ORIGINAL count, not the unique one.
pub extern fn meshopt_remapVertexBuffer(destination: *anyopaque, vertices: *const anyopaque, vertex_count: usize, vertex_size: usize, remap: [*]const u32) void;

/// Applies a remap table to an index buffer. `indices` may be null for
/// unindexed input (the identity sequence is remapped).
pub extern fn meshopt_remapIndexBuffer(destination: [*]u32, indices: ?[*]const u32, index_count: usize, remap: [*]const u32) void;

/// EXPERIMENTAL upstream: filters out degenerate and duplicate triangles
/// (opposite windings preserved); returns the remaining index count.
/// The first `vertex_size` bytes of each vertex are the equality key.
pub extern fn meshopt_filterIndexBuffer(destination: [*]u32, indices: [*]const u32, index_count: usize, vertices: *const anyopaque, vertex_count: usize, vertex_size: usize, vertex_stride: usize) usize;

/// EXPERIMENTAL upstream: `meshopt_filterIndexBuffer` over multiple streams
/// (`stream_count` must be <= 16).
pub extern fn meshopt_filterIndexBufferMulti(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize, streams: [*]const Stream, stream_count: usize) usize;

/// Generates an index buffer mapping binary-equivalent vertices (wrt the
/// first `vertex_size` bytes) to the first equivalent vertex, for Z pre-pass
/// or shadowmap rendering with the original vertex buffer.
pub extern fn meshopt_generateShadowIndexBuffer(destination: [*]u32, indices: [*]const u32, index_count: usize, vertices: *const anyopaque, vertex_count: usize, vertex_size: usize, vertex_stride: usize) void;

/// `meshopt_generateShadowIndexBuffer` over multiple streams
/// (`stream_count` must be <= 16).
pub extern fn meshopt_generateShadowIndexBufferMulti(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize, streams: [*]const Stream, stream_count: usize) void;

/// Generates a remap table mapping all vertices with the same position to the
/// same existing index, for position-only connectivity.
pub extern fn meshopt_generatePositionRemap(destination: [*]u32, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) void;

/// Converts each triangle to a 6-vertex patch with adjacency information for
/// geometry shaders. `destination` must hold `index_count * 2` elements.
pub extern fn meshopt_generateAdjacencyIndexBuffer(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) void;

/// Converts each triangle to a 12-vertex PN-AEN tessellation patch.
/// `destination` must hold `index_count * 4` elements.
pub extern fn meshopt_generateTessellationIndexBuffer(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) void;

/// Reorders indices so each triangle's provoking vertex index equals its
/// primitive id, for visibility buffer rendering; returns the size of the
/// reorder table. `reorder` must hold `vertex_count + index_count/3`
/// elements worst case.
pub extern fn meshopt_generateProvokingIndexBuffer(destination: [*]u32, reorder: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize) usize;
