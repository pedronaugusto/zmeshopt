//! meshoptimizer C declarations: meshlet codec.
//!
//! Mirrors the meshlet codec region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Encodes ONE meshlet's vertex references and triangles; returns the encoded
/// size, or 0 if `buffer` is too small (size it with
/// `meshopt_encodeMeshletBound`). `vertices` may be null with
/// `vertex_count == 0` to encode triangle data only. `vertex_count` and
/// `triangle_count` must be <= 256. For best results optimize the meshlet
/// with `meshopt_optimizeMeshletLevel` (level 3 recommended) first.
pub extern fn meshopt_encodeMeshlet(buffer: [*]u8, buffer_size: usize, vertices: ?[*]const u32, vertex_count: usize, triangles: [*]const u8, triangle_count: usize) usize;

/// Worst-case encoded size for `meshopt_encodeMeshlet`.
pub extern fn meshopt_encodeMeshletBound(max_vertices: usize, max_triangles: usize) usize;

/// Decodes one encoded meshlet; returns 0 on success, an error code
/// otherwise. Safe on untrusted input, but may produce garbage data.
/// `vertex_size` must be 2 or 4; `triangle_size` must be 3 (8-bit indices) or
/// 4 (packed `a | b<<8 | c<<16`); both outputs must be 4-byte aligned, with
/// space rounded up to 4 bytes. Counts and `buffer_size` must match the
/// encoding exactly. `vertices` may be null with `vertex_count == 0`.
pub extern fn meshopt_decodeMeshlet(vertices: ?*anyopaque, vertex_count: usize, vertex_size: usize, triangles: *anyopaque, triangle_count: usize, triangle_size: usize, buffer: [*]const u8, buffer_size: usize) c_int;

/// Raw-mode meshlet decode into 32-bit outputs; both outputs should have
/// space aligned (and padded) to 16 bytes for SIMD decoding. Returns 0 on
/// success. `vertices` may be null with `vertex_count == 0`.
pub extern fn meshopt_decodeMeshletRaw(vertices: ?[*]u32, vertex_count: usize, triangles: [*]u32, triangle_count: usize, buffer: [*]const u8, buffer_size: usize) c_int;
