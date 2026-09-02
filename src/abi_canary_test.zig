//! Runtime canaries for the two measured Zig 0.16.0 self-hosted-backend
//! caller miscompiles (hosted CI, 2026-09-02): a float argument after more
//! than 6 integer-class parameters, and an all-float 16-byte struct return.
//!
//! `zmeshopt_canary_*` mirror the RAW upstream shapes and feed the toolchain
//! watch: a comptime verdict table records what each measured (backend, OS)
//! pair does. Exact pairs assert exactness; broken pairs assert the
//! miscompile is still present, so a fixed backend fails loudly — the signal
//! to retire `src/abi_shim.c`; unmeasured pairs skip.
//!
//! `zmeshopt_canary_shim_*` mirror the shapes the bindings ship
//! (`src/shim.zig`): floats first, struct return via out-param. Hard asserts
//! on every backend. Pointer sentinels are fake addresses, never
//! dereferenced.

const std = @import("std");
const builtin = @import("builtin");
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

extern fn zmeshopt_canary_coverage_return() c.analyze.CoverageStatistics;

extern fn zmeshopt_canary_shim_simplify(target_error: f32, destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, target_index_count: usize, options: c.simplify.SimplifyOptions, result_error: ?*f32) usize;
extern fn zmeshopt_canary_shim_simplify_attr(target_error: f32, destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_attributes: ?[*]const f32, vertex_attributes_stride: usize, attribute_weights: ?[*]const f32, attribute_count: usize, vertex_lock: ?[*]const u8, target_index_count: usize, options: c.simplify.SimplifyOptions, result_error: ?*f32) usize;
extern fn zmeshopt_canary_shim_simplify_update(target_error: f32, indices: [*]u32, index_count: usize, vertex_positions: [*]f32, vertex_count: usize, vertex_positions_stride: usize, vertex_attributes: ?[*]f32, vertex_attributes_stride: usize, attribute_weights: ?[*]const f32, attribute_count: usize, vertex_lock: ?[*]const u8, target_index_count: usize, options: c.simplify.SimplifyOptions, result_error: ?*f32) usize;
extern fn zmeshopt_canary_shim_simplify_sloppy(target_error: f32, destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_lock: ?[*]const u8, target_index_count: usize, result_error: ?*f32) usize;
extern fn zmeshopt_canary_shim_build_meshlets(cone_weight: f32, meshlets: [*]c.clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, max_triangles: usize) usize;
extern fn zmeshopt_canary_shim_build_meshlets_flex(cone_weight: f32, split_factor: f32, meshlets: [*]c.clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize) usize;
extern fn zmeshopt_canary_shim_build_meshlets_spatial(fill_weight: f32, meshlets: [*]c.clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize) usize;
extern fn zmeshopt_canary_shim_opacity_measure(target_edge: f32, levels: [*]u8, sources: [*]u32, omm_indices: [*]c_int, indices: [*]const u32, index_count: usize, vertex_uvs: [*]const f32, vertex_count: usize, vertex_uvs_stride: usize, texture_width: u32, texture_height: u32, max_level: c_int) usize;
extern fn zmeshopt_canary_shim_coverage(out: *c.analyze.CoverageStatistics, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) void;

const Verdict = enum { exact, broken, unmeasured };

// The verdict table: what each (backend, OS) pair was MEASURED to do with the
// raw shapes. Every non-skip row comes from a hosted-CI or local run of the
// mirrors above; extend it only with a new measurement, never by analogy.
const late_float_verdict: Verdict = switch (builtin.zig_backend) {
    .stage2_llvm => .exact,
    .stage2_x86_64 => switch (builtin.os.tag) {
        .windows => .exact,
        .linux => .broken,
        else => .unmeasured,
    },
    .stage2_aarch64 => switch (builtin.os.tag) {
        .macos => .exact,
        else => .unmeasured,
    },
    else => .unmeasured,
};

const struct_return_verdict: Verdict = switch (builtin.zig_backend) {
    .stage2_llvm => .exact,
    .stage2_x86_64 => switch (builtin.os.tag) {
        .windows => .exact,
        .linux => .broken,
        else => .unmeasured,
    },
    .stage2_aarch64 => switch (builtin.os.tag) {
        .macos => .broken,
        else => .unmeasured,
    },
    else => .unmeasured,
};

fn p(comptime T: type, comptime addr: usize) T {
    return @ptrFromInt(addr);
}

fn expectSlots(expected: []const f64) !void {
    for (expected, 0..) |want, i| {
        try std.testing.expectEqual(want, zmeshopt_canary_slot(i));
    }
}

