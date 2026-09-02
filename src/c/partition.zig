//! meshoptimizer C declarations: cluster partitioning.
//!
//! Mirrors the partition region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Partitions clusters into groups of similar size, preferring clusters
/// that share vertices or sit close together; returns the partition count,
/// writing each cluster's partition id to `destination` (`cluster_count`
/// elements). `cluster_indices` holds all clusters' vertex indices in
/// sequence, `cluster_index_counts` their lengths (summing to
/// `total_index_count`); null `vertex_positions` groups by sharing only.
pub extern fn meshopt_partitionClusters(destination: [*]u32, cluster_indices: [*]const u32, total_index_count: usize, cluster_index_counts: [*]const u32, cluster_count: usize, vertex_positions: ?[*]const f32, vertex_count: usize, vertex_positions_stride: usize, target_partition_size: usize) usize;
