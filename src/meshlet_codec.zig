//! Idiomatic layer: meshlet codec.
//!
//! Slice-based wrappers over `src/c/meshlet_codec.zig`. One meshlet per
//! call; the counts and buffer size must match the encoding exactly on
//! decode, so keep them alongside the encoded bytes.

const std = @import("std");
const check = @import("check.zig");
const failure_ = @import("failure.zig");
const c = @import("c.zig").meshlet_codec;

pub const EncodeError = error{BufferTooSmall};

/// Encodes ONE meshlet's vertex references and triangles; returns the
/// written prefix. Size `buffer` with `encodeMeshletBound`; `vertices` may be
/// empty to encode triangle data only; both counts must be <= 256. For best
/// results run `optimizeMeshletLevel` (level 3) on the meshlet first.
pub fn encodeMeshlet(buffer: []u8, vertices: []const u32, triangles: []const u8) (EncodeError || check.Error)![]u8 {
    try check.range(vertices.len <= 256);
    try check.triangles(triangles.len);
    try check.range(triangles.len / 3 <= 256);
    const n = c.meshopt_encodeMeshlet(buffer.ptr, buffer.len, if (vertices.len == 0) null else vertices.ptr, vertices.len, triangles.ptr, triangles.len / 3);
    if (n == 0) return error.BufferTooSmall;
    return buffer[0..n];
}

/// Worst-case encoded size for `encodeMeshlet`.
pub fn encodeMeshletBound(max_vertices: usize, max_triangles: usize) usize {
    return c.meshopt_encodeMeshletBound(max_vertices, max_triangles);
}

/// Decodes one encoded meshlet into `vertex_count` 16- or 32-bit vertex
/// references (`I`) and `triangle_count` 3-byte or packed 4-byte triangles
/// (`T` = `[3]u8` or `u32`, packed as `a | b<<8 | c<<16`): the counts the
/// encoding carried, each at most 256. The decoder writes whole words, so
/// each slice holds its count's bytes rounded up to 4 (`meshoptimizer.h:340`).
/// Safe on untrusted input, but may produce garbage data.
pub fn decodeMeshlet(comptime I: type, comptime T: type, vertices: []align(4) I, vertex_count: usize, triangles: []align(4) T, triangle_count: usize, encoded: failure_.Encoded, failure: *failure_.Failure) failure_.DecodeError!void {
    comptime if (I != u16 and I != u32) @compileError("zmeshopt: the meshlet codec decodes vertex references to u16 or u32, not " ++ @typeName(I));
    comptime if (T != [3]u8 and T != u32) @compileError("zmeshopt: the meshlet codec decodes triangles to [3]u8 or packed u32, not " ++ @typeName(T));
    try failure_.held(failure, .decode_meshlet, check.range(vertex_count <= 256 and triangle_count <= 256));
    try failure_.held(failure, .decode_meshlet, check.room(vertices.len * @sizeOf(I), std.mem.alignForward(usize, vertex_count * @sizeOf(I), 4)));
    try failure_.held(failure, .decode_meshlet, check.room(triangles.len * @sizeOf(T), std.mem.alignForward(usize, triangle_count * @sizeOf(T), 4)));
    const bytes = encoded.readForParse();
    try failure_.decoded(failure, .decode_meshlet, c.meshopt_decodeMeshlet(if (vertex_count == 0) null else vertices.ptr, vertex_count, @sizeOf(I), triangles.ptr, triangle_count, @sizeOf(T), bytes.ptr, bytes.len));
}

/// Raw-mode meshlet decode of `vertex_count` vertex references and
/// `triangle_count` packed triangles, each at most 256. The SIMD decoder
/// writes whole groups of 4, so each slice holds its count rounded up to a
/// multiple of 4 (`meshletcodec.cpp:874-883`). Safe on untrusted input.
pub fn decodeMeshletRaw(vertices: []align(16) u32, vertex_count: usize, triangles: []align(16) u32, triangle_count: usize, encoded: failure_.Encoded, failure: *failure_.Failure) failure_.DecodeError!void {
    try failure_.held(failure, .decode_meshlet_raw, check.range(vertex_count <= 256 and triangle_count <= 256));
    try failure_.held(failure, .decode_meshlet_raw, check.room(vertices.len, std.mem.alignForward(usize, vertex_count, 4)));
    try failure_.held(failure, .decode_meshlet_raw, check.room(triangles.len, std.mem.alignForward(usize, triangle_count, 4)));
    const bytes = encoded.readForParse();
    try failure_.decoded(failure, .decode_meshlet_raw, c.meshopt_decodeMeshletRaw(if (vertex_count == 0) null else vertices.ptr, vertex_count, triangles.ptr, triangle_count, bytes.ptr, bytes.len));
}

