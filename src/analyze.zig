//! Idiomatic layer: cache, fetch, overdraw and coverage analyzers.
//!
//! Slice-based wrappers over `src/c/analyze.zig`. All four are diagnostics
//! over simplified hardware models — treat the numbers as relative quality
//! signals, not GPU predictions.

const std = @import("std");
const c = @import("c.zig").analyze;
const contract = @import("contract.zig");

pub const VertexCacheStatistics = c.VertexCacheStatistics;
pub const VertexFetchStatistics = c.VertexFetchStatistics;
pub const OverdrawStatistics = c.OverdrawStatistics;
pub const CoverageStatistics = c.CoverageStatistics;

/// Vertex transform cache statistics under a simplified FIFO model.
/// `warp_size` and `primgroup_size` may be 0 to skip those models.
pub fn analyzeVertexCache(indices: []const u32, vertex_count: usize, cache_size: u32, warp_size: u32, primgroup_size: u32) VertexCacheStatistics {
    return c.meshopt_analyzeVertexCache(indices.ptr, indices.len, vertex_count, cache_size, warp_size, primgroup_size);
}

/// Vertex fetch statistics under a simplified direct-mapped cache model,
/// for a buffer of `vertex_count` vertices of type `V`.
pub fn analyzeVertexFetch(comptime V: type, indices: []const u32, vertex_count: usize) VertexFetchStatistics {
    return c.meshopt_analyzeVertexFetch(indices.ptr, indices.len, vertex_count, @sizeOf(V));
}

/// Overdraw statistics from a software rasterizer. `V`'s first 12 bytes are
/// the position float3.
pub fn analyzeOverdraw(comptime V: type, indices: []const u32, vertices: []const V) OverdrawStatistics {
    contract.checkVertex(V, 3);
    return c.meshopt_analyzeOverdraw(indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// Coverage statistics (per-axis covered viewport ratio) from a software
/// rasterizer.
pub fn analyzeCoverage(comptime V: type, indices: []const u32, vertices: []const V) CoverageStatistics {
    contract.checkVertex(V, 3);
    return c.meshopt_analyzeCoverage(indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

test analyzeVertexCache {
    const indices = [_]u32{ 0, 1, 2, 2, 1, 3 };
    const stats = analyzeVertexCache(&indices, 4, 16, 0, 0);
    // 4 unique vertices in cache 16: each transforms exactly once.
    try std.testing.expectEqual(@as(u32, 4), stats.vertices_transformed);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), stats.acmr, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), stats.atvr, 1e-6);
}

test analyzeVertexFetch {
    const indices = [_]u32{ 0, 1, 2 };
    const stats = analyzeVertexFetch([3]f32, &indices, 3);
    try std.testing.expect(stats.bytes_fetched >= 3 * @sizeOf([3]f32));
    try std.testing.expect(stats.overfetch >= 1.0);
}

test analyzeOverdraw {
    // Two identical overlapping triangles: every covered pixel shades twice.
    const vertices = [_][3]f32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } };
    const indices = [_]u32{ 0, 1, 2, 0, 1, 2 };
    const stats = analyzeOverdraw([3]f32, &indices, &vertices);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), stats.overdraw, 1e-6);
}

test analyzeCoverage {
    // A quad spanning the whole XY bounding square covers that axis fully.
    const vertices = [_][3]f32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 1, 0 } };
    const indices = [_]u32{ 0, 1, 2, 2, 1, 3 };
    const stats = analyzeCoverage([3]f32, &indices, &vertices);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), stats.coverage[2], 0.05);
}
