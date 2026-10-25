//! Idiomatic layer: vertex buffer codec.
//!
//! Slice-based wrappers over `src/c/vertex_codec.zig`, generic over the
//! vertex type: all of `@sizeOf(V)` is encoded verbatim, padding included, so
//! `V` should have none (or keep it zero-initialized).

const std = @import("std");
const aegis = @import("aegis");
const failure_ = @import("failure.zig");
const c = @import("c.zig").vertex_codec;

/// Vertex codec format version (`meshopt_encodeVertexVersion` values).
pub const VertexCodecVersion = enum(c_int) {
    /// Decodable by meshoptimizer 0.13+.
    v0 = 0,
    /// The default; decodable by 0.23+, supports compression levels.
    v1 = 1,
};

fn checkCodecVertex(comptime V: type) void {
    comptime if (@sizeOf(V) % 4 != 0 or @sizeOf(V) > 256) @compileError("zmeshopt: the vertex codec requires a vertex size that is a " ++
        "multiple of 4 and at most 256, not " ++ @typeName(V) ++ "'s");
}

/// Encodes a vertex buffer; returns the written prefix. Size `buffer` with
/// `encodeVertexBufferBound`.
pub fn encodeVertexBuffer(comptime V: type, buffer: []u8, vertices: []const V, failure: *failure_.Failure) failure_.Error![]u8 {
    checkCodecVertex(V);
    const n = c.meshopt_encodeVertexBuffer(buffer.ptr, buffer.len, vertices.ptr, vertices.len, @sizeOf(V));
    if (n == 0) return failure_.refuse(failure, .encode_vertex_buffer, error.BufferTooSmall);
    return buffer[0..n];
}

/// Worst-case encoded size for `encodeVertexBuffer` on `vertex_count`
/// vertices of type `V`.
pub fn encodeVertexBufferBound(comptime V: type, vertex_count: usize) usize {
    checkCodecVertex(V);
    return c.meshopt_encodeVertexBufferBound(vertex_count, @sizeOf(V));
}

/// `encodeVertexBuffer` with an explicit compression level ([0, 3]; the plain
/// function implies 2) and format version (null = the process default set via
/// `encodeVertexVersion`; levels only take effect with version 1).
pub fn encodeVertexBufferLevel(comptime V: type, buffer: []u8, vertices: []const V, level: u2, version: ?VertexCodecVersion, failure: *failure_.Failure) failure_.Error![]u8 {
    checkCodecVertex(V);
    const v: c_int = if (version) |ver| @backingInt(ver) else -1;
    const n = c.meshopt_encodeVertexBufferLevel(buffer.ptr, buffer.len, vertices.ptr, vertices.len, @sizeOf(V), level, v);
    if (n == 0) return failure_.refuse(failure, .encode_vertex_buffer_level, error.BufferTooSmall);
    return buffer[0..n];
}

/// Sets the vertex encoder format version. NOT thread safe: must not run
/// concurrently with vertex encoding.
pub fn encodeVertexVersion(version: VertexCodecVersion) void {
    c.meshopt_encodeVertexVersion(@backingInt(version));
}

/// Decodes an encoded vertex buffer. Safe on untrusted input, but may produce
/// garbage vertex data.
pub fn decodeVertexBuffer(comptime V: type, destination: []V, encoded: failure_.Encoded, failure: *failure_.Failure) failure_.Error!void {
    checkCodecVertex(V);
    const bytes = encoded.readForParse();
    try failure_.decoded(failure, .decode_vertex_buffer, c.meshopt_decodeVertexBuffer(destination.ptr, destination.len, @sizeOf(V), bytes.ptr, bytes.len));
}

/// The format version of an encoded vertex buffer, or null if the header is
/// invalid. Non-null does not guarantee decodability.
pub fn decodeVertexVersion(encoded: failure_.Encoded) ?u32 {
    const bytes = encoded.readForParse();
    // Upstream returns -1 for a header it does not read.
    return aegis.int.cast(u32, c.meshopt_decodeVertexVersion(bytes.ptr, bytes.len)) catch null;
}

test encodeVertexBuffer {
    var failure: failure_.Failure = .{};
    const Vertex = extern struct { position: [3]f32, uv: [2]f32 };
    const vertices = [_]Vertex{
        .{ .position = .{ 0, 0, 0 }, .uv = .{ 0, 0 } },
        .{ .position = .{ 1, 0, 0 }, .uv = .{ 1, 0 } },
        .{ .position = .{ 0, 1, 0.5 }, .uv = .{ 0, 1 } },
    };
    var buffer: [256]u8 = undefined;
    const encoded = try encodeVertexBuffer(Vertex, &buffer, &vertices, &failure);
    try std.testing.expect(encoded.len <= encodeVertexBufferBound(Vertex, vertices.len));

    var decoded: [3]Vertex = undefined;
    try decodeVertexBuffer(Vertex, &decoded, .init(encoded), &failure);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&vertices), std.mem.sliceAsBytes(&decoded));

    var tiny: [4]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, encodeVertexBuffer(Vertex, &tiny, &vertices, &failure));
    try std.testing.expectError(error.Malformed, decodeVertexBuffer(Vertex, &decoded, .init(encoded[0 .. encoded.len - 1]), &failure));
    try std.testing.expectEqualSlices(failure_.Frame, &.{
        .{ .call = .encode_vertex_buffer, .reason = .buffer_too_small },
        .{ .call = .decode_vertex_buffer, .reason = .mismatched_end },
    }, failure.frames());
}

test encodeVertexBufferLevel {
    var failure: failure_.Failure = .{};
    const vertices = [_][4]f32{ .{ 1, 2, 3, 4 }, .{ 1, 2, 3, 5 } };
    var buffer: [256]u8 = undefined;
    // Level 0/version 0 must still round-trip and report its version.
    const encoded = try encodeVertexBufferLevel([4]f32, &buffer, &vertices, 0, .v0, &failure);
    try std.testing.expectEqual(@as(?u32, 0), decodeVertexVersion(.init(encoded)));
    var decoded: [2][4]f32 = undefined;
    try decodeVertexBuffer([4]f32, &decoded, .init(encoded), &failure);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&vertices), std.mem.sliceAsBytes(&decoded));
    try std.testing.expectEqual(@as(?u32, null), decodeVertexVersion(.init(&.{0xff})));
}
