//! meshoptimizer C declarations: scalar quantization.
//!
//! Mirrors the quantization region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.
//!
//! Upstream also ships `meshopt_quantizeUnorm`/`meshopt_quantizeSnorm`, but
//! only as inline C++ functions — no symbol exists for a binding to call.
//! The root module reimplements them in Zig (see `src/quantize.zig`), which
//! the coverage ledger records as its `ZIG` verdicts.

/// Quantizes a float to IEEE-754 fp16: +-inf on overflow, NaN preserved,
/// denormals flushed to zero, round to nearest. Representable magnitude
/// range [6e-5, 65504]; max relative reconstruction error 5e-4.
pub extern fn meshopt_quantizeHalf(v: f32) u16;

/// Quantizes a float to `N` significant mantissa bits (`N` in 1..23),
/// staying in fp32 binary representation. Inf/NaN preserved, denormals
/// flushed to zero, round to nearest.
pub extern fn meshopt_quantizeFloat(v: f32, N: c_int) f32;

/// Reverses fp16 quantization; Inf/NaN preserved, denormals flushed to zero.
pub extern fn meshopt_dequantizeHalf(h: u16) f32;

/// EXPERIMENTAL upstream: shared exponent for quantizing any position inside
/// `[minv, maxv]` (each a float3) onto a 24-bit integer grid:
/// `iv = int(round(v / pow(2, exponent)))`. `min_exp` floors the returned
/// exponent to limit precision; `max_bits` caps the quantized range.
pub extern fn meshopt_computePositionExponent(minv: [*]const f32, maxv: [*]const f32, min_exp: c_int, max_bits: c_int) c_int;
