//! Idiomatic layer: index buffer and index sequence codec.
//!
//! Slice-based wrappers over `src/c/index_codec.zig`. Encoders return the
//! written prefix of the buffer or `error.BufferTooSmall` (the C API's 0).
//! Decoders take the bytes as `Encoded` and return `error.Malformed` for
//! any nonzero C status, with a frame on `failure` saying which.

const std = @import("std");
const aegis = @import("aegis");
const check = @import("check.zig");
const failure_ = @import("failure.zig");
const c = @import("c.zig").index_codec;

/// Index codec format version (`meshopt_encodeIndexVersion` values).
pub const IndexCodecVersion = enum(c_int) {
    /// Decodable by meshoptimizer 0.13+.
    v0 = 0,
    /// The default; decodable by 0.14+.
    v1 = 1,
};

/// Encodes a triangle-list index buffer (<1.5 bytes/triangle typical);
/// returns the written prefix. Size `buffer` with `encodeIndexBufferBound`.
pub fn encodeIndexBuffer(buffer: []u8, indices: []const u32, failure: *failure_.Failure) failure_.Error![]u8 {
    try failure_.held(failure, .encode_index_buffer, check.triangles(indices.len));
    const n = c.meshopt_encodeIndexBuffer(buffer.ptr, buffer.len, indices.ptr, indices.len);
    if (n == 0) return failure_.refuse(failure, .encode_index_buffer, error.BufferTooSmall);
    return buffer[0..n];
}

/// Worst-case encoded size for `encodeIndexBuffer`.
pub fn encodeIndexBufferBound(index_count: usize, vertex_count: usize, failure: *failure_.Failure) failure_.Error!usize {
    try failure_.held(failure, .encode_index_buffer_bound, check.triangles(index_count));
    return c.meshopt_encodeIndexBufferBound(index_count, vertex_count);
}

/// Sets the format version of every later index encode in the process:
/// upstream holds it in one global (`indexcodec.cpp:16`), so this must not
/// run while another thread encodes indices.
pub fn encodeIndexVersion(version: IndexCodecVersion) void {
    c.meshopt_encodeIndexVersion(@backingInt(version));
}

/// Decodes an encoded index buffer into `u16` or `u32` indices. Safe on
/// untrusted input, but decoded indices may still be garbage — validate
/// against the vertex count.
pub fn decodeIndexBuffer(comptime I: type, destination: []I, encoded: failure_.Encoded, failure: *failure_.Failure) failure_.Error!void {
    comptime if (I != u16 and I != u32) @compileError("zmeshopt: the index codec decodes to u16 or u32, not " ++ @typeName(I));
    try failure_.held(failure, .decode_index_buffer, check.triangles(destination.len));
    const bytes = encoded.readForParse();
    try failure_.decoded(failure, .decode_index_buffer, c.meshopt_decodeIndexBuffer(destination.ptr, destination.len, @sizeOf(I), bytes.ptr, bytes.len));
}

/// The format version of an encoded index buffer/sequence, or null if the
/// header is invalid. Non-null does not guarantee decodability.
pub fn decodeIndexVersion(encoded: failure_.Encoded) ?u32 {
    const bytes = encoded.readForParse();
    // Upstream returns -1 for a header it does not read.
    return aegis.int.cast(u32, c.meshopt_decodeIndexVersion(bytes.ptr, bytes.len)) catch null;
}

/// Encodes an index sequence (arbitrary topology; prefer `encodeIndexBuffer`
/// for triangle lists); returns the written prefix.
pub fn encodeIndexSequence(buffer: []u8, indices: []const u32, failure: *failure_.Failure) failure_.Error![]u8 {
    const n = c.meshopt_encodeIndexSequence(buffer.ptr, buffer.len, indices.ptr, indices.len);
    if (n == 0) return failure_.refuse(failure, .encode_index_sequence, error.BufferTooSmall);
    return buffer[0..n];
}

/// Worst-case encoded size for `encodeIndexSequence`.
pub fn encodeIndexSequenceBound(index_count: usize, vertex_count: usize) usize {
    return c.meshopt_encodeIndexSequenceBound(index_count, vertex_count);
}

/// Decodes an encoded index sequence into `u16` or `u32` indices. Safe on
/// untrusted input, but decoded indices may still be garbage.
pub fn decodeIndexSequence(comptime I: type, destination: []I, encoded: failure_.Encoded, failure: *failure_.Failure) failure_.Error!void {
    comptime if (I != u16 and I != u32) @compileError("zmeshopt: the index codec decodes to u16 or u32, not " ++ @typeName(I));
    const bytes = encoded.readForParse();
    try failure_.decoded(failure, .decode_index_sequence, c.meshopt_decodeIndexSequence(destination.ptr, destination.len, @sizeOf(I), bytes.ptr, bytes.len));
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
    var failure: failure_.Failure = .{};
    const indices = [_]u32{ 0, 1, 2, 2, 1, 3 };
    var buffer: [64]u8 = undefined;
    const encoded = try encodeIndexBuffer(&buffer, &indices, &failure);
    try std.testing.expect(encoded.len <= try encodeIndexBufferBound(indices.len, 4, &failure));

    // The codec preserves each triangle up to corner rotation
    // (indexcodec.cpp:245), so compare rotation-normalized.
    var decoded32: [6]u32 = undefined;
    try decodeIndexBuffer(u32, &decoded32, .init(encoded), &failure);
    try expectSameTriangles(&indices, &decoded32);

    var decoded16: [6]u16 = undefined;
    try decodeIndexBuffer(u16, &decoded16, .init(encoded), &failure);
    var widened: [6]u32 = undefined;
    for (decoded16, &widened) |got, *w| w.* = got;
    try expectSameTriangles(&indices, &widened);

    var tiny: [1]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, encodeIndexBuffer(&tiny, &indices, &failure));
}

test decodeIndexVersion {
    var failure: failure_.Failure = .{};
    const indices = [_]u32{ 0, 1, 2 };
    var buffer: [64]u8 = undefined;
    const encoded = try encodeIndexBuffer(&buffer, &indices, &failure);
    try std.testing.expectEqual(@as(?u32, 1), decodeIndexVersion(.init(encoded)));
    try std.testing.expectEqual(@as(?u32, null), decodeIndexVersion(.init(&.{ 0xff, 0xff })));

    var garbled: [64]u8 = undefined;
    @memcpy(garbled[0..encoded.len], encoded);
    garbled[encoded.len - 1] +%= 1; // break the trailing codeaux table marker
    var decoded: [3]u32 = undefined;
    try std.testing.expectError(error.Malformed, decodeIndexBuffer(u32, &decoded, .init(garbled[0 .. encoded.len - 1]), &failure));
    try std.testing.expectEqual(failure_.Frame{ .call = .decode_index_buffer, .reason = .truncated }, failure.frames()[0]);
}

test encodeIndexSequence {
    var failure: failure_.Failure = .{};
    const indices = [_]u32{ 4, 2, 4, 7, 1, 1 };
    var buffer: [64]u8 = undefined;
    const encoded = try encodeIndexSequence(&buffer, &indices, &failure);
    try std.testing.expect(encoded.len <= encodeIndexSequenceBound(indices.len, 8));
    var decoded: [6]u32 = undefined;
    try decodeIndexSequence(u32, &decoded, .init(encoded), &failure);
    try std.testing.expectEqualSlices(u32, &indices, &decoded);
}
