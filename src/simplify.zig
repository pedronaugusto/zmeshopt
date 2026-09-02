//! Idiomatic layer: mesh, point cloud and prune simplifiers.
//!
//! Slice-based wrappers over `src/c/simplify.zig`. Simplifiers that report a
//! result error always receive an out slot and return it in `Result` — the
//! C API's nullable pointer exists only to make the report optional, and a
//! float is not worth an optional parameter.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").simplify;
const contract = @import("contract.zig");

pub const Options = c.SimplifyOptions;
pub const VertexFlags = c.SimplifyVertexFlags;

/// What a simplifier produced: the surviving indices (a prefix of the
/// destination buffer) and the resulting error, in the units the call's
/// options selected (relative to mesh extents unless `.error_absolute`;
/// convert with `scale`).
pub const Result = struct {
    indices: []u32,
    err: f32,
};

/// Extra per-vertex attributes folded into the simplifier's error metric:
/// `weights.len` floats per vertex (at most 32), read at `stride` bytes per
/// vertex from `values`, weighted per component.
pub const Attributes = struct {
    values: []const f32,
    /// Bytes between consecutive vertices' attributes in `values`.
    stride: usize,
    weights: []const f32,
};

/// `Attributes` for the in-place update simplifier, which rewrites them.
pub const MutableAttributes = struct {
    values: []f32,
    stride: usize,
    weights: []const f32,
};

/// Vertex colors for the point simplifier: a float3 per vertex, read at
/// `stride` bytes per vertex.
pub const Colors = struct {
    values: []const f32,
    stride: usize,
};

fn lockPtr(vertex_lock: ?[]const VertexFlags, vertex_count: usize) ?[*]const u8 {
    const lock = vertex_lock orelse return null;
    assert(lock.len == vertex_count);
    return @ptrCast(lock.ptr);
}

/// Reduces triangle count while preserving appearance; `destination` needs
/// `indices.len` elements worst case (NOT `target_index_count` — the
/// simplifier may stop short on topology or `target_error`).
pub fn simplify(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V, target_index_count: usize, target_error: f32, options: Options) Result {
    contract.checkVertex(V, 3);
    assert(destination.len >= indices.len);
    var err: f32 = 0;
    const n = c.meshopt_simplify(destination.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), target_index_count, target_error, options, &err);
    return .{ .indices = destination[0..n], .err = err };
}

/// `simplify` with attribute values folded into the error metric and an
/// optional per-vertex lock/protect/priority array.
pub fn simplifyWithAttributes(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V, attributes: ?Attributes, vertex_lock: ?[]const VertexFlags, target_index_count: usize, target_error: f32, options: Options) Result {
    contract.checkVertex(V, 3);
    assert(destination.len >= indices.len);
    if (attributes) |attr| assert(attr.weights.len <= 32);
    var err: f32 = 0;
    const n = c.meshopt_simplifyWithAttributes(
        destination.ptr,
        indices.ptr,
        indices.len,
        contract.floatPtr(V, vertices),
        vertices.len,
        @sizeOf(V),
        if (attributes) |attr| attr.values.ptr else null,
        if (attributes) |attr| attr.stride else 0,
        if (attributes) |attr| attr.weights.ptr else null,
        if (attributes) |attr| attr.weights.len else 0,
        lockPtr(vertex_lock, vertices.len),
        target_index_count,
        target_error,
        options,
        &err,
    );
    return .{ .indices = destination[0..n], .err = err };
}

