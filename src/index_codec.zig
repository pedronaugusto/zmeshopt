//! Idiomatic layer: index buffer and index sequence codec.
//!
//! Slice-based wrappers over `src/c/index_codec.zig`. Encoders return the
//! written prefix of the buffer or `error.BufferTooSmall` (the C API's 0);
//! decoders return `error.Malformed` for any nonzero C status — upstream
//! documents the distinct codes as diagnostic only.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").index_codec;

/// Index codec format version (`meshopt_encodeIndexVersion` values).
pub const IndexCodecVersion = enum(c_int) {
    /// Decodable by meshoptimizer 0.13+.
    v0 = 0,
    /// The default; decodable by 0.14+.
    v1 = 1,
};

pub const EncodeError = error{BufferTooSmall};
pub const DecodeError = error{Malformed};

/// Encodes a triangle-list index buffer (<1.5 bytes/triangle typical);
/// returns the written prefix. Size `buffer` with `encodeIndexBufferBound`.
pub fn encodeIndexBuffer(buffer: []u8, indices: []const u32) EncodeError![]u8 {
    assert(indices.len % 3 == 0);
    const n = c.meshopt_encodeIndexBuffer(buffer.ptr, buffer.len, indices.ptr, indices.len);
    if (n == 0) return error.BufferTooSmall;
    return buffer[0..n];
}

/// Worst-case encoded size for `encodeIndexBuffer`.
pub fn encodeIndexBufferBound(index_count: usize, vertex_count: usize) usize {
    assert(index_count % 3 == 0);
    return c.meshopt_encodeIndexBufferBound(index_count, vertex_count);
}

/// Sets the index encoder format version. NOT thread safe: must not run
/// concurrently with index encoding.
pub fn encodeIndexVersion(version: IndexCodecVersion) void {
    c.meshopt_encodeIndexVersion(@intFromEnum(version));
}

/// Decodes an encoded index buffer into `u16` or `u32` indices. Safe on
/// untrusted input, but decoded indices may still be garbage — validate
/// against the vertex count.
pub fn decodeIndexBuffer(comptime I: type, destination: []I, buffer: []const u8) DecodeError!void {
    comptime if (I != u16 and I != u32) @compileError("zmeshopt: the index codec decodes to u16 or u32, not " ++ @typeName(I));
    assert(destination.len % 3 == 0);
    if (c.meshopt_decodeIndexBuffer(destination.ptr, destination.len, @sizeOf(I), buffer.ptr, buffer.len) != 0)
        return error.Malformed;
}

/// The format version of an encoded index buffer/sequence, or null if the
/// header is invalid. Non-null does not guarantee decodability.
pub fn decodeIndexVersion(buffer: []const u8) ?u32 {
    const v = c.meshopt_decodeIndexVersion(buffer.ptr, buffer.len);
    return if (v < 0) null else @intCast(v);
}

/// Encodes an index sequence (arbitrary topology; prefer `encodeIndexBuffer`
/// for triangle lists); returns the written prefix.
pub fn encodeIndexSequence(buffer: []u8, indices: []const u32) EncodeError![]u8 {
    const n = c.meshopt_encodeIndexSequence(buffer.ptr, buffer.len, indices.ptr, indices.len);
    if (n == 0) return error.BufferTooSmall;
    return buffer[0..n];
}

/// Worst-case encoded size for `encodeIndexSequence`.
pub fn encodeIndexSequenceBound(index_count: usize, vertex_count: usize) usize {
    return c.meshopt_encodeIndexSequenceBound(index_count, vertex_count);
}

/// Decodes an encoded index sequence into `u16` or `u32` indices. Safe on
/// untrusted input, but decoded indices may still be garbage.
pub fn decodeIndexSequence(comptime I: type, destination: []I, buffer: []const u8) DecodeError!void {
    comptime if (I != u16 and I != u32) @compileError("zmeshopt: the index codec decodes to u16 or u32, not " ++ @typeName(I));
    if (c.meshopt_decodeIndexSequence(destination.ptr, destination.len, @sizeOf(I), buffer.ptr, buffer.len) != 0)
        return error.Malformed;
}

fn expectSameTriangles(want: []const u32, got: []const u32) !void {
    try std.testing.expectEqual(want.len, got.len);
    var i: usize = 0;
    while (i < want.len) : (i += 3) {
        for (0..3) |r| {
            if (want[i] == got[i + r] and
                want[i + 1] == got[i + (r + 1) % 3] and
                want[i + 2] == got[i + (r + 2) % 3]) break;
        } else return error.TestTriangleMismatch;
    }
}

test encodeIndexBuffer {
    const indices = [_]u32{ 0, 1, 2, 2, 1, 3 };
    var buffer: [64]u8 = undefined;
    const encoded = try encodeIndexBuffer(&buffer, &indices);
    try std.testing.expect(encoded.len <= encodeIndexBufferBound(indices.len, 4));

    // The codec preserves each triangle up to corner rotation
    // (indexcodec.cpp:245), so compare rotation-normalized.
    var decoded32: [6]u32 = undefined;
    try decodeIndexBuffer(u32, &decoded32, encoded);
    try expectSameTriangles(&indices, &decoded32);

    var decoded16: [6]u16 = undefined;
    try decodeIndexBuffer(u16, &decoded16, encoded);
    var widened: [6]u32 = undefined;
    for (decoded16, &widened) |got, *w| w.* = got;
    try expectSameTriangles(&indices, &widened);

    var tiny: [1]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, encodeIndexBuffer(&tiny, &indices));
}

test decodeIndexVersion {
    const indices = [_]u32{ 0, 1, 2 };
    var buffer: [64]u8 = undefined;
    const encoded = try encodeIndexBuffer(&buffer, &indices);
    try std.testing.expectEqual(@as(?u32, 1), decodeIndexVersion(encoded));
    try std.testing.expectEqual(@as(?u32, null), decodeIndexVersion(&.{ 0xff, 0xff }));

    var garbled: [64]u8 = undefined;
    @memcpy(garbled[0..encoded.len], encoded);
    garbled[encoded.len - 1] +%= 1; // break the trailing codeaux table marker
    var decoded: [3]u32 = undefined;
    try std.testing.expectError(error.Malformed, decodeIndexBuffer(u32, &decoded, garbled[0 .. encoded.len - 1]));
}

test encodeIndexSequence {
    const indices = [_]u32{ 4, 2, 4, 7, 1, 1 };
    var buffer: [64]u8 = undefined;
    const encoded = try encodeIndexSequence(&buffer, &indices);
    try std.testing.expect(encoded.len <= encodeIndexSequenceBound(indices.len, 8));
    var decoded: [6]u32 = undefined;
    try decodeIndexSequence(u32, &decoded, encoded);
    try std.testing.expectEqualSlices(u32, &indices, &decoded);
}
