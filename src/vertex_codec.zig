//! Idiomatic layer: vertex buffer codec.
//!
//! Slice-based wrappers over `src/c/vertex_codec.zig`, generic over the
//! vertex type: all of `@sizeOf(V)` is encoded verbatim, padding included, so
//! `V` should have none (or keep it zero-initialized).

const std = @import("std");
const c = @import("c.zig").vertex_codec;

/// Vertex codec format version (`meshopt_encodeVertexVersion` values).
pub const VertexCodecVersion = enum(c_int) {
    /// Decodable by meshoptimizer 0.13+.
    v0 = 0,
    /// The default; decodable by 0.23+, supports compression levels.
    v1 = 1,
};

pub const EncodeError = error{BufferTooSmall};
pub const DecodeError = error{Malformed};

fn checkCodecVertex(comptime V: type) void {
    comptime if (@sizeOf(V) % 4 != 0 or @sizeOf(V) > 256) @compileError("zmeshopt: the vertex codec requires a vertex size that is a " ++
        "multiple of 4 and at most 256, not " ++ @typeName(V) ++ "'s");
}

/// Encodes a vertex buffer; returns the written prefix. Size `buffer` with
/// `encodeVertexBufferBound`.
pub fn encodeVertexBuffer(comptime V: type, buffer: []u8, vertices: []const V) EncodeError![]u8 {
    checkCodecVertex(V);
    const n = c.meshopt_encodeVertexBuffer(buffer.ptr, buffer.len, vertices.ptr, vertices.len, @sizeOf(V));
    if (n == 0) return error.BufferTooSmall;
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
pub fn encodeVertexBufferLevel(comptime V: type, buffer: []u8, vertices: []const V, level: u2, version: ?VertexCodecVersion) EncodeError![]u8 {
    checkCodecVertex(V);
    const v: c_int = if (version) |ver| @intFromEnum(ver) else -1;
    const n = c.meshopt_encodeVertexBufferLevel(buffer.ptr, buffer.len, vertices.ptr, vertices.len, @sizeOf(V), level, v);
    if (n == 0) return error.BufferTooSmall;
    return buffer[0..n];
}

/// Sets the vertex encoder format version. NOT thread safe: must not run
/// concurrently with vertex encoding.
pub fn encodeVertexVersion(version: VertexCodecVersion) void {
    c.meshopt_encodeVertexVersion(@intFromEnum(version));
}

/// Decodes an encoded vertex buffer. Safe on untrusted input, but may produce
/// garbage vertex data.
pub fn decodeVertexBuffer(comptime V: type, destination: []V, buffer: []const u8) DecodeError!void {
    checkCodecVertex(V);
    if (c.meshopt_decodeVertexBuffer(destination.ptr, destination.len, @sizeOf(V), buffer.ptr, buffer.len) != 0)
        return error.Malformed;
}

/// The format version of an encoded vertex buffer, or null if the header is
/// invalid. Non-null does not guarantee decodability.
pub fn decodeVertexVersion(buffer: []const u8) ?u32 {
    const v = c.meshopt_decodeVertexVersion(buffer.ptr, buffer.len);
    return if (v < 0) null else @intCast(v);
}

test encodeVertexBuffer {
    const Vertex = extern struct { position: [3]f32, uv: [2]f32 };
    const vertices = [_]Vertex{
        .{ .position = .{ 0, 0, 0 }, .uv = .{ 0, 0 } },
        .{ .position = .{ 1, 0, 0 }, .uv = .{ 1, 0 } },
        .{ .position = .{ 0, 1, 0.5 }, .uv = .{ 0, 1 } },
    };
    var buffer: [256]u8 = undefined;
    const encoded = try encodeVertexBuffer(Vertex, &buffer, &vertices);
    try std.testing.expect(encoded.len <= encodeVertexBufferBound(Vertex, vertices.len));

    var decoded: [3]Vertex = undefined;
    try decodeVertexBuffer(Vertex, &decoded, encoded);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&vertices), std.mem.sliceAsBytes(&decoded));

    var tiny: [4]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, encodeVertexBuffer(Vertex, &tiny, &vertices));
    try std.testing.expectError(error.Malformed, decodeVertexBuffer(Vertex, &decoded, encoded[0 .. encoded.len - 1]));
}

test encodeVertexBufferLevel {
    const vertices = [_][4]f32{ .{ 1, 2, 3, 4 }, .{ 1, 2, 3, 5 } };
    var buffer: [256]u8 = undefined;
    // Level 0/version 0 must still round-trip and report its version.
    const encoded = try encodeVertexBufferLevel([4]f32, &buffer, &vertices, 0, .v0);
    try std.testing.expectEqual(@as(?u32, 0), decodeVertexVersion(encoded));
    var decoded: [2][4]f32 = undefined;
    try decodeVertexBuffer([4]f32, &decoded, encoded);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&vertices), std.mem.sliceAsBytes(&decoded));
    try std.testing.expectEqual(@as(?u32, null), decodeVertexVersion(&.{0xff}));
}
