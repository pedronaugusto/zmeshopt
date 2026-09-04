//! Idiomatic layer: indexing and remapping.
//!
//! Slice-based wrappers over `src/c/remap.zig`. Counts come from slice
//! lengths wherever the C contract lets them (`destination.len` is the vertex
//! count for the remap generators, because that is exactly what the C API
//! requires it to hold), and the documented sizing rules become assertions.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").remap;
const contract = @import("contract.zig");

pub const Stream = c.Stream;
pub const RemapCallback = c.RemapCallback;

/// Generates a remap table (old vertex -> new vertex, no gaps) from binary
/// vertex equality; returns the unique vertex count. `destination.len` is the
/// vertex count; pass `indices == null` for unindexed input.
pub fn generateVertexRemap(comptime V: type, destination: []u32, indices: ?[]const u32, vertices: []const V) usize {
    contract.checkVertexSize(V);
    assert(destination.len == vertices.len);
    const index_count = if (indices) |ix| ix.len else vertices.len;
    return c.meshopt_generateVertexRemap(destination.ptr, if (indices) |ix| ix.ptr else null, index_count, vertices.ptr, vertices.len, @sizeOf(V));
}

/// Whether the multi-stream entry points can hash these streams: upstream
/// bounds the stream count at both ends, and every stream's key size the same
/// way it bounds one opaque vertex size (indexgenerator.cpp:408-413).
fn streamsSupported(streams: []const Stream) bool {
    if (streams.len < 1 or streams.len > 16) return false;
    for (streams) |s| {
        if (s.size < 1 or s.size > 256 or s.size > s.stride) return false;
    }
    return true;
}

/// `generateVertexRemap` over multiple vertex streams (1 to 16).
/// `destination.len` is the vertex count.
pub fn generateVertexRemapMulti(destination: []u32, indices: ?[]const u32, streams: []const Stream) usize {
    assert(streamsSupported(streams));
    const index_count = if (indices) |ix| ix.len else destination.len;
    return c.meshopt_generateVertexRemapMulti(destination.ptr, if (indices) |ix| ix.ptr else null, index_count, destination.len, streams.ptr, streams.len);
}

/// `generateVertexRemap` with position equality plus an optional user
/// equality callback. `V`'s first 12 bytes are the position float3.
pub fn generateVertexRemapCustom(comptime V: type, destination: []u32, indices: ?[]const u32, vertices: []const V, callback: ?RemapCallback, context: ?*anyopaque) usize {
    contract.checkVertex(V, 3);
    assert(destination.len == vertices.len);
    const index_count = if (indices) |ix| ix.len else vertices.len;
    return c.meshopt_generateVertexRemapCustom(destination.ptr, if (indices) |ix| ix.ptr else null, index_count, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), callback, context);
}

/// Applies a remap table to a vertex buffer; `destination.len` must be the
/// unique vertex count the generating call returned.
pub fn remapVertexBuffer(comptime V: type, destination: []V, vertices: []const V, remap: []const u32) void {
    contract.checkVertexSize(V);
    assert(remap.len == vertices.len);
    c.meshopt_remapVertexBuffer(destination.ptr, vertices.ptr, vertices.len, @sizeOf(V), remap.ptr);
}

/// Applies a remap table to an index buffer; `indices == null` remaps the
/// identity sequence (unindexed input). `destination.len` is the index count.
pub fn remapIndexBuffer(destination: []u32, indices: ?[]const u32, remap: []const u32) void {
    if (indices) |ix| assert(ix.len == destination.len);
    c.meshopt_remapIndexBuffer(destination.ptr, if (indices) |ix| ix.ptr else null, destination.len, remap.ptr);
}

