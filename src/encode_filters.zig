//! Idiomatic layer: vertex encode filters.
//!
//! Slice-based wrappers over `src/c/encode_filters.zig`; each produces data
//! `encodeVertexBuffer` compresses well and the matching decode filter
//! restores. Generic over the destination element type, which fixes the
//! stride the C API takes as a runtime argument.

const std = @import("std");
const assert = std.debug.assert;
const check = @import("check.zig");
const failure_ = @import("failure.zig");
const c = @import("c.zig").encode_filters;

pub const EncodeExpMode = c.EncodeExpMode;

/// Encodes unit vectors octahedrally with K-bit signed X/Y (2 <= `bits`).
/// 4-byte elements hold up to 8 bits per component, 8-byte up to 16; input is
/// one float4 per element (Z will store 1.0, W is preserved as a snorm).
pub fn encodeFilterOct(comptime E: type, destination: []E, bits: u5, data: []const [4]f32, failure: *failure_.Failure) failure_.Error!void {
    comptime assert(@sizeOf(E) == 4 or @sizeOf(E) == 8);
    try failure_.held(failure, .encode_filter_oct, check.room(bits, 2));
    try failure_.held(failure, .encode_filter_oct, check.range(bits <= if (@sizeOf(E) == 4) 8 else 16));
    try failure_.held(failure, .encode_filter_oct, check.same(data.len, destination.len));
    c.meshopt_encodeFilterOct(destination.ptr, destination.len, @sizeOf(E), bits, @ptrCast(data.ptr)); // safe: [4]f32 elements read as their flat floats
}

/// Encodes unit quaternions with K-bit components (4 <= `bits` <= 16) into
/// 8-byte elements; input is one float4 per element.
pub fn encodeFilterQuat(comptime E: type, destination: []E, bits: u5, data: []const [4]f32, failure: *failure_.Failure) failure_.Error!void {
    comptime assert(@sizeOf(E) == 8);
    try failure_.held(failure, .encode_filter_quat, check.room(bits, 4));
    try failure_.held(failure, .encode_filter_quat, check.range(bits <= 16));
    try failure_.held(failure, .encode_filter_quat, check.same(data.len, destination.len));
    c.meshopt_encodeFilterQuat(destination.ptr, destination.len, @sizeOf(E), bits, @ptrCast(data.ptr)); // safe: [4]f32 elements read as their flat floats
}

/// Encodes finite floats with an 8-bit exponent and K-bit mantissa
/// (1 <= `bits` <= 24), exponents shared per `mode`; each element of `E`
/// holds `@sizeOf(E) / 4` components, and `data` supplies that many floats
/// per element.
pub fn encodeFilterExp(comptime E: type, destination: []E, bits: u5, data: []const f32, mode: EncodeExpMode, failure: *failure_.Failure) failure_.Error!void {
    comptime assert(@sizeOf(E) % 4 == 0);
    comptime assert(@sizeOf(E) <= 256);
    try failure_.held(failure, .encode_filter_exp, check.room(bits, 1));
    try failure_.held(failure, .encode_filter_exp, check.range(bits <= 24));
    try failure_.held(failure, .encode_filter_exp, check.same(data.len, destination.len * (@sizeOf(E) / 4)));
    c.meshopt_encodeFilterExp(destination.ptr, destination.len, @sizeOf(E), bits, data.ptr, mode);
}

/// Encodes RGBA colors via YCoCg with K-bit components (2 <= `bits`; alpha
/// uses one bit fewer). 4-byte elements hold up to 8 bits per component,
/// 8-byte up to 16; input is one float4 per element.
pub fn encodeFilterColor(comptime E: type, destination: []E, bits: u5, data: []const [4]f32, failure: *failure_.Failure) failure_.Error!void {
    comptime assert(@sizeOf(E) == 4 or @sizeOf(E) == 8);
    try failure_.held(failure, .encode_filter_color, check.room(bits, 2));
    try failure_.held(failure, .encode_filter_color, check.range(bits <= if (@sizeOf(E) == 4) 8 else 16));
    try failure_.held(failure, .encode_filter_color, check.same(data.len, destination.len));
    c.meshopt_encodeFilterColor(destination.ptr, destination.len, @sizeOf(E), bits, @ptrCast(data.ptr)); // safe: [4]f32 elements read as their flat floats
}

const decode = @import("decode_filters.zig");

test encodeFilterOct {
    var failure: failure_.Failure = .{};
    const inv_sqrt3 = 1.0 / @sqrt(3.0);
    const data = [_][4]f32{ .{ 1, 0, 0, 1 }, .{ inv_sqrt3, inv_sqrt3, inv_sqrt3, -1 } };
    var packed_vectors: [2][4]i16 = undefined;
    try encodeFilterOct([4]i16, &packed_vectors, 12, &data, &failure);
    decode.decodeFilterOct([4]i16, &packed_vectors);
    for (data, packed_vectors) |want, got| {
        for (0..3) |i| {
            const component = @as(f32, @floatFromInt(got[i])) / 32767.0;
            try std.testing.expectApproxEqAbs(want[i], component, 1.0 / 256.0);
        }
    }
}

test encodeFilterQuat {
    var failure: failure_.Failure = .{};
    const half_sqrt2 = @sqrt(2.0) / 2.0;
    const data = [_][4]f32{ .{ 0, 0, 0, 1 }, .{ half_sqrt2, 0, 0, half_sqrt2 } };
    var packed_quats: [2][4]i16 = undefined;
    try encodeFilterQuat([4]i16, &packed_quats, 12, &data, &failure);
    decode.decodeFilterQuat([4]i16, &packed_quats);
    for (data, packed_quats) |want, got| {
        var dot: f32 = 0;
        for (0..4) |i| dot += want[i] * @as(f32, @floatFromInt(got[i])) / 32767.0;
        // Quaternion double cover: q and -q are the same rotation.
        try std.testing.expectApproxEqAbs(1.0, @abs(dot), 1.0 / 512.0);
    }
}

test encodeFilterExp {
    var failure: failure_.Failure = .{};
    const data = [_]f32{ 1.0, -2.5, 0.125, 1000.0, 0.0, 3.14159 };
    var encoded: [2][3]u32 = undefined;
    try encodeFilterExp([3]u32, &encoded, 20, &data, .shared_vector, &failure);
    decode.decodeFilterExp([3]u32, &encoded);
    const roundtripped: [6]f32 = @bitCast(encoded);
    for (data, roundtripped) |want, got| {
        try std.testing.expectApproxEqRel(want, got, 1.0 / 1024.0);
    }
    // expectApproxEqRel rejects want == 0; check the exact zero separately.
    try std.testing.expectEqual(@as(f32, 0), roundtripped[4]);
}

test encodeFilterColor {
    var failure: failure_.Failure = .{};
    const data = [_][4]f32{ .{ 1, 0, 0, 1 }, .{ 0.25, 0.5, 0.75, 0.5 } };
    var packed_colors: [2][4]u16 = undefined;
    try encodeFilterColor([4]u16, &packed_colors, 12, &data, &failure);
    decode.decodeFilterColor([4]u16, &packed_colors);
    for (data, packed_colors) |want, got| {
        for (0..4) |i| {
            const component = @as(f32, @floatFromInt(got[i])) / 65535.0;
            try std.testing.expectApproxEqAbs(want[i], component, 1.0 / 512.0);
        }
    }
}
