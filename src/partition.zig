//! Idiomatic layer: cluster partitioning.
//!
//! Slice-based wrappers over `src/c/partition.zig`. Two entry points for the
//! one C function, because its `vertex_positions` is optional but its
//! `vertex_count` is not: `partition.cpp:39` asserts every cluster index
//! against the count even when no positions are given.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").partition;
const contract = @import("contract.zig");

/// Partitions clusters into groups of similar size, preferring clusters that
/// share vertices or sit close together; writes each cluster's partition id
/// to `destination` and returns the partition count. `cluster_indices` holds
/// every cluster's vertex indices sequentially, `cluster_index_counts` each
/// cluster's length. Partitions can end up smaller or larger than
/// `target_partition_size` (up to target + target/3).
pub fn partitionClusters(comptime V: type, destination: []u32, cluster_indices: []const u32, cluster_index_counts: []const u32, vertices: []const V, target_partition_size: usize) usize {
    contract.checkVertex(V, 3);
    checkClusters(destination, cluster_indices, cluster_index_counts);
    return c.meshopt_partitionClusters(destination.ptr, cluster_indices.ptr, cluster_indices.len, cluster_index_counts.ptr, cluster_index_counts.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), target_partition_size);
}

/// `partitionClusters` without positions: only vertex sharing groups
/// clusters. `vertex_count` still bounds every cluster index.
pub fn partitionClustersBySharing(destination: []u32, cluster_indices: []const u32, cluster_index_counts: []const u32, vertex_count: usize, target_partition_size: usize) usize {
    checkClusters(destination, cluster_indices, cluster_index_counts);
    return c.meshopt_partitionClusters(destination.ptr, cluster_indices.ptr, cluster_indices.len, cluster_index_counts.ptr, cluster_index_counts.len, null, vertex_count, 0, target_partition_size);
}

fn checkClusters(destination: []u32, cluster_indices: []const u32, cluster_index_counts: []const u32) void {
    assert(destination.len >= cluster_index_counts.len);
    var total: usize = 0;
    for (cluster_index_counts) |n| total += n;
    assert(total == cluster_indices.len);
}

test partitionClusters {
    // Four clusters, two spatial pairs; target size 2 splits along the pairs.
    var vertices: [8][3]f32 = undefined;
    for (&vertices, 0..) |*v, i| {
        const far: f32 = if (i >= 4) 100 else 0;
        v.* = .{ @as(f32, @floatFromInt(i % 4)) + far, 0, 0 };
    }
    const cluster_indices = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7 };
    const cluster_index_counts = [_]u32{ 2, 2, 2, 2 };
    var destination: [4]u32 = undefined;
    const partitions = partitionClusters([3]f32, &destination, &cluster_indices, &cluster_index_counts, &vertices, 2);
    try std.testing.expectEqual(@as(usize, 2), partitions);
    try std.testing.expectEqual(destination[0], destination[1]);
    try std.testing.expectEqual(destination[2], destination[3]);
    try std.testing.expect(destination[0] != destination[2]);
}

test partitionClustersBySharing {
    // Clusters 0 and 1 share vertices 2 and 3; cluster 2 is disjoint.
    const cluster_indices = [_]u32{ 0, 1, 2, 3, 2, 3, 4, 5, 6, 7, 8, 9 };
    const cluster_index_counts = [_]u32{ 4, 4, 4 };
    var destination: [3]u32 = undefined;
    const partitions = partitionClustersBySharing(&destination, &cluster_indices, &cluster_index_counts, 10, 2);
    try std.testing.expect(partitions >= 1 and partitions <= 3);
    try std.testing.expectEqual(destination[0], destination[1]);
}