fn slotsMatch(expected: []const f64) bool {
    for (expected, 0..) |want, i| {
        if (zmeshopt_canary_slot(i) != want) return false;
    }
    return true;
}

// The raw shapes as (call, expected-slots) pairs, so the toolchain watch can
// run them under either verdict without repeating the sentinel lists.
const RawCase = struct {
    run: *const fn () void,
    expected: []const f64,
};

fn rawSimplify() void {
    _ = zmeshopt_canary_simplify(p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, 7, 0.625, .{ .lock_border = true, .prune = true }, p(?*f32, 0x4000));
}

fn rawSimplifyAttr() void {
    _ = zmeshopt_canary_simplify_attr(p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, p(?[*]const f32, 0x5000), 16, p(?[*]const f32, 0x6000), 4, p(?[*]const u8, 0x7000), 9, 0.375, .{ .sparse = true }, null);
}

fn rawSimplifyUpdate() void {
    _ = zmeshopt_canary_simplify_update(p([*]u32, 0x1000), 3, p([*]f32, 0x3000), 5, 12, p(?[*]f32, 0x5000), 16, p(?[*]const f32, 0x6000), 4, p(?[*]const u8, 0x7000), 9, 0.4375, .{ .error_absolute = true }, p(?*f32, 0x8000));
}

fn rawSimplifySloppy() void {
    _ = zmeshopt_canary_simplify_sloppy(p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, p(?[*]const u8, 0x7000), 9, 0.8125, null);
}

fn rawBuildMeshlets() void {
    _ = zmeshopt_canary_build_meshlets(p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 124, 0.5625);
}

fn rawBuildMeshletsFlex() void {
    _ = zmeshopt_canary_build_meshlets_flex(p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 32, 124, 0.5625, 2.5);
}

fn rawBuildMeshletsSpatial() void {
    _ = zmeshopt_canary_build_meshlets_spatial(p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 32, 124, 0.6875);
}

