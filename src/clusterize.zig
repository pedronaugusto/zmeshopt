//! Idiomatic layer: meshlet building, meshlet optimization and cluster
//! bounds.
//!
//! Slice-based wrappers over `src/c/clusterize.zig`. The builders return the
//! meshlet prefix they filled; per-meshlet data slices come out of
//! `vertexSlice`/`triangleSlice` rather than hand-computed offsets.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").clusterize;
const contract = @import("contract.zig");
// The three position-aware builders have a late float; they cross through
// src/abi_shim.c on every backend (src/shim.zig has the measurement).
const shim = @import("shim.zig");

pub const Meshlet = c.Meshlet;
pub const Bounds = c.Bounds;

/// One built meshlet's window into the shared vertex indirection buffer.
pub fn vertexSlice(meshlet: Meshlet, meshlet_vertices: []u32) []u32 {
    return meshlet_vertices[meshlet.vertex_offset..][0..meshlet.vertex_count];
}

/// One built meshlet's window into the shared micro index buffer.
pub fn triangleSlice(meshlet: Meshlet, meshlet_triangles: []u8) []u8 {
    return meshlet_triangles[meshlet.triangle_offset..][0 .. meshlet.triangle_count * 3];
}

/// Upstream's per-meshlet implementation limits, both halves of each
/// (clusterizer.cpp:1043-1044): under 3 vertices no triangle fits, and a
/// meshlet of 0 triangles is not a meshlet. A predicate rather than a run of
/// asserts because the limits are the contract every builder is gated on.
fn withinMeshletLimits(max_vertices: usize, min_triangles: usize, max_triangles: usize) bool {
    return max_vertices >= 3 and max_vertices <= 256 and
        min_triangles >= 1 and min_triangles <= max_triangles and max_triangles <= 512;
}

/// The precondition gate the four builders share. `min_triangles` equals
/// `max_triangles` for the fixed-size pair, which is how upstream reduces
/// them to the flexible ones (clusterizer.cpp:1228), and it is the count
/// `buildMeshletsBound` has to be asked with (meshoptimizer.h:736, :750).
fn checkBuildBuffers(meshlets: []const Meshlet, meshlet_vertices: []u32, meshlet_triangles: []u8, index_count: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize) void {
    assert(index_count % 3 == 0);
    assert(withinMeshletLimits(max_vertices, min_triangles, max_triangles));
    // The one destination whose size is a computed bound rather than a length
    // upstream can derive from the input (meshoptimizer.h:720).
    assert(meshlets.len >= buildMeshletsBound(index_count, max_vertices, min_triangles));
    assert(meshlet_vertices.len >= index_count);
    assert(meshlet_triangles.len >= index_count);
}

/// Splits a mesh into meshlets; returns the filled prefix of `meshlets`
/// (size it with `buildMeshletsBound`; the two data buffers need
/// `indices.len` elements worst case). `cone_weight` is 0 when cone culling
/// is unused, else (0..1] trades cluster size for culling efficiency.
pub fn buildMeshlets(comptime V: type, meshlets: []Meshlet, meshlet_vertices: []u32, meshlet_triangles: []u8, indices: []const u32, vertices: []const V, max_vertices: usize, max_triangles: usize, cone_weight: f32) []Meshlet {
    contract.checkVertex(V, 3);
    checkBuildBuffers(meshlets, meshlet_vertices, meshlet_triangles, indices.len, max_vertices, max_triangles, max_triangles);
    const n = shim.zmeshopt_shim_buildMeshlets(cone_weight, meshlets.ptr, meshlet_vertices.ptr, meshlet_triangles.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), max_vertices, max_triangles);
    return meshlets[0..n];
}

/// `buildMeshlets` without positions, scanning the index buffer in order;
/// optimize for vertex cache first for best results.
pub fn buildMeshletsScan(meshlets: []Meshlet, meshlet_vertices: []u32, meshlet_triangles: []u8, indices: []const u32, vertex_count: usize, max_vertices: usize, max_triangles: usize) []Meshlet {
    checkBuildBuffers(meshlets, meshlet_vertices, meshlet_triangles, indices.len, max_vertices, max_triangles, max_triangles);
    const n = c.meshopt_buildMeshletsScan(meshlets.ptr, meshlet_vertices.ptr, meshlet_triangles.ptr, indices.ptr, indices.len, vertex_count, max_vertices, max_triangles);
    return meshlets[0..n];
}