/// EXPERIMENTAL upstream: filters out degenerate and duplicate triangles
/// (opposite windings preserved); returns the remaining index count. The
/// first `key_bytes` of each vertex are the equality key.
pub fn filterIndexBuffer(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V, key_bytes: usize) usize {
    assert(indices.len % 3 == 0);
    assert(destination.len >= indices.len);
    assert(key_bytes >= 1 and key_bytes <= 256 and key_bytes <= @sizeOf(V));
    return c.meshopt_filterIndexBuffer(destination.ptr, indices.ptr, indices.len, vertices.ptr, vertices.len, key_bytes, @sizeOf(V));
}

/// EXPERIMENTAL upstream: `filterIndexBuffer` over multiple streams (1 to
/// 16). `vertex_count` cannot come from a slice here — streams carry no count.
pub fn filterIndexBufferMulti(destination: []u32, indices: []const u32, vertex_count: usize, streams: []const Stream) usize {
    assert(indices.len % 3 == 0);
    assert(destination.len >= indices.len);
    assert(streamsSupported(streams));
    return c.meshopt_filterIndexBufferMulti(destination.ptr, indices.ptr, indices.len, vertex_count, streams.ptr, streams.len);
}

/// Generates an index buffer that maps binary-equivalent vertices (wrt the
/// first `key_bytes` of each) to one representative, for Z pre-pass or
/// shadowmap draws with the original vertex buffer.
pub fn generateShadowIndexBuffer(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V, key_bytes: usize) void {
    assert(indices.len % 3 == 0);
    assert(destination.len >= indices.len);
    assert(key_bytes >= 1 and key_bytes <= 256 and key_bytes <= @sizeOf(V));
    c.meshopt_generateShadowIndexBuffer(destination.ptr, indices.ptr, indices.len, vertices.ptr, vertices.len, key_bytes, @sizeOf(V));
}

/// `generateShadowIndexBuffer` over multiple streams (1 to 16).
pub fn generateShadowIndexBufferMulti(destination: []u32, indices: []const u32, vertex_count: usize, streams: []const Stream) void {
    assert(indices.len % 3 == 0);
    assert(destination.len >= indices.len);
    assert(streamsSupported(streams));
    c.meshopt_generateShadowIndexBufferMulti(destination.ptr, indices.ptr, indices.len, vertex_count, streams.ptr, streams.len);
}

