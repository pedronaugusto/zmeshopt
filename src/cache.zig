//! Idiomatic layer: vertex cache, overdraw and vertex fetch optimizers.
//!
//! Slice-based wrappers over `src/c/cache.zig`.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").cache;
const contract = @import("contract.zig");

/// Reorders indices to reduce GPU vertex shader invocations. Call per draw
/// range if the index buffer holds several. `destination` may alias `indices`.
pub fn optimizeVertexCache(destination: []u32, indices: []const u32, vertex_count: usize) void {
    assert(destination.len >= indices.len);
    c.meshopt_optimizeVertexCache(destination.ptr, indices.ptr, indices.len, vertex_count);
}

/// Vertex cache optimizer tuned for strip-like orders: worse cache results
/// than `optimizeVertexCache`, better strip length and compression.
pub fn optimizeVertexCacheStrip(destination: []u32, indices: []const u32, vertex_count: usize) void {
    assert(destination.len >= indices.len);
    c.meshopt_optimizeVertexCacheStrip(destination.ptr, indices.ptr, indices.len, vertex_count);
}

/// Vertex cache optimizer for FIFO caches: ~3x faster, inferior results.
/// `cache_size` should be below the actual GPU cache size.
pub fn optimizeVertexCacheFifo(destination: []u32, indices: []const u32, vertex_count: usize, cache_size: u32) void {
    assert(destination.len >= indices.len);
    c.meshopt_optimizeVertexCacheFifo(destination.ptr, indices.ptr, indices.len, vertex_count, cache_size);
}

/// Reorders indices to reduce overdraw. `indices` must already be the OUTPUT
/// of `optimizeVertexCache`. `threshold` is how much cache efficiency may
/// degrade (1.05 = up to 5%). `V`'s first 12 bytes are the position float3.
/// `destination` may alias `indices` (overdrawoptimizer.cpp:284).
pub fn optimizeOverdraw(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V, threshold: f32) void {
    contract.checkVertex(V, 3);
    assert(destination.len >= indices.len);
    c.meshopt_optimizeOverdraw(destination.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), threshold);
}

/// Reorders vertices (rewriting `indices` in place) to reduce GPU memory
/// fetches; returns the unique vertex count. Single-stream only — for
/// multiple streams use `optimizeVertexFetchRemap` plus the remap functions.
/// `destination` may alias `vertices` (vfetchoptimizer.cpp:35).
pub fn optimizeVertexFetch(comptime V: type, destination: []V, indices: []u32, vertices: []const V) usize {
    assert(destination.len >= vertices.len);
    return c.meshopt_optimizeVertexFetch(destination.ptr, indices.ptr, indices.len, vertices.ptr, vertices.len, @sizeOf(V));
}

/// Generates a vertex fetch remap table instead of reordering directly;
/// returns the unique vertex count. `destination.len` is the vertex count.
pub fn optimizeVertexFetchRemap(destination: []u32, indices: []const u32) usize {
    return c.meshopt_optimizeVertexFetchRemap(destination.ptr, indices.ptr, indices.len, destination.len);
}

test optimizeVertexCache {
    // A 2x2 quad grid; the optimizer must emit a permutation of the input.
    const indices = [_]u32{ 0, 1, 3, 0, 3, 2, 2, 3, 5, 2, 5, 4 };
    var optimized: [12]u32 = undefined;
    optimizeVertexCache(&optimized, &indices, 6);
    var histogram = [_]u8{0} ** 6;
    for (optimized) |i| histogram[i] += 1;
    for (histogram, 0..) |n, v| {
        var expected: u8 = 0;
        for (indices) |i| expected += @intFromBool(i == v);
        try std.testing.expectEqual(expected, n);
    }
}

test optimizeVertexFetch {
    // Indices touch vertices 2 and 0 only; fetch order becomes usage order.
    const vertices = [_][3]f32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 2, 0, 0 } };
    var indices = [_]u32{ 2, 0, 1 };
    var reordered: [3][3]f32 = undefined;
    const unique = optimizeVertexFetch([3]f32, &reordered, &indices, &vertices);
    try std.testing.expectEqual(@as(usize, 3), unique);
    try std.testing.expectEqual(@as(f32, 2), reordered[0][0]);
    try std.testing.expectEqual(@as(u32, 0), indices[0]);
}

test optimizeVertexFetchRemap {
    var remap: [3]u32 = undefined;
    const indices = [_]u32{ 2, 0, 1 };
    const unique = optimizeVertexFetchRemap(&remap, &indices);
    try std.testing.expectEqual(@as(usize, 3), unique);
    try std.testing.expectEqual(@as(u32, 0), remap[2]);
}
