//! meshoptimizer C declarations: vertex decode filters.
//!
//! These post-process the output of `meshopt_decodeVertexBuffer` in place.
//! Mirrors the decode filter region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Decodes octahedral unit vectors (K-bit signed X/Y, Z stores 1.0) in place.
/// Components are 8- or 16-bit normalized integers; `stride` must be 4 or 8.
/// W is preserved as is.
pub extern fn meshopt_decodeFilterOct(buffer: *anyopaque, count: usize, stride: usize) void;

/// Decodes 3-component quaternion encoding (K-bit components plus a 2-bit
/// reconstructed-component index) in place. Components are 16-bit integers;
/// `stride` must be 8.
pub extern fn meshopt_decodeFilterQuat(buffer: *anyopaque, count: usize, stride: usize) void;

/// Decodes exponential floating-point encoding (8-bit exponent, 24-bit
/// mantissa, `2^E*M`) in place, each 32-bit component in isolation;
/// `stride` must be divisible by 4.
pub extern fn meshopt_decodeFilterExp(buffer: *anyopaque, count: usize, stride: usize) void;

/// Decodes YCoCg(+A) color encoding back to RGBA in place. Components are
/// 8- or 16-bit normalized integers; `stride` must be 4 or 8.
pub extern fn meshopt_decodeFilterColor(buffer: *anyopaque, count: usize, stride: usize) void;
