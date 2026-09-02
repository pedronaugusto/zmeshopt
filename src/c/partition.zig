//! meshoptimizer C declarations: cluster partitioning.
//!
//! Mirrors the partition region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Partitions clusters into groups of similar size, preferring clusters that
/// share vertices or sit close together; returns the partition count and
/// writes each cluster's partition id to `destination` (`cluster_count`
/// elements). `cluster_indices` holds every cluster's vertex indices
/// sequentially, with `cluster_index_counts` giving each cluster's length
/// (their sum must equal `total_index_count`). `vertex_positions` may be
/// null — then only vertex sharing groups clusters. Partitions may end up
/// smaller or larger than `target_partition_size` (up to target + target/3).
pub extern fn meshopt_partitionClusters(destination: [*]u32, cluster_indices: [*]const u32, total_index_count: usize, cluster_index_counts: [*]const u32, cluster_count: usize, vertex_positions: ?[*]const f32, vertex_count: usize, vertex_positions_stride: usize, target_partition_size: usize) usize;