/// Generates a remap table mapping all vertices with the same position to the
/// same existing index, for position-only connectivity.
pub fn generatePositionRemap(comptime V: type, destination: []u32, vertices: []const V) void {
    contract.checkVertex(V, 3);
    assert(destination.len == vertices.len);
    c.meshopt_generatePositionRemap(destination.ptr, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// Converts each triangle to a 6-vertex patch with adjacency information for
/// geometry shaders; `destination.len` must be at least `indices.len * 2`.
pub fn generateAdjacencyIndexBuffer(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V) void {
    contract.checkVertex(V, 3);
    assert(indices.len % 3 == 0);
    assert(destination.len >= indices.len * 2);
    c.meshopt_generateAdjacencyIndexBuffer(destination.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// Converts each triangle to a 12-vertex PN-AEN tessellation patch;
/// `destination.len` must be at least `indices.len * 4`.
pub fn generateTessellationIndexBuffer(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V) void {
    contract.checkVertex(V, 3);
    assert(indices.len % 3 == 0);
    assert(destination.len >= indices.len * 4);
    c.meshopt_generateTessellationIndexBuffer(destination.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// Reorders indices so each triangle's provoking vertex index equals its
/// primitive id; returns the used prefix of `reorder`, which must hold
/// `vertex_count + indices.len / 3` elements worst case.
pub fn generateProvokingIndexBuffer(destination: []u32, reorder: []u32, indices: []const u32, vertex_count: usize) []u32 {
    assert(indices.len % 3 == 0);
    assert(destination.len >= indices.len);
    assert(reorder.len >= vertex_count + indices.len / 3);
    const n = c.meshopt_generateProvokingIndexBuffer(destination.ptr, reorder.ptr, indices.ptr, indices.len, vertex_count);
    return reorder[0..n];
}

test generateVertexRemap {
    // Vertex 3 duplicates vertex 1, so 5 vertices remap to 4 unique.
    const vertices = [_][3]f32{
        .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 0, 0 }, .{ 1, 1, 0 },
    };
    const indices = [_]u32{ 0, 1, 2, 3, 4, 2 };
    var remap: [5]u32 = undefined;
    const unique = generateVertexRemap([3]f32, &remap, &indices, &vertices);
    try std.testing.expectEqual(@as(usize, 4), unique);
    try std.testing.expectEqual(remap[1], remap[3]);

    var new_vertices: [4][3]f32 = undefined;
    remapVertexBuffer([3]f32, new_vertices[0..unique], &vertices, &remap);
    var new_indices: [6]u32 = undefined;
    remapIndexBuffer(&new_indices, &indices, &remap);
    try std.testing.expectEqual(new_indices[1], new_indices[3]);
    for (new_indices) |i| try std.testing.expect(i < unique);
}

test generateVertexRemapMulti {
    const positions = [_][3]f32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 1, 0, 0 } };
    const uvs = [_][2]f32{ .{ 0, 0 }, .{ 1, 1 }, .{ 1, 1 } };
    const streams = [_]Stream{
        .{ .data = &positions, .size = 12, .stride = 12 },
        .{ .data = &uvs, .size = 8, .stride = 8 },
    };
    var remap: [3]u32 = undefined;
    const indices = [_]u32{ 0, 1, 2 };
    const unique = generateVertexRemapMulti(&remap, &indices, &streams);
    try std.testing.expectEqual(@as(usize, 2), unique);
}

test streamsSupported {
    const data: [4]f32 = @splat(0);
    const one = [_]Stream{.{ .data = &data, .size = 12, .stride = 16 }};
    try std.testing.expect(streamsSupported(&one));
    // Both ends of every rule upstream states on a stream: no streams at
    // all, a key of 0 bytes, a key over the ceiling, a key wider than the
    // stride it is read at.
    try std.testing.expect(!streamsSupported(&.{}));
    try std.testing.expect(!streamsSupported(&(one ** 17)));
    try std.testing.expect(!streamsSupported(&.{.{ .data = &data, .size = 0, .stride = 16 }}));
    try std.testing.expect(!streamsSupported(&.{.{ .data = &data, .size = 257, .stride = 512 }}));
    try std.testing.expect(!streamsSupported(&.{.{ .data = &data, .size = 16, .stride = 12 }}));
}

test generateShadowIndexBuffer {
    // Positions equal, other attribute differs: the shadow buffer folds them.
    const Vertex = extern struct { position: [3]f32, uv: [2]f32 };
    const vertices = [_]Vertex{
        .{ .position = .{ 0, 0, 0 }, .uv = .{ 0, 0 } },
        .{ .position = .{ 0, 0, 0 }, .uv = .{ 1, 1 } },
        .{ .position = .{ 1, 0, 0 }, .uv = .{ 0, 0 } },
    };
    const indices = [_]u32{ 0, 1, 2 };
    var shadow: [3]u32 = undefined;
    generateShadowIndexBuffer(Vertex, &shadow, &indices, &vertices, @sizeOf([3]f32));
    try std.testing.expectEqual(shadow[0], shadow[1]);
}

test generateProvokingIndexBuffer {
    const indices = [_]u32{ 0, 1, 2, 2, 1, 3 };
    var destination: [6]u32 = undefined;
    var reorder: [6]u32 = undefined;
    const used = generateProvokingIndexBuffer(&destination, &reorder, &indices, 4);
    try std.testing.expect(used.len >= 2);
    // Each triangle's provoking (first) vertex index equals its primitive id.
    try std.testing.expectEqual(@as(u32, 0), destination[0]);
    try std.testing.expectEqual(@as(u32, 1), destination[3]);
}
