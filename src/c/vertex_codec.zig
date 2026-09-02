//! meshoptimizer C declarations: vertex buffer codec.
//!
//! Mirrors the vertex codec region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Encodes a vertex buffer; returns the encoded size, or 0 if `buffer` is too
/// small (size it with `meshopt_encodeVertexBufferBound`). All `vertex_size`
/// bytes of each vertex are encoded verbatim, padding included, so padding
/// should be zero-initialized. `vertex_size` must be a multiple of 4, <= 256.
pub extern fn meshopt_encodeVertexBuffer(buffer: [*]u8, buffer_size: usize, vertices: *const anyopaque, vertex_count: usize, vertex_size: usize) usize;

/// Worst-case encoded size for `meshopt_encodeVertexBuffer`.
pub extern fn meshopt_encodeVertexBufferBound(vertex_count: usize, vertex_size: usize) usize;

/// `meshopt_encodeVertexBuffer` with an explicit compression `level`
/// ([0, 3]; the plain function implies 2) and `version` (-1 for the default
/// set via `meshopt_encodeVertexVersion`, or 0/1 to override; level only
/// takes effect with version 1).
pub extern fn meshopt_encodeVertexBufferLevel(buffer: [*]u8, buffer_size: usize, vertices: *const anyopaque, vertex_count: usize, vertex_size: usize, level: c_int, version: c_int) usize;

/// Sets the vertex encoder format version (0 or 1; defaults to 1, decodable
/// by 0.23+). NOT thread safe: must not run concurrently with vertex encoding.
pub extern fn meshopt_encodeVertexVersion(version: c_int) void;

/// Decodes an encoded vertex buffer; returns 0 on success, an error code
/// otherwise. Safe on untrusted input, but may produce garbage data.
/// `vertex_size` must be a multiple of 4, <= 256.
pub extern fn meshopt_decodeVertexBuffer(destination: *anyopaque, vertex_count: usize, vertex_size: usize, buffer: [*]const u8, buffer_size: usize) c_int;

/// Returns the format version of an encoded vertex buffer, or -1 if the
/// header is invalid. Non-negative does not guarantee decodability.
pub extern fn meshopt_decodeVertexVersion(buffer: [*]const u8, buffer_size: usize) c_int;
