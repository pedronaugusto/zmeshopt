//! Idiomatic layer: scalar quantization.
//!
//! Wrappers over `src/c/quantize.zig`, plus Zig reimplementations of the two
//! helpers upstream ships only as inline C++ (`meshopt_quantizeUnorm`,
//! `meshopt_quantizeSnorm` — no symbol exists for a binding to call). The
//! reimplementations mirror `libs/meshoptimizer/src/meshoptimizer.h:1123-1143`
//! operation for operation; the tests pin the values that math produces.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").quantize;

/// Quantizes a float to IEEE-754 fp16: +-inf on overflow, NaN preserved,
/// denormals flushed to zero, round to nearest. Representable magnitude
/// range [6e-5, 65504]; max relative reconstruction error 5e-4.
pub fn quantizeHalf(v: f32) u16 {
    return c.meshopt_quantizeHalf(v);
}

/// Quantizes a float to `bits` significant mantissa bits (1..23), staying in
/// fp32 binary representation. Inf/NaN preserved, denormals flushed to zero,
/// round to nearest.
pub fn quantizeFloat(v: f32, bits: u5) f32 {
    assert(bits >= 1 and bits <= 23);
    return c.meshopt_quantizeFloat(v, bits);
}

/// Reverses fp16 quantization; Inf/NaN preserved, denormals flushed to zero.
pub fn dequantizeHalf(h: u16) f32 {
    return c.meshopt_dequantizeHalf(h);
}

/// Quantizes a float in [0..1] into an N-bit unorm (`bits` in 1..23);
/// out-of-range input is clamped. Assumes reconstruction `q / (2^N - 1)`.
/// Zig reimplementation of upstream's inline C++
/// (`meshoptimizer.h:1123-1131`); the maximum reconstruction error is
/// `1 / 2^(N+1)`.
pub fn quantizeUnorm(v: f32, bits: u5) i32 {
    assert(bits >= 1 and bits <= 23);
    const scale: f32 = @floatFromInt((@as(i32, 1) << bits) - 1);
    var x = v;
    x = if (x >= 0) x else 0;
    x = if (x <= 1) x else 1;
    return @intFromFloat(x * scale + 0.5);
}

/// Quantizes a float in [-1..1] into an N-bit snorm (`bits` in 2..23);
/// out-of-range input is clamped. Assumes reconstruction
/// `q / (2^(N-1) - 1)` (fixed-function normalized conversion, except early
/// OpenGL). Zig reimplementation of upstream's inline C++
/// (`meshoptimizer.h:1133-1143`); the maximum reconstruction error is
/// `1 / 2^N`.
pub fn quantizeSnorm(v: f32, bits: u5) i32 {
    assert(bits >= 2 and bits <= 23);
    const scale: f32 = @floatFromInt((@as(i32, 1) << (bits - 1)) - 1);
    const round: f32 = if (v >= 0) 0.5 else -0.5;
    var x = v;
    x = if (x >= -1) x else -1;
    x = if (x <= 1) x else 1;
    return @intFromFloat(x * scale + round);
}

/// EXPERIMENTAL upstream: shared exponent for quantizing any position inside
/// `[minv, maxv]` onto a 24-bit integer grid: `iv = round(v / 2^exponent)`.
/// `min_exp` floors the returned exponent to cap precision; `max_bits` caps
/// the quantized range.
pub fn computePositionExponent(minv: [3]f32, maxv: [3]f32, min_exp: i32, max_bits: i32) i32 {
    return c.meshopt_computePositionExponent(&minv, &maxv, min_exp, max_bits);
}

test quantizeHalf {
    try std.testing.expectEqual(@as(f32, 0.5), dequantizeHalf(quantizeHalf(0.5)));
    try std.testing.expectEqual(@as(u16, 0x3c00), quantizeHalf(1.0));
    try std.testing.expectEqual(@as(u16, 0x7c00), quantizeHalf(100000.0));
    const nearly = dequantizeHalf(quantizeHalf(0.1));
    try std.testing.expectApproxEqRel(@as(f32, 0.1), nearly, 5e-4);
}

test quantizeFloat {
    try std.testing.expectEqual(@as(f32, 1.0), quantizeFloat(1.0, 10));
    // 4 mantissa bits cannot hold 1/3 exactly but stay within 2^-5 relative.
    const rounded = quantizeFloat(1.0 / 3.0, 4);
    try std.testing.expect(rounded != 1.0 / 3.0);
    try std.testing.expectApproxEqRel(1.0 / 3.0, rounded, 1.0 / 32.0);
    try std.testing.expect(std.math.isInf(quantizeFloat(std.math.inf(f32), 10)));
}

test quantizeUnorm {
    try std.testing.expectEqual(@as(i32, 0), quantizeUnorm(0.0, 8));
    try std.testing.expectEqual(@as(i32, 255), quantizeUnorm(1.0, 8));
    try std.testing.expectEqual(@as(i32, 128), quantizeUnorm(0.5, 8));
    try std.testing.expectEqual(@as(i32, 0), quantizeUnorm(-2.0, 8));
    try std.testing.expectEqual(@as(i32, 1023), quantizeUnorm(7.0, 10));
    try std.testing.expectEqual(@as(i32, 1), quantizeUnorm(1.0, 1));
}

test quantizeSnorm {
    try std.testing.expectEqual(@as(i32, 0), quantizeSnorm(0.0, 8));
    try std.testing.expectEqual(@as(i32, 127), quantizeSnorm(1.0, 8));
    try std.testing.expectEqual(@as(i32, -127), quantizeSnorm(-1.0, 8));
    try std.testing.expectEqual(@as(i32, 64), quantizeSnorm(0.5, 8));
    try std.testing.expectEqual(@as(i32, -127), quantizeSnorm(-5.0, 8));
    try std.testing.expectEqual(@as(i32, 32767), quantizeSnorm(1.0, 16));
}

test computePositionExponent {
    // A [0,1] cube on a 24-bit grid: 1.0 = round(1 / 2^e) * 2^e needs
    // e <= 0; more precision (smaller e) until the 24 bits run out.
    const exponent = computePositionExponent(.{ 0, 0, 0 }, .{ 1, 1, 1 }, -100, 24);
    try std.testing.expect(exponent <= -20 and exponent >= -24);
    // min_exp floors the result.
    const floored = computePositionExponent(.{ 0, 0, 0 }, .{ 1, 1, 1 }, -8, 24);
    try std.testing.expectEqual(@as(i32, -8), floored);
}
