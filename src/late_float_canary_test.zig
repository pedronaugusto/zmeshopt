//! The runtime half of the late-float caller-codegen guard.
//!
//! `src/abi_check.zig` pins the count of upstream signatures that pass a
//! float after more than 6 integer-class parameters — the shape Zig 0.16.0's
//! self-hosted x86-64 backend was measured (zjolt, 2026-09-01) misallocating
//! in the CALLER on x86_64-linux. This test calls a test-only C mirror of
//! each of the 8 affected signatures (`tests/abi_canary.c`) with distinct
//! sentinel values and asserts every argument arrived bit-exact, so each CI
//! target measures its own caller codegen instead of trusting a claim made
//! on another machine.
//!
//! Pointer sentinels are fake addresses; the canaries never dereference them.

const std = @import("std");
const c = @import("c.zig");

extern fn zmeshopt_canary_slot(i: usize) f64;

extern fn zmeshopt_canary_simplify(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, target_index_count: usize, target_error: f32, options: c.simplify.SimplifyOptions, result_error: ?*f32) usize;
extern fn zmeshopt_canary_simplify_attr(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_attributes: ?[*]const f32, vertex_attributes_stride: usize, attribute_weights: ?[*]const f32, attribute_count: usize, vertex_lock: ?[*]const u8, target_index_count: usize, target_error: f32, options: c.simplify.SimplifyOptions, result_error: ?*f32) usize;
extern fn zmeshopt_canary_simplify_update(indices: [*]u32, index_count: usize, vertex_positions: [*]f32, vertex_count: usize, vertex_positions_stride: usize, vertex_attributes: ?[*]f32, vertex_attributes_stride: usize, attribute_weights: ?[*]const f32, attribute_count: usize, vertex_lock: ?[*]const u8, target_index_count: usize, target_error: f32, options: c.simplify.SimplifyOptions, result_error: ?*f32) usize;
extern fn zmeshopt_canary_simplify_sloppy(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_lock: ?[*]const u8, target_index_count: usize, target_error: f32, result_error: ?*f32) usize;
extern fn zmeshopt_canary_build_meshlets(meshlets: [*]c.clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, max_triangles: usize, cone_weight: f32) usize;
extern fn zmeshopt_canary_build_meshlets_flex(meshlets: [*]c.clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize, cone_weight: f32, split_factor: f32) usize;
extern fn zmeshopt_canary_build_meshlets_spatial(meshlets: [*]c.clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize, fill_weight: f32) usize;
extern fn zmeshopt_canary_opacity_measure(levels: [*]u8, sources: [*]u32, omm_indices: [*]c_int, indices: [*]const u32, index_count: usize, vertex_uvs: [*]const f32, vertex_count: usize, vertex_uvs_stride: usize, texture_width: u32, texture_height: u32, max_level: c_int, target_edge: f32) usize;

fn p(comptime T: type, comptime addr: usize) T {
    return @ptrFromInt(addr);
}

fn expectSlots(expected: []const f64) !void {
    for (expected, 0..) |want, i| {
        try std.testing.expectEqual(want, zmeshopt_canary_slot(i));
    }
}

test "late-float canary: meshopt_simplify's shape (7 int-class, then f32)" {
    const opts = c.simplify.SimplifyOptions{ .lock_border = true, .prune = true };
    _ = zmeshopt_canary_simplify(p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, 7, 0.625, opts, p(?*f32, 0x4000));
    try expectSlots(&.{ 0x1000, 0x2000, 3, 0x3000, 5, 12, 7, 0.625, 9, 0x4000 });
}

test "late-float canary: meshopt_simplifyWithAttributes' shape (12 int-class, then f32)" {
    _ = zmeshopt_canary_simplify_attr(p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, p(?[*]const f32, 0x5000), 16, p(?[*]const f32, 0x6000), 4, p(?[*]const u8, 0x7000), 9, 0.375, .{ .sparse = true }, null);
    try expectSlots(&.{ 0x1000, 0x2000, 3, 0x3000, 5, 12, 0x5000, 16, 0x6000, 4, 0x7000, 9, 0.375, 2, 0 });
}

test "late-float canary: meshopt_simplifyWithUpdate's shape (11 int-class, then f32)" {
    _ = zmeshopt_canary_simplify_update(p([*]u32, 0x1000), 3, p([*]f32, 0x3000), 5, 12, p(?[*]f32, 0x5000), 16, p(?[*]const f32, 0x6000), 4, p(?[*]const u8, 0x7000), 9, 0.4375, .{ .error_absolute = true }, p(?*f32, 0x8000));
    try expectSlots(&.{ 0x1000, 3, 0x3000, 5, 12, 0x5000, 16, 0x6000, 4, 0x7000, 9, 0.4375, 4, 0x8000 });
}

test "late-float canary: meshopt_simplifySloppy's shape (8 int-class, then f32)" {
    _ = zmeshopt_canary_simplify_sloppy(p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, p(?[*]const u8, 0x7000), 9, 0.8125, null);
    try expectSlots(&.{ 0x1000, 0x2000, 3, 0x3000, 5, 12, 0x7000, 9, 0.8125, 0 });
}

test "late-float canary: meshopt_buildMeshlets' shape (10 int-class, then f32)" {
    _ = zmeshopt_canary_build_meshlets(p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 124, 0.5625);
    try expectSlots(&.{ 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 124, 0.5625 });
}

test "late-float canary: meshopt_buildMeshletsFlex's shape (11 int-class, then 2 f32s)" {
    _ = zmeshopt_canary_build_meshlets_flex(p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 32, 124, 0.5625, 2.5);
    try expectSlots(&.{ 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 32, 124, 0.5625, 2.5 });
}

test "late-float canary: meshopt_buildMeshletsSpatial's shape (11 int-class, then f32)" {
    _ = zmeshopt_canary_build_meshlets_spatial(p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 32, 124, 0.6875);
    try expectSlots(&.{ 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 32, 124, 0.6875 });
}

test "late-float canary: meshopt_opacityMapMeasure's shape (11 int-class, then f32)" {
    _ = zmeshopt_canary_opacity_measure(p([*]u8, 0x1000), p([*]u32, 0x2000), p([*]c_int, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 8, 512, 256, 9, 0.9375);
    try expectSlots(&.{ 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 8, 512, 256, 9, 0.9375 });
}