/// Worst-case meshlet count for the builders. For the flex/spatial builders
/// pass their `min_triangles` as `max_triangles`.
pub fn buildMeshletsBound(index_count: usize, max_vertices: usize, max_triangles: usize) usize {
    // Checked here rather than left to clusterizer.cpp:1021-1023, because a
    // caller sizes an array from the result: `max_vertices` under 3 makes
    // upstream's `max_vertices - 2` divisor 0 or a near-SIZE_MAX wrap.
    assert(index_count % 3 == 0);
    assert(withinMeshletLimits(max_vertices, max_triangles, max_triangles));
    return c.meshopt_buildMeshletsBound(index_count, max_vertices, max_triangles);
}

/// `buildMeshlets` with min/max triangle counts per meshlet
/// (`min_triangles <= max_triangles <= 512`); clusters over the expected size
/// by more than `split_factor` are split when it is > 0.
pub fn buildMeshletsFlex(comptime V: type, meshlets: []Meshlet, meshlet_vertices: []u32, meshlet_triangles: []u8, indices: []const u32, vertices: []const V, max_vertices: usize, min_triangles: usize, max_triangles: usize, cone_weight: f32, split_factor: f32) []Meshlet {
    contract.checkVertex(V, 3);
    checkBuildBuffers(meshlets, meshlet_vertices, meshlet_triangles, indices.len, max_vertices, min_triangles, max_triangles);
    const n = shim.zmeshopt_shim_buildMeshletsFlex(cone_weight, split_factor, meshlets.ptr, meshlet_vertices.ptr, meshlet_triangles.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), max_vertices, min_triangles, max_triangles);
    return meshlets[0..n];
}

/// Meshlet builder optimizing cluster subdivision for raytracing;
/// `fill_weight` trades cluster fill for SAH quality (0.5 is a safe default).
pub fn buildMeshletsSpatial(comptime V: type, meshlets: []Meshlet, meshlet_vertices: []u32, meshlet_triangles: []u8, indices: []const u32, vertices: []const V, max_vertices: usize, min_triangles: usize, max_triangles: usize, fill_weight: f32) []Meshlet {
    contract.checkVertex(V, 3);
    checkBuildBuffers(meshlets, meshlet_vertices, meshlet_triangles, indices.len, max_vertices, min_triangles, max_triangles);
    const n = shim.zmeshopt_shim_buildMeshletsSpatial(fill_weight, meshlets.ptr, meshlet_vertices.ptr, meshlet_triangles.ptr, indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V), max_vertices, min_triangles, max_triangles);
    return meshlets[0..n];
}

/// Reorders one meshlet's vertices and triangles for locality; pass the
/// slices `vertexSlice`/`triangleSlice` produce.
pub fn optimizeMeshlet(meshlet_vertices: []u32, meshlet_triangles: []u8) void {
    assert(meshlet_triangles.len % 3 == 0);
    c.meshopt_optimizeMeshlet(meshlet_vertices.ptr, meshlet_triangles.ptr, meshlet_triangles.len / 3, meshlet_vertices.len);
}

/// `optimizeMeshlet` with a compression-oriented `level` ([0, 9]; ~3 is the
/// codec sweet spot). Levels >= 1 may rotate triangle corners, which changes
/// the provoking vertex and affects OMM data.
pub fn optimizeMeshletLevel(meshlet_vertices: []u32, meshlet_triangles: []u8, level: u4) void {
    assert(meshlet_triangles.len % 3 == 0);
    assert(level <= 9);
    c.meshopt_optimizeMeshletLevel(meshlet_vertices.ptr, meshlet_vertices.len, meshlet_triangles.ptr, meshlet_triangles.len / 3, level);
}

