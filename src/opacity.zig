//! Idiomatic layer: opacity micromap generation.
//!
//! Slice-based wrappers over `src/c/opacity.zig`. ALL FOUR entry points are
//! EXPERIMENTAL upstream.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").opacity;
const contract = @import("contract.zig");
// opacityMapMeasure has a late float; it crosses through src/abi_shim.c on
// every backend (src/shim.zig has the measurement).
const shim = @import("shim.zig");

/// The OMM state count: 2-state (opaque/transparent) or 4-state (adding
/// unknown-opaque/unknown-transparent).
pub const OpacityStates = enum(c_int) {
    two = 2,
    four = 4,
};

/// The alpha texture the rasterizer samples: `data` points at UNORM8 alpha
/// values, `stride` bytes apart within a row, rows `pitch` bytes apart.
pub const AlphaTexture = struct {
    data: []const u8,
    stride: usize,
    pitch: usize,
    width: u32,
    height: u32,
};

/// EXPERIMENTAL upstream: computes a subdivision level per triangle and
/// deduplicates triangles referencing the same UVs; returns the OMM entry
/// count. `levels`/`sources` need `indices.len / 3` elements worst case,
/// `omm_indices` exactly that many. `max_level` is at most 12;
/// `target_edge > 0` makes subdivision adaptive, targeting `target_edge^2`
/// texel area. `V`'s first 8 bytes are the UV float2.
pub fn opacityMapMeasure(comptime V: type, levels: []u8, sources: []u32, omm_indices: []c_int, indices: []const u32, uvs: []const V, texture_width: u32, texture_height: u32, max_level: u4, target_edge: f32) usize {
    contract.checkVertex(V, 2);
    const triangle_count = indices.len / 3;
    assert(levels.len >= triangle_count and sources.len >= triangle_count);
    assert(omm_indices.len >= triangle_count);
    assert(max_level <= 12);
    return shim.zmeshopt_shim_opacityMapMeasure(target_edge, levels.ptr, sources.ptr, omm_indices.ptr, indices.ptr, indices.len, contract.floatPtr(V, uvs), uvs.len, @sizeOf(V), texture_width, texture_height, max_level);
}

/// EXPERIMENTAL upstream: rasterizes opacity for one triangle entry by
/// sampling the alpha texture (bilinear, 0.5 cutoff). Size `result` with
/// `opacityMapEntrySize`.
pub fn opacityMapRasterize(result: []u8, level: u4, states: OpacityStates, uv0: *const [2]f32, uv1: *const [2]f32, uv2: *const [2]f32, texture: AlphaTexture) void {
    assert(result.len >= opacityMapEntrySize(level, states));
    c.meshopt_opacityMapRasterize(result.ptr, level, @intFromEnum(states), @ptrCast(uv0), @ptrCast(uv1), @ptrCast(uv2), texture.data.ptr, texture.stride, texture.pitch, texture.width, texture.height);
}

/// EXPERIMENTAL upstream: bytes one OMM entry occupies at `level`/`states`.
pub fn opacityMapEntrySize(level: u4, states: OpacityStates) usize {
    return c.meshopt_opacityMapEntrySize(level, @intFromEnum(states));
}

/// EXPERIMENTAL upstream: compacts and deduplicates opacity data, merging
/// identical entries and substituting the special indices (-4..-1) where
/// possible; returns the post-compaction entry count. `levels.len` is the
/// entry count going in, `omm_indices.len` the triangle count; all three
/// entry arrays are updated in place — trim `data` afterwards using the last
/// offset plus its entry's size.
pub fn opacityMapCompact(data: []u8, levels: []u8, offsets: []u32, omm_indices: []c_int, states: OpacityStates) usize {
    assert(offsets.len == levels.len);
    return c.meshopt_opacityMapCompact(data.ptr, data.len, levels.ptr, offsets.ptr, levels.len, omm_indices.ptr, omm_indices.len, @intFromEnum(states));
}

test opacityMapMeasure {
    // Two triangles over the same UVs: measure deduplicates them to one entry.
    const uvs = [_][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 } };
    const indices = [_]u32{ 0, 1, 2, 0, 1, 2 };
    var levels: [2]u8 = undefined;
    var sources: [2]u32 = undefined;
    var omm_indices: [2]c_int = undefined;
    const entries = opacityMapMeasure([2]f32, &levels, &sources, &omm_indices, &indices, &uvs, 64, 64, 4, 0);
    try std.testing.expectEqual(@as(usize, 1), entries);
    try std.testing.expectEqual(omm_indices[0], omm_indices[1]);
    try std.testing.expect(levels[0] <= 4);
}

test opacityMapRasterize {
    // A fully opaque texture rasterizes to all-opaque 2-state bits.
    const texture_data = [_]u8{255} ** (8 * 8);
    const texture = AlphaTexture{ .data = &texture_data, .stride = 1, .pitch = 8, .width = 8, .height = 8 };
    const level = 2;
    const size = opacityMapEntrySize(level, .two);
    try std.testing.expectEqual(@as(usize, 2), size); // 4^2 tris / 8 bits
    var result: [2]u8 = undefined;
    opacityMapRasterize(&result, level, .two, &.{ 0, 0 }, &.{ 1, 0 }, &.{ 0, 1 }, texture);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0xff }, &result);
}

test opacityMapCompact {
    // Two identical all-opaque entries compact to the special index -1
    // (predefined fully-opaque), leaving zero stored entries.
    var data = [_]u8{ 0xff, 0xff };
    var levels = [_]u8{ 0, 0 };
    var offsets = [_]u32{ 0, 1 };
    var omm_indices = [_]c_int{ 0, 1 };
    const remaining = opacityMapCompact(&data, &levels, &offsets, &omm_indices, .two);
    try std.testing.expectEqual(@as(usize, 0), remaining);
    for (omm_indices) |i| try std.testing.expect(i < 0);
}