/// `simplifyWithAttributes` variant that destructively updates `indices`,
/// `vertices` and the attribute values in place for optimal appearance;
/// the returned indices are a prefix of `indices`.
pub fn simplifyWithUpdate(comptime V: type, indices: []u32, vertices: []V, attributes: ?MutableAttributes, vertex_lock: ?[]const VertexFlags, target_index_count: usize, target_error: f32, options: Options) Result {
    contract.checkVertex(V, 3);
    if (attributes) |attr| assert(attr.weights.len <= 32);
    var err: f32 = 0;
    const n = c.meshopt_simplifyWithUpdate(
        indices.ptr,
        indices.len,
        contract.floatPtrMut(V, vertices),
        vertices.len,
        @sizeOf(V),
        if (attributes) |attr| attr.values.ptr else null,
        if (attributes) |attr| attr.stride else 0,
        if (attributes) |attr| attr.weights.ptr else null,
        if (attributes) |attr| attr.weights.len else 0,
        lockPtr(vertex_lock, vertices.len),
        target_index_count,
        target_error,
        options,
        &err,
    );
    return .{ .indices = indices[0..n], .err = err };
}

/// Sloppy simplifier: does not preserve topology, sacrifices appearance for
/// speed. Locked vertices must be flagged consistently across all indices
/// sharing a position; `target_error` is in [0..1].
pub fn simplifySloppy(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V, vertex_lock: ?[]const VertexFlags, target_index_count: usize, target_error: f32) Result {
    contract.checkVertex(V, 3);
    assert(destination.len >= indices.len);
    var err: f32 = 0;
    const n = c.meshopt_simplifySloppy(destination.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), lockPtr(vertex_lock, vertices.len), target_index_count, target_error, &err);
    return .{ .indices = destination[0..n], .err = err };
}

/// Removes small isolated parts of the mesh; returns the surviving prefix of
/// `destination`. `target_error` is in [0..1], relative to mesh extents.
pub fn simplifyPrune(comptime V: type, destination: []u32, indices: []const u32, vertices: []const V, target_error: f32) []u32 {
    contract.checkVertex(V, 3);
    assert(destination.len >= indices.len);
    const n = c.meshopt_simplifyPrune(destination.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), target_error);
    return destination[0..n];
}

/// Point cloud simplifier; writes the indices of kept points and returns the
/// written prefix. `destination.len` is the target point count; a color
/// weight of 1.0 is a safe default when colors are given.
pub fn simplifyPoints(comptime V: type, destination: []u32, vertices: []const V, colors: ?Colors, color_weight: f32) []u32 {
    contract.checkVertex(V, 3);
    const n = c.meshopt_simplifyPoints(
        destination.ptr,
        contract.floatPtr(V, vertices),
        vertices.len,
        @sizeOf(V),
        if (colors) |col| col.values.ptr else null,
        if (colors) |col| col.stride else 0,
        color_weight,
        destination.len,
    );
    return destination[0..n];
}