/// Bounding volumes for a cluster given absolute indices (at most 256 unique
/// vertices, `indices.len / 3 <= 512`); `vertices` is the WHOLE mesh.
pub fn computeClusterBounds(comptime V: type, indices: []const u32, vertices: []const V) Bounds {
    contract.checkVertex(V, 3);
    assert(indices.len % 3 == 0);
    assert(indices.len / 3 <= 512);
    return c.meshopt_computeClusterBounds(indices.ptr, indices.len, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// Bounding volumes for a built meshlet: pass the slices
/// `vertexSlice`/`triangleSlice` produce and the whole mesh's vertices.
pub fn computeMeshletBounds(comptime V: type, meshlet_vertices: []const u32, meshlet_triangles: []const u8, vertices: []const V) Bounds {
    contract.checkVertex(V, 3);
    assert(meshlet_triangles.len % 3 == 0);
    return c.meshopt_computeMeshletBounds(meshlet_vertices.ptr, meshlet_triangles.ptr, meshlet_triangles.len / 3, contract.floatPtr(V, vertices), vertices.len, @sizeOf(V));
}

/// Bounding sphere around points (or spheres, when `radii` is given — one
/// tightly packed float per point); only `center` and `radius` of the result
/// are set.
pub fn computeSphereBounds(comptime V: type, positions: []const V, radii: ?[]const f32) Bounds {
    contract.checkVertex(V, 3);
    if (radii) |r| assert(r.len == positions.len);
    return c.meshopt_computeSphereBounds(contract.floatPtr(V, positions), positions.len, @sizeOf(V), if (radii) |r| r.ptr else null, @sizeOf(f32));
}

/// Extracts meshlet-local vertex and triangle indices from absolute cluster
/// indices, such that `vertices[triangles[i]] == indices[i]`; returns the
/// unique vertex count (up to 256; `indices.len / 3 <= 512`).
pub fn extractMeshletIndices(vertices: []u32, triangles: []u8, indices: []const u32) usize {
    assert(indices.len % 3 == 0);
    assert(indices.len / 3 <= 512);
    assert(vertices.len >= @min(indices.len, 256));
    assert(triangles.len >= indices.len);
    return c.meshopt_extractMeshletIndices(vertices.ptr, triangles.ptr, indices.ptr, indices.len);
}

/// A tetrahedron fan mesh big enough to split into several meshlets.
fn testMesh() struct { vertices: [66][3]f32, indices: [192]u32 } {
    var vertices: [66][3]f32 = undefined;
    vertices[0] = .{ 0, 0, 1 };
    vertices[1] = .{ 0, 0, -1 };
    for (2..66) |i| {
        const angle = @as(f32, @floatFromInt(i - 2)) * std.math.tau / 64.0;
        vertices[i] = .{ @cos(angle), @sin(angle), 0 };
    }
    var indices: [192]u32 = undefined;
    for (0..32) |i| {
        const a: u32 = @intCast(2 + i * 2);
        const b: u32 = @intCast(2 + (i * 2 + 2) % 64);
        indices[i * 6 ..][0..6].* = .{ 0, a, b, 1, b, a };
    }
    return .{ .vertices = vertices, .indices = indices };
}

test buildMeshlets {
    const mesh = testMesh();
    const max_vertices = 16;
    const max_triangles = 8;
    var meshlets: [64]Meshlet = undefined;
    var meshlet_vertices: [mesh.indices.len]u32 = undefined;
    var meshlet_triangles: [mesh.indices.len]u8 = undefined;
    const built = buildMeshlets([3]f32, &meshlets, &meshlet_vertices, &meshlet_triangles, &mesh.indices, &mesh.vertices, max_vertices, max_triangles, 0);

    try std.testing.expect(built.len >= mesh.indices.len / 3 / max_triangles);
    try std.testing.expect(built.len <= buildMeshletsBound(mesh.indices.len, max_vertices, max_triangles));
    var total_triangles: usize = 0;
    for (built) |m| {
        try std.testing.expect(m.vertex_count <= max_vertices);
        try std.testing.expect(m.triangle_count <= max_triangles);
        total_triangles += m.triangle_count;
        const mv = vertexSlice(m, &meshlet_vertices);
        for (triangleSlice(m, &meshlet_triangles)) |local| {
            try std.testing.expect(local < m.vertex_count);
            try std.testing.expect(mv[local] < mesh.vertices.len);
        }
    }
    try std.testing.expectEqual(mesh.indices.len / 3, total_triangles);

    // Optimize and bound the first meshlet; the sphere must be sane.
    const first = built[0];
    optimizeMeshlet(vertexSlice(first, &meshlet_vertices), triangleSlice(first, &meshlet_triangles));
    optimizeMeshletLevel(vertexSlice(first, &meshlet_vertices), triangleSlice(first, &meshlet_triangles), 3);
    const bounds = computeMeshletBounds([3]f32, vertexSlice(first, &meshlet_vertices), triangleSlice(first, &meshlet_triangles), &mesh.vertices);
    try std.testing.expect(bounds.radius > 0 and bounds.radius <= 2.5);
    try std.testing.expect(bounds.cone_cutoff <= 1.0);
}

test withinMeshletLimits {
    // The legal floor is 3 vertices and 1 triangle. 2 vertices makes
    // upstream's `max_vertices - 2` divisor 0 and fewer wraps it
    // (clusterizer.cpp:1029), and 0 triangles per meshlet divides by 0 too.
    try std.testing.expect(withinMeshletLimits(3, 1, 1));
    try std.testing.expect(withinMeshletLimits(256, 1, 512));
    for ([_]usize{ 0, 1, 2, 257 }) |bad| {
        try std.testing.expect(!withinMeshletLimits(bad, 1, 8));
    }
    try std.testing.expect(!withinMeshletLimits(64, 0, 8));
    try std.testing.expect(!withinMeshletLimits(64, 9, 8));
    try std.testing.expect(!withinMeshletLimits(64, 1, 513));
}

test buildMeshletsBound {
    // At the vertex floor the conservative divisor is 1, so the vertex limit
    // is one meshlet per index and dominates; at the ceiling the triangle
    // limit does.
    try std.testing.expectEqual(@as(usize, 9), buildMeshletsBound(9, 3, 1));
    try std.testing.expectEqual(@as(usize, 3), buildMeshletsBound(9, 256, 1));
    try std.testing.expectEqual(@as(usize, 1), buildMeshletsBound(9, 256, 512));
}

test buildMeshletsScan {
    const mesh = testMesh();
    var meshlets: [64]Meshlet = undefined;
    var meshlet_vertices: [mesh.indices.len]u32 = undefined;
    var meshlet_triangles: [mesh.indices.len]u8 = undefined;
    const built = buildMeshletsScan(&meshlets, &meshlet_vertices, &meshlet_triangles, &mesh.indices, mesh.vertices.len, 16, 8);
    try std.testing.expect(built.len > 0);
}

test buildMeshletsFlex {
    const mesh = testMesh();
    var meshlets: [64]Meshlet = undefined;
    var meshlet_vertices: [mesh.indices.len]u32 = undefined;
    var meshlet_triangles: [mesh.indices.len]u8 = undefined;
    const built = buildMeshletsFlex([3]f32, &meshlets, &meshlet_vertices, &meshlet_triangles, &mesh.indices, &mesh.vertices, 32, 4, 8, 0, 2.0);
    try std.testing.expect(built.len > 0);
    for (built) |m| try std.testing.expect(m.triangle_count <= 8);
}

test checkBuildBuffers {
    // The gate takes `meshlets` because that array's size is a bound the
    // caller computes rather than a length upstream derives. Sized exactly,
    // as the doc comments prescribe: the flexible builders have to be
    // bounded with `min_triangles`, and this array fits nothing looser.
    const mesh = testMesh();
    var storage: [64]Meshlet = undefined;
    var meshlet_vertices: [mesh.indices.len]u32 = undefined;
    var meshlet_triangles: [mesh.indices.len]u8 = undefined;
    const bound = buildMeshletsBound(mesh.indices.len, 32, 4);
    try std.testing.expect(bound > buildMeshletsBound(mesh.indices.len, 32, 8));
    checkBuildBuffers(storage[0..bound], &meshlet_vertices, &meshlet_triangles, mesh.indices.len, 32, 4, 8);
    const built = buildMeshletsFlex([3]f32, storage[0..bound], &meshlet_vertices, &meshlet_triangles, &mesh.indices, &mesh.vertices, 32, 4, 8, 0, 2.0);
    try std.testing.expect(built.len > 0 and built.len <= bound);
}

test buildMeshletsSpatial {
    const mesh = testMesh();
    var meshlets: [64]Meshlet = undefined;
    var meshlet_vertices: [mesh.indices.len]u32 = undefined;
    var meshlet_triangles: [mesh.indices.len]u8 = undefined;
    const built = buildMeshletsSpatial([3]f32, &meshlets, &meshlet_vertices, &meshlet_triangles, &mesh.indices, &mesh.vertices, 32, 4, 8, 0.5);
    try std.testing.expect(built.len > 0);
}

test computeClusterBounds {
    const vertices = [_][3]f32{ .{ -1, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } };
    const indices = [_]u32{ 0, 1, 2 };
    const bounds = computeClusterBounds([3]f32, &indices, &vertices);
    // One triangle: its normal cone is the face normal with zero spread.
    try std.testing.expect(bounds.radius > 0.9 and bounds.radius < 1.3);
    try std.testing.expectApproxEqAbs(@as(f32, 1), @abs(bounds.cone_axis[2]), 1e-3);
}

test computeSphereBounds {
    const points = [_][3]f32{ .{ -2, 0, 0 }, .{ 2, 0, 0 } };
    const bounds = computeSphereBounds([3]f32, &points, null);
    try std.testing.expectApproxEqAbs(@as(f32, 2), bounds.radius, 1e-3);
    const with_radii = computeSphereBounds([3]f32, &points, &.{ 1, 1 });
    try std.testing.expectApproxEqAbs(@as(f32, 3), with_radii.radius, 1e-3);
}

test extractMeshletIndices {
    const indices = [_]u32{ 10, 20, 30, 30, 20, 40 };
    var vertices: [6]u32 = undefined;
    var triangles: [6]u8 = undefined;
    const unique = extractMeshletIndices(&vertices, &triangles, &indices);
    try std.testing.expectEqual(@as(usize, 4), unique);
    for (indices, 0..) |want, i| {
        try std.testing.expectEqual(want, vertices[triangles[i]]);
    }
}
