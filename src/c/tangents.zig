//! meshoptimizer C declarations: tangent space generation.
//!
//! Mirrors the tangent region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.
//!
//! Upstream declares the option bits as an anonymous enum taken as
//! `unsigned int`; here they are a packed struct over u32, and
//! `src/abi_check.zig` proves each field sits on its upstream bit.

/// Tangent generation options (upstream `meshopt_Tangent*`, a bitmask).
pub const TangentOptions = packed struct(u32) {
    /// Upstream spells these as an ANONYMOUS enum; `abi_check.zig` pairs each
    /// bit against this prefix plus the PascalCased field name.
    pub const upstream_prefix = "meshopt_Tangent";

    /// MikkTSpace-compatible weighting and fallbacks, at reduced quality; not
    /// recommended unless normal maps are baked (`meshopt_TangentCompatible`).
    compatible: bool = false,
    /// EXPERIMENTAL upstream: zero tangents (instead of an arbitrary
    /// fallback) for vertices only connected to degenerate triangles
    /// (`meshopt_TangentZeroFallback`).
    zero_fallback: bool = false,
    _padding: u30 = 0,
};

/// EXPERIMENTAL upstream: computes per-corner tangents — normalized xyz plus
/// orientation w (+/-1); bitangent = `cross(normal, tangent.xyz) * w`.
/// `result` must hold `index_count * 4` floats; `indices` may be null for
/// unindexed input (same tangents, ~30% slower). Normals must be unit
/// float3; UVs float2.
pub extern fn meshopt_generateTangents(result: [*]f32, indices: ?[*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_normals: [*]const f32, vertex_normals_stride: usize, vertex_uvs: [*]const f32, vertex_uvs_stride: usize, options: TangentOptions) void;