/// The factor converting between absolute and relative simplifier error:
/// divide absolute error by it before passing `target_error`, multiply a
/// relative `Result.err` by it to get absolute error.
pub fn scale(comptime V: type, vertices: []const V) f32 {
    contract.checkVertex(V, 3);
    return c.meshopt_simplifyScale(contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// A grid mesh for the simplifier tests: (n+1)^2 vertices, 2n^2 triangles,
/// all coplanar so simplification can be aggressive.
fn gridMesh(comptime n: usize) struct { vertices: [(n + 1) * (n + 1)][3]f32, indices: [n * n * 6]u32 } {
    var vertices: [(n + 1) * (n + 1)][3]f32 = undefined;
    for (0..n + 1) |y| for (0..n + 1) |x| {
        vertices[y * (n + 1) + x] = .{ @floatFromInt(x), @floatFromInt(y), 0 };
    };
    var indices: [n * n * 6]u32 = undefined;
    for (0..n) |y| for (0..n) |x| {
        const tl = y * (n + 1) + x;
        const quad = [6]usize{ tl, tl + 1, tl + n + 1, tl + 1, tl + n + 2, tl + n + 1 };
        for (quad, 0..) |q, k| indices[(y * n + x) * 6 + k] = @intCast(q);
    };
    return .{ .vertices = vertices, .indices = indices };
}

test simplify {
    const mesh = gridMesh(8);
    var destination: [mesh.indices.len]u32 = undefined;
    const result = simplify([3]f32, &destination, &mesh.indices, &mesh.vertices, 6, 1e-2, .{});
    // A flat grid collapses hard; the result must honor the worst case
    // bound, stay triangles, and reference real vertices.
    try std.testing.expect(result.indices.len <= mesh.indices.len);
    try std.testing.expect(result.indices.len < mesh.indices.len / 2);
    try std.testing.expectEqual(@as(usize, 0), result.indices.len % 3);
    for (result.indices) |i| try std.testing.expect(i < mesh.vertices.len);
    try std.testing.expect(result.err <= 1e-2);
}

test simplifyWithAttributes {
    const mesh = gridMesh(4);
    // One attribute (all equal), weight 1: must not prevent full collapse.
    var attribute_values: [mesh.vertices.len]f32 = @splat(0.5);
    var destination: [mesh.indices.len]u32 = undefined;
    const result = simplifyWithAttributes([3]f32, &destination, &mesh.indices, &mesh.vertices, .{
        .values = &attribute_values,
        .stride = @sizeOf(f32),
        .weights = &.{1.0},
    }, null, 6, 1e-2, .{});
    try std.testing.expect(result.indices.len < mesh.indices.len);
    try std.testing.expectEqual(@as(usize, 0), result.indices.len % 3);
}

test simplifyWithUpdate {
    var mesh = gridMesh(4);
    const original_len = mesh.indices.len;
    const result = simplifyWithUpdate([3]f32, &mesh.indices, &mesh.vertices, null, null, 6, 1e-2, .{});
    try std.testing.expect(result.indices.len < original_len);
    try std.testing.expectEqual(@as(usize, 0), result.indices.len % 3);
}

test simplifySloppy {
    const mesh = gridMesh(8);
    var destination: [mesh.indices.len]u32 = undefined;
    const result = simplifySloppy([3]f32, &destination, &mesh.indices, &mesh.vertices, null, 12, 0.5);
    try std.testing.expect(result.indices.len <= mesh.indices.len);
    try std.testing.expectEqual(@as(usize, 0), result.indices.len % 3);
}

test simplifyPrune {
    // A big quad and a tiny sliver triangle beside it: relative to the mesh
    // extents the quad is large and survives, the sliver is pruned.
    const vertices = [_][3]f32{
        .{ 0, 0, 0 },     .{ 100, 0, 0 },      .{ 0, 100, 0 },      .{ 100, 100, 0 },
        .{ 101, 101, 0 }, .{ 101.01, 101, 0 }, .{ 101, 101.01, 0 },
    };
    const indices = [_]u32{ 0, 1, 2, 1, 3, 2, 4, 5, 6 };
    var destination: [indices.len]u32 = undefined;
    const kept = simplifyPrune([3]f32, &destination, &indices, &vertices, 1e-2);
    try std.testing.expectEqual(@as(usize, 6), kept.len);
    for (kept) |i| try std.testing.expect(i < 4);
}

test simplifyPoints {
    var vertices: [64][3]f32 = undefined;
    for (&vertices, 0..) |*v, i| {
        v.* = .{ @floatFromInt(i % 4), @floatFromInt((i / 4) % 4), @floatFromInt(i / 16) };
    }
    var destination: [8]u32 = undefined;
    const kept = simplifyPoints([3]f32, &destination, &vertices, null, 0);
    try std.testing.expectEqual(@as(usize, 8), kept.len);
    for (kept) |i| try std.testing.expect(i < vertices.len);
}

test scale {
    // The scale is the largest bounding-box axis extent (measured; a unit
    // cube reports 1, not the diagonal).
    const vertices = [_][3]f32{ .{ 0, 0, 0 }, .{ 2, 1, 1 } };
    try std.testing.expectApproxEqRel(@as(f32, 2.0), scale([3]f32, &vertices), 1e-6);
}
