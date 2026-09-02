//! Idiomatic layer: spatial sorting and clustering.
//!
//! Slice-based wrappers over `src/c/spatial.zig`.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").spatial;
const contract = @import("contract.zig");

/// Generates a remap table (old vertex -> new vertex) ordering points for
/// spatial locality; apply with `remapVertexBuffer`. `destination.len` is the
/// vertex count.
pub fn spatialSortRemap(comptime V: type, destination: []u32, vertices: []const V) void {
    contract.checkVertex(V, 3);
    assert(destination.len == vertices.len);
    c.meshopt_spatialSortRemap(destination.ptr, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// Reorders triangles for spatial locality into a new index buffer; the
/// result can feed other optimizers such as `optimizeVertexCache`.
pub fn spatialSortTriangles(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V) void {
    contract.checkVertex(V, 3);
    assert(destination.len >= indices.len);
    c.meshopt_spatialSortTriangles(destination.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// Reorders points into spatial clusters of `cluster_size` (only the last
/// chunk is smaller), writing an index buffer of `vertices.len` elements.
pub fn spatialClusterPoints(comptime V: type, destination: []u32, vertices: []const V, cluster_size: usize) void {
    contract.checkVertex(V, 3);
    assert(destination.len == vertices.len);
    c.meshopt_spatialClusterPoints(destination.ptr, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), cluster_size);
}

test spatialSortRemap {
    const vertices = [_][3]f32{ .{ 0, 0, 0 }, .{ 50, 0, 0 }, .{ 0.1, 0, 0 }, .{ 50.1, 0, 0 } };
    var remap: [4]u32 = undefined;
    spatialSortRemap([3]f32, &remap, &vertices);
    // A valid remap is a permutation...
    var seen = [_]bool{false} ** 4;
    for (remap) |i| seen[i] = true;
    for (seen) |s| try std.testing.expect(s);
    // ...and spatial neighbors land next to each other.
    const distance_01 = @max(remap[0], remap[2]) - @min(remap[0], remap[2]);
    try std.testing.expectEqual(@as(u32, 1), distance_01);
}

test spatialSortTriangles {
    const vertices = [_][3]f32{
        .{ 0, 0, 0 },  .{ 1, 0, 0 },  .{ 0, 1, 0 },
        .{ 90, 0, 0 }, .{ 91, 0, 0 }, .{ 90, 1, 0 },
    };
    const indices = [_]u32{ 0, 1, 2, 3, 4, 5 };
    var sorted: [6]u32 = undefined;
    spatialSortTriangles([3]f32, &sorted, &indices, &vertices);
    // Triangles stay intact (each output triple is one input triangle).
    for (0..2) |t| {
        const first = sorted[t * 3];
        try std.testing.expect(first == 0 or first == 3);
        try std.testing.expectEqual(first + 1, sorted[t * 3 + 1]);
        try std.testing.expectEqual(first + 2, sorted[t * 3 + 2]);
    }
}

test spatialClusterPoints {
    var vertices: [8][3]f32 = undefined;
    for (&vertices, 0..) |*v, i| {
        const far: f32 = if (i % 2 == 1) 100 else 0;
        v.* = .{ @as(f32, @floatFromInt(i)) * 0.1 + far, 0, 0 };
    }
    var clustered: [8]u32 = undefined;
    spatialClusterPoints([3]f32, &clustered, &vertices, 4);
    // The first cluster of 4 is entirely one spatial group.
    const first_group = vertices[clustered[0]][0] >= 50;
    for (clustered[0..4]) |i| {
        try std.testing.expectEqual(first_group, vertices[i][0] >= 50);
    }
}