fn rawOpacityMeasure() void {
    _ = zmeshopt_canary_opacity_measure(p([*]u8, 0x1000), p([*]u32, 0x2000), p([*]c_int, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 8, 512, 256, 9, 0.9375);
}

const raw_cases = [_]RawCase{
    .{ .run = rawSimplify, .expected = &.{ 0x1000, 0x2000, 3, 0x3000, 5, 12, 7, 0.625, 9, 0x4000 } },
    .{ .run = rawSimplifyAttr, .expected = &.{ 0x1000, 0x2000, 3, 0x3000, 5, 12, 0x5000, 16, 0x6000, 4, 0x7000, 9, 0.375, 2, 0 } },
    .{ .run = rawSimplifyUpdate, .expected = &.{ 0x1000, 3, 0x3000, 5, 12, 0x5000, 16, 0x6000, 4, 0x7000, 9, 0.4375, 4, 0x8000 } },
    .{ .run = rawSimplifySloppy, .expected = &.{ 0x1000, 0x2000, 3, 0x3000, 5, 12, 0x7000, 9, 0.8125, 0 } },
    .{ .run = rawBuildMeshlets, .expected = &.{ 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 124, 0.5625 } },
    .{ .run = rawBuildMeshletsFlex, .expected = &.{ 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 32, 124, 0.5625, 2.5 } },
    .{ .run = rawBuildMeshletsSpatial, .expected = &.{ 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 32, 124, 0.6875 } },
    .{ .run = rawOpacityMeasure, .expected = &.{ 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 8, 512, 256, 9, 0.9375 } },
};

test "toolchain watch: raw late-float caller codegen" {
    switch (late_float_verdict) {
        .unmeasured => return error.SkipZigTest,
        .exact => for (raw_cases) |case| {
            case.run();
            try expectSlots(case.expected);
        },
        .broken => {
            var mismatches: usize = 0;
            for (raw_cases) |case| {
                case.run();
                if (!slotsMatch(case.expected)) mismatches += 1;
            }
            if (mismatches == 0) {
                std.debug.print("raw late-float shapes now arrive exact on this backend: update the verdict table and consider retiring src/abi_shim.c\n", .{});
                return error.TestUnexpectedResult;
            }
        },
    }
}

test "toolchain watch: raw all-float struct return" {
    if (struct_return_verdict == .unmeasured) return error.SkipZigTest;
    const stats = zmeshopt_canary_coverage_return();
    const exact = stats.coverage[0] == 1.25 and stats.coverage[1] == 2.5 and stats.coverage[2] == 3.75 and stats.extent == 5.0;
    switch (struct_return_verdict) {
        .unmeasured => unreachable,
        .exact => try std.testing.expect(exact),
        .broken => if (exact) {
            std.debug.print("the raw all-float struct return now arrives exact on this backend: update the verdict table and consider retiring src/abi_shim.c\n", .{});
            return error.TestUnexpectedResult;
        },
    }
}

test "shim canary: zmeshopt_shim_simplify's shape (f32 first)" {
    _ = zmeshopt_canary_shim_simplify(0.625, p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, 7, .{ .lock_border = true, .prune = true }, p(?*f32, 0x4000));
    try expectSlots(&.{ 0.625, 0x1000, 0x2000, 3, 0x3000, 5, 12, 7, 9, 0x4000 });
}

test "shim canary: zmeshopt_shim_simplifyWithAttributes' shape (f32 first)" {
    _ = zmeshopt_canary_shim_simplify_attr(0.375, p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, p(?[*]const f32, 0x5000), 16, p(?[*]const f32, 0x6000), 4, p(?[*]const u8, 0x7000), 9, .{ .sparse = true }, null);
    try expectSlots(&.{ 0.375, 0x1000, 0x2000, 3, 0x3000, 5, 12, 0x5000, 16, 0x6000, 4, 0x7000, 9, 2, 0 });
}

test "shim canary: zmeshopt_shim_simplifyWithUpdate's shape (f32 first)" {
    _ = zmeshopt_canary_shim_simplify_update(0.4375, p([*]u32, 0x1000), 3, p([*]f32, 0x3000), 5, 12, p(?[*]f32, 0x5000), 16, p(?[*]const f32, 0x6000), 4, p(?[*]const u8, 0x7000), 9, .{ .error_absolute = true }, p(?*f32, 0x8000));
    try expectSlots(&.{ 0.4375, 0x1000, 3, 0x3000, 5, 12, 0x5000, 16, 0x6000, 4, 0x7000, 9, 4, 0x8000 });
}

test "shim canary: zmeshopt_shim_simplifySloppy's shape (f32 first)" {
    _ = zmeshopt_canary_shim_simplify_sloppy(0.8125, p([*]u32, 0x1000), p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12, p(?[*]const u8, 0x7000), 9, null);
    try expectSlots(&.{ 0.8125, 0x1000, 0x2000, 3, 0x3000, 5, 12, 0x7000, 9, 0 });
}

test "shim canary: zmeshopt_shim_buildMeshlets' shape (f32 first)" {
    _ = zmeshopt_canary_shim_build_meshlets(0.5625, p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 124);
    try expectSlots(&.{ 0.5625, 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 124 });
}

test "shim canary: zmeshopt_shim_buildMeshletsFlex's shape (2 f32s first)" {
    _ = zmeshopt_canary_shim_build_meshlets_flex(0.5625, 2.5, p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 32, 124);
    try expectSlots(&.{ 0.5625, 2.5, 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 32, 124 });
}

test "shim canary: zmeshopt_shim_buildMeshletsSpatial's shape (f32 first)" {
    _ = zmeshopt_canary_shim_build_meshlets_spatial(0.6875, p([*]c.clusterize.Meshlet, 0x1000), p([*]u32, 0x2000), p([*]u8, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 12, 64, 32, 124);
    try expectSlots(&.{ 0.6875, 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 12, 64, 32, 124 });
}

test "shim canary: zmeshopt_shim_opacityMapMeasure's shape (f32 first)" {
    _ = zmeshopt_canary_shim_opacity_measure(0.9375, p([*]u8, 0x1000), p([*]u32, 0x2000), p([*]c_int, 0x3000), p([*]const u32, 0x4000), 33, p([*]const f32, 0x5000), 7, 8, 512, 256, 9);
    try expectSlots(&.{ 0.9375, 0x1000, 0x2000, 0x3000, 0x4000, 33, 0x5000, 7, 8, 512, 256, 9 });
}

test "shim canary: zmeshopt_shim_analyzeCoverage's shape (out-param)" {
    var stats: c.analyze.CoverageStatistics = undefined;
    zmeshopt_canary_shim_coverage(&stats, p([*]const u32, 0x2000), 3, p([*]const f32, 0x3000), 5, 12);
    try expectSlots(&.{ @floatFromInt(@intFromPtr(&stats)), 0x2000, 3, 0x3000, 5, 12 });
    try std.testing.expectEqual(@as(f32, 1.25), stats.coverage[0]);
    try std.testing.expectEqual(@as(f32, 2.5), stats.coverage[1]);
    try std.testing.expectEqual(@as(f32, 3.75), stats.coverage[2]);
    try std.testing.expectEqual(@as(f32, 5.0), stats.extent);
}