test encodeMeshlet {
    const vertices = [_]u32{ 10, 11, 12, 13 };
    const triangles = [_]u8{ 0, 1, 2, 2, 1, 3 };
    var buffer: [256]u8 = undefined;
    const encoded = try encodeMeshlet(&buffer, &vertices, &triangles);
    try std.testing.expect(encoded.len <= encodeMeshletBound(vertices.len, triangles.len / 3));

    var decoded_vertices: [4]u32 align(4) = undefined;
    // Two triangles are 6 bytes, which the decoder writes as 8.
    var decoded_triangles: [3][3]u8 align(4) = undefined;
    var failure: failure_.Failure = .{};
    try decodeMeshlet(u32, [3]u8, &decoded_vertices, 4, &decoded_triangles, 2, .init(encoded), &failure);
    try std.testing.expectEqualSlices(u32, &vertices, &decoded_vertices);
    try std.testing.expectEqualSlices(u8, &triangles, @as([*]const u8, @ptrCast(&decoded_triangles))[0..6]);

    var tiny: [1]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, encodeMeshlet(&tiny, &vertices, &triangles));
}

test decodeMeshletRaw {
    const vertices = [_]u32{ 7, 8, 9 };
    const triangles = [_]u8{ 0, 1, 2 };
    var buffer: [256]u8 = undefined;
    const encoded = try encodeMeshlet(&buffer, &vertices, &triangles);

    var decoded_vertices: [4]u32 align(16) = undefined;
    var decoded_triangles: [4]u32 align(16) = undefined;
    var failure: failure_.Failure = .{};
    try decodeMeshletRaw(&decoded_vertices, 3, &decoded_triangles, 1, .init(encoded), &failure);
    try std.testing.expectEqualSlices(u32, &vertices, decoded_vertices[0..3]);
    const t = decoded_triangles[0];
    try std.testing.expectEqual(@as(u32, 0 | (1 << 8) | (2 << 16)), t & 0xffffff);
}

test "raw decoding refuses outputs without room for the groups the decoder writes" {
    const vertices = [_]u32{ 7, 8, 9 };
    const triangles = [_]u8{ 0, 1, 2 };
    var buffer: [256]u8 = undefined;
    const encoded = try encodeMeshlet(&buffer, &vertices, &triangles);

    var exact_vertices: [3]u32 align(16) = undefined;
    var decoded_triangles: [4]u32 align(16) = undefined;
    var failure: failure_.Failure = .{};
    try std.testing.expectError(error.BufferTooSmall, decodeMeshletRaw(&exact_vertices, 3, &decoded_triangles, 1, .init(encoded), &failure));
    try std.testing.expectEqual(failure_.Frame{ .call = .decode_meshlet_raw, .reason = .buffer_too_small }, failure.frames()[0]);
}

test "a meshlet's outputs without room for the words the decoder writes are refused" {
    const vertices = [_]u32{ 7, 8, 9 };
    const triangles = [_]u8{ 0, 1, 2 };
    var buffer: [256]u8 = undefined;
    const encoded = try encodeMeshlet(&buffer, &vertices, &triangles);

    var decoded_vertices: [3]u16 align(4) = undefined;
    var exact_triangle: [1][3]u8 align(4) = undefined;
    var failure: failure_.Failure = .{};
    try std.testing.expectError(error.BufferTooSmall, decodeMeshlet(u16, [3]u8, &decoded_vertices, 3, &exact_triangle, 1, .init(encoded), &failure));
    try std.testing.expectEqual(failure_.Frame{ .call = .decode_meshlet, .reason = .buffer_too_small }, failure.frames()[0]);
}
