//! Idiomatic layer: vertex cache, overdraw and vertex fetch optimizers.
//!
//! Slice-based wrappers over `src/c/cache.zig`.

const std = @import("std");
const check = @import("check.zig");
const failure_ = @import("failure.zig");
const c = @import("c.zig").cache;
const contract = @import("contract.zig");

/// Reorders indices to reduce GPU vertex shader invocations. Call per draw
/// range if the index buffer holds several. `destination` may alias `indices`.
pub fn optimizeVertexCache(destination: []u32, indices: []const u32, vertex_count: usize, failure: *failure_.Failure) failure_.Error!void {
    try failure_.held(failure, .optimize_vertex_cache, check.triangles(indices.len));
    try failure_.held(failure, .optimize_vertex_cache, check.room(destination.len, indices.len));
    try failure_.bounded(failure, .optimize_vertex_cache, indices, vertex_count);
    c.meshopt_optimizeVertexCache(destination.ptr, indices.ptr, indices.len, vertex_count);
}

/// Vertex cache optimizer tuned for strip-like orders: worse cache results
/// than `optimizeVertexCache`, better strip length and compression.
pub fn optimizeVertexCacheStrip(destination: []u32, indices: []const u32, vertex_count: usize, failure: *failure_.Failure) failure_.Error!void {
    try failure_.held(failure, .optimize_vertex_cache_strip, check.triangles(indices.len));
    try failure_.held(failure, .optimize_vertex_cache_strip, check.room(destination.len, indices.len));
    try failure_.bounded(failure, .optimize_vertex_cache_strip, indices, vertex_count);
    c.meshopt_optimizeVertexCacheStrip(destination.ptr, indices.ptr, indices.len, vertex_count);
}

/// Vertex cache optimizer for FIFO caches: ~3x faster, inferior results.
/// `cache_size` should be below the actual GPU cache size.
pub fn optimizeVertexCacheFifo(destination: []u32, indices: []const u32, vertex_count: usize, cache_size: u32, failure: *failure_.Failure) failure_.Error!void {
    try failure_.held(failure, .optimize_vertex_cache_fifo, check.triangles(indices.len));
    try failure_.held(failure, .optimize_vertex_cache_fifo, check.room(destination.len, indices.len));
    try failure_.bounded(failure, .optimize_vertex_cache_fifo, indices, vertex_count);
    c.meshopt_optimizeVertexCacheFifo(destination.ptr, indices.ptr, indices.len, vertex_count, cache_size);
}

/// Reorders indices to reduce overdraw. `indices` must already be the OUTPUT
/// of `optimizeVertexCache`. `threshold` is how much cache efficiency may
/// degrade (1.05 = up to 5%). `V`'s first 12 bytes are the position float3.
/// `destination` may alias `indices` (overdrawoptimizer.cpp:284).
pub fn optimizeOverdraw(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V, threshold: f32, failure: *failure_.Failure) failure_.Error!void {
    contract.checkVertex(V, 3);
    try failure_.held(failure, .optimize_overdraw, check.triangles(indices.len));
    try failure_.held(failure, .optimize_overdraw, check.room(destination.len, indices.len));
    try failure_.bounded(failure, .optimize_overdraw, indices, vertices.len);
    c.meshopt_optimizeOverdraw(destination.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), threshold);
}

/// Reorders vertices (rewriting `indices` in place) to reduce GPU memory
/// fetches; returns the unique vertex count. Single-stream only — for
/// multiple streams use `optimizeVertexFetchRemap` plus the remap functions.
/// `destination` may alias `vertices` (vfetchoptimizer.cpp:35).
pub fn optimizeVertexFetch(comptime V: type, destination: []V, indices: []u32, vertices: []const V, failure: *failure_.Failure) failure_.Error!usize {
    contract.checkVertexSize(V);
    try failure_.held(failure, .optimize_vertex_fetch, check.room(destination.len, vertices.len));
    try failure_.bounded(failure, .optimize_vertex_fetch, indices, vertices.len);
    return c.meshopt_optimizeVertexFetch(destination.ptr, indices.ptr, indices.len, vertices.ptr, vertices.len, @sizeOf(V));
}

