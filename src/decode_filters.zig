//! Idiomatic layer: vertex decode filters.
//!
//! Slice-based wrappers over `src/c/decode_filters.zig`; each transforms the
//! output of `decodeVertexBuffer` in place. Generic over the element type so
//! the C API's "stride must be 4 or 8" prose becomes a compile error.

const std = @import("std");
const c = @import("c.zig").decode_filters;

fn checkStride(comptime E: type, comptime valid: []const usize, comptime what: []const u8) void {
    comptime for (valid) |s| {
        if (@sizeOf(E) == s) break;
    } else @compileError("zmeshopt: " ++ what ++ " does not accept elements of " ++
        @typeName(E) ++ "'s size");
}

/// Decodes octahedral unit vectors (signed K-bit X/Y, Z storing 1.0) in
/// place. Elements are 4 or 8 bytes of normalized integers (e.g. `[4]i8`,
/// `[4]i16`); the W component is preserved as is.
pub fn decodeFilterOct(comptime E: type, buffer: []E) void {
    checkStride(E, &.{ 4, 8 }, "the octahedral filter");
    c.meshopt_decodeFilterOct(buffer.ptr, buffer.len, @sizeOf(E));
}

/// Decodes 3-component quaternion encoding in place. Elements are 8 bytes of
/// 16-bit integers (e.g. `[4]i16`).
pub fn decodeFilterQuat(comptime E: type, buffer: []E) void {
    checkStride(E, &.{8}, "the quaternion filter");
    c.meshopt_decodeFilterQuat(buffer.ptr, buffer.len, @sizeOf(E));
}

/// Decodes exponential floating-point encoding (`2^E*M`) in place, each
/// 32-bit component in isolation; the element size must be divisible by 4.
pub fn decodeFilterExp(comptime E: type, buffer: []E) void {
    comptime if (@sizeOf(E) % 4 != 0) @compileError("zmeshopt: the exponential filter needs an element size divisible " ++
        "by 4, not " ++ @typeName(E) ++ "'s");
    c.meshopt_decodeFilterExp(buffer.ptr, buffer.len, @sizeOf(E));
}

/// Decodes YCoCg(+A) color encoding back to RGBA in place. Elements are 4 or
/// 8 bytes of normalized integers.
pub fn decodeFilterColor(comptime E: type, buffer: []E) void {
    checkStride(E, &.{ 4, 8 }, "the color filter");
    c.meshopt_decodeFilterColor(buffer.ptr, buffer.len, @sizeOf(E));
}

// Round-trip tests for these live next to the encoders in
// `src/encode_filters.zig` — a decode filter is only meaningful on data its
// encoder produced.
