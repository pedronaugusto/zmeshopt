//! meshoptimizer C declarations: vertex encode filters.
//!
//! These produce data the decode filters can decode. Mirrors the encode
//! filter region of `libs/meshoptimizer/src/meshoptimizer.h` exactly; listed
//! in `src/c.zig` for the ABI cross-check.

/// Exponent-sharing mode for `meshopt_encodeFilterExp`.
pub const EncodeExpMode = enum(c_uint) {
    /// Upstream enumerators are `meshopt_EncodeExpSeparate` etc.;
    /// `abi_check.zig` pairs each value against this prefix plus the
    /// PascalCased field name.
    pub const upstream_prefix = "meshopt_EncodeExp";

    /// Separate exponent per component (maximum quality).
    separate = 0,
    /// Shared exponent for all components of each vector (better compression).
    shared_vector = 1,
    /// Shared exponent for each component across all vectors (best compression).
    shared_component = 2,
    /// Separate per component, clamped to >= 0 (good quality when very small
    /// values do not matter).
    clamped = 3,
};

/// Encodes unit vectors octahedrally with K-bit signed X/Y
/// (2 <= `bits` <= 16). `stride` must be 4 (K <= 8) or 8 (K <= 16); input is
/// 4 floats per vector (`count * 4` total). Z will store 1.0, W is preserved.
pub extern fn meshopt_encodeFilterOct(destination: *anyopaque, count: usize, stride: usize, bits: c_int, data: [*]const f32) void;

/// Encodes unit quaternions with K-bit components (4 <= `bits` <= 16).
/// `stride` must be 8; input is 4 floats per quaternion (`count * 4` total).
pub extern fn meshopt_encodeFilterQuat(destination: *anyopaque, count: usize, stride: usize, bits: c_int, data: [*]const f32) void;

/// Encodes finite floats with an 8-bit exponent and K-bit mantissa
/// (1 <= `bits` <= 24); exponent sharing per `mode`. `stride` must be
/// divisible by 4 and <= 256; input is `stride/4` floats per vector.
pub extern fn meshopt_encodeFilterExp(destination: *anyopaque, count: usize, stride: usize, bits: c_int, data: [*]const f32, mode: EncodeExpMode) void;

/// Encodes RGBA colors via YCoCg with K-bit components (2 <= `bits` <= 16;
/// A uses K-1 bits). `stride` must be 4 (K <= 8) or 8 (K <= 16); input is
/// 4 floats per color (`count * 4` total).
pub extern fn meshopt_encodeFilterColor(destination: *anyopaque, count: usize, stride: usize, bits: c_int, data: [*]const f32) void;