/// Generates a vertex fetch remap table instead of reordering directly;
/// returns the unique vertex count. `destination.len` is the vertex count.
pub fn optimizeVertexFetchRemap(destination: []u32, indices: []const u32, failure: *failure_.Failure) failure_.Error!usize {
    try failure_.bounded(failure, .optimize_vertex_fetch_remap, indices, destination.len);
    return c.meshopt_optimizeVertexFetchRemap(destination.ptr, indices.ptr, indices.len, destination.len);
}

test optimizeVertexCache {
    var failure: failure_.Failure = .{};
    // A 2x2 quad grid; the optimizer must emit a permutation of the input.
    const indices = [_]u32{ 0, 1, 3, 0, 3, 2, 2, 3, 5, 2, 5, 4 };
    var optimized: [12]u32 = undefined;
    try optimizeVertexCache(&optimized, &indices, 6, &failure);
    var histogram = @as([6]u8, @splat(0));
    for (optimized) |i| histogram[i] += 1;
    for (histogram, 0..) |n, v| {
        var expected: u8 = 0;
        for (indices) |i| expected += @intFromBool(i == v);
        try std.testing.expectEqual(expected, n);
    }
}

test optimizeVertexFetch {
    var failure: failure_.Failure = .{};
    // Indices touch vertices 2 and 0 only; fetch order becomes usage order.
    const vertices = [_][3]f32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 2, 0, 0 } };
    var indices = [_]u32{ 2, 0, 1 };
    var reordered: [3][3]f32 = undefined;
    const unique = try optimizeVertexFetch([3]f32, &reordered, &indices, &vertices, &failure);
    try std.testing.expectEqual(@as(usize, 3), unique);
    try std.testing.expectEqual(@as(f32, 2), reordered[0][0]);
    try std.testing.expectEqual(@as(u32, 0), indices[0]);
}

test optimizeVertexFetchRemap {
    var remap: [3]u32 = undefined;
    const indices = [_]u32{ 2, 0, 1 };
    var failure: failure_.Failure = .{};
    const unique = try optimizeVertexFetchRemap(&remap, &indices, &failure);
    try std.testing.expectEqual(@as(usize, 3), unique);
    try std.testing.expectEqual(@as(u32, 0), remap[2]);
}

test "an index past the remap it fills is refused, naming its position" {
    var failure: failure_.Failure = .{};
    var storage: [4]u32 = undefined;
    try std.testing.expectError(error.OutOfRange, optimizeVertexFetchRemap(storage[0..3], &.{ 2, 0, 3 }, &failure));
    try std.testing.expectEqualSlices(failure_.Frame, &.{.{ .call = .optimize_vertex_fetch_remap, .reason = .index_out_of_range, .at = 2 }}, failure.frames());
}

test "a destination shorter than the index buffer is refused before upstream writes" {
    var failure: failure_.Failure = .{};
    const indices = [_]u32{ 0, 1, 2, 2, 1, 3 };
    var short: [5]u32 = undefined;
    try std.testing.expectError(error.BufferTooSmall, optimizeVertexCache(&short, &indices, 4, &failure));
}

test "an index buffer that is not whole triangles is refused" {
    var failure: failure_.Failure = .{};
    const indices = [_]u32{ 0, 1, 2, 2 };
    var optimized: [4]u32 = undefined;
    try std.testing.expectError(error.NotTriangles, optimizeVertexCache(&optimized, &indices, 3, &failure));
}

test "an index past the vertex count is refused, naming its position" {
    var failure: failure_.Failure = .{};
    var destination: [6]u32 = undefined;
    try std.testing.expectError(error.OutOfRange, optimizeVertexCache(&destination, &.{ 0, 1, 2, 2, 1, 3 }, 3, &failure));
    try std.testing.expectEqualSlices(failure_.Frame, &.{.{ .call = .optimize_vertex_cache, .reason = .index_out_of_range, .at = 5 }}, failure.frames());
}
