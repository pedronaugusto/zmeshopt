//! Idiomatic layer: meshlet codec.
//!
//! Slice-based wrappers over `src/c/meshlet_codec.zig`. One meshlet per
//! call; the counts and buffer size must match the encoding exactly on
//! decode, so keep them alongside the encoded bytes.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").meshlet_codec;

pub const EncodeError = error{BufferTooSmall};
pub const DecodeError = error{Malformed};

/// Encodes ONE meshlet's vertex references and triangles; returns the
/// written prefix. Size `buffer` with `encodeMeshletBound`; `vertices` may be
/// empty to encode triangle data only; both counts must be <= 256. For best
/// results run `optimizeMeshletLevel` (level 3) on the meshlet first.
pub fn encodeMeshlet(buffer: []u8, vertices: []const u32, triangles: []const u8) EncodeError![]u8 {
    assert(vertices.len <= 256);
    assert(triangles.len % 3 == 0 and triangles.len / 3 <= 256);
    const n = c.meshopt_encodeMeshlet(buffer.ptr, buffer.len, if (vertices.len == 0) null else vertices.ptr, vertices.len, triangles.ptr, triangles.len / 3);
    if (n == 0) return error.BufferTooSmall;
    return buffer[0..n];
}

/// Worst-case encoded size for `encodeMeshlet`.
pub fn encodeMeshletBound(max_vertices: usize, max_triangles: usize) usize {
    return c.meshopt_encodeMeshletBound(max_vertices, max_triangles);
}

/// Decodes one encoded meshlet into 16- or 32-bit vertex references (`I`)
/// and 3-byte or packed 4-byte triangles (`T` = `[3]u8` or `u32`, packed as
/// `a | b<<8 | c<<16`). Both outputs must be what the encoding carried:
/// `vertices.len` and `triangles.len` are the exact counts. Safe on
/// untrusted input, but may produce garbage data.
pub fn decodeMeshlet(comptime I: type, comptime T: type, vertices: []align(4) I, triangles: []align(4) T, buffer: []const u8) DecodeError!void {
    comptime if (I != u16 and I != u32) @compileError(
        "zmeshopt: the meshlet codec decodes vertex references to u16 or u32, not " ++ @typeName(I));
    comptime if (T != [3]u8 and T != u32) @compileError(
        "zmeshopt: the meshlet codec decodes triangles to [3]u8 or packed u32, not " ++ @typeName(T));
    if (c.meshopt_decodeMeshlet(if (vertices.len == 0) null else vertices.ptr, vertices.len, @sizeOf(I), triangles.ptr, triangles.len, @sizeOf(T), buffer.ptr, buffer.len) != 0)
        return error.Malformed;
}

/// Raw-mode meshlet decode into 32-bit outputs; give both slices space
/// aligned (and padded) to 16 bytes for SIMD decoding. Safe on untrusted
/// input.
pub fn decodeMeshletRaw(vertices: []align(16) u32, triangles: []align(16) u32, buffer: []const u8) DecodeError!void {
    if (c.meshopt_decodeMeshletRaw(if (vertices.len == 0) null else vertices.ptr, vertices.len, triangles.ptr, triangles.len, buffer.ptr, buffer.len) != 0)
        return error.Malformed;
}

test encodeMeshlet {
    const vertices = [_]u32{ 10, 11, 12, 13 };
    const triangles = [_]u8{ 0, 1, 2, 2, 1, 3 };
    var buffer: [256]u8 = undefined;
    const encoded = try encodeMeshlet(&buffer, &vertices, &triangles);
    try std.testing.expect(encoded.len <= encodeMeshletBound(vertices.len, triangles.len / 3));

    var decoded_vertices: [4]u32 align(4) = undefined;
    var decoded_triangles: [2][3]u8 align(4) = undefined;
    try decodeMeshlet(u32, [3]u8, &decoded_vertices, &decoded_triangles, encoded);
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
    try decodeMeshletRaw(decoded_vertices[0..3], decoded_triangles[0..1], encoded);
    try std.testing.expectEqualSlices(u32, &vertices, decoded_vertices[0..3]);
    const t = decoded_triangles[0];
    try std.testing.expectEqual(@as(u32, 0 | (1 << 8) | (2 << 16)), t & 0xffffff);
}
