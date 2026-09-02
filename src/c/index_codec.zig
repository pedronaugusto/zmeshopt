//! meshoptimizer C declarations: index buffer and index sequence codec.
//!
//! Mirrors the index codec region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.

/// Encodes a triangle-list index buffer (<1.5 bytes/triangle typical);
/// returns the encoded size, or 0 if `buffer` is too small
/// (size it with `meshopt_encodeIndexBufferBound`).
pub extern fn meshopt_encodeIndexBuffer(buffer: [*]u8, buffer_size: usize, indices: [*]const u32, index_count: usize) usize;

/// Worst-case encoded size for `meshopt_encodeIndexBuffer`.
pub extern fn meshopt_encodeIndexBufferBound(index_count: usize, vertex_count: usize) usize;

/// Sets the index encoder format version (0 or 1; defaults to 1, decodable
/// by 0.14+). NOT thread safe: must not run concurrently with index encoding.
pub extern fn meshopt_encodeIndexVersion(version: c_int) void;

/// Decodes an encoded index buffer; returns 0 on success, an error code
/// otherwise. Safe on untrusted input, but may produce garbage indices.
/// `index_size` selects the output index width in bytes.
pub extern fn meshopt_decodeIndexBuffer(destination: *anyopaque, index_count: usize, index_size: usize, buffer: [*]const u8, buffer_size: usize) c_int;

/// Returns the format version of an encoded index buffer/sequence, or -1 if
/// the header is invalid. Non-negative does not guarantee decodability.
pub extern fn meshopt_decodeIndexVersion(buffer: [*]const u8, buffer_size: usize) c_int;

/// Encodes an index sequence (arbitrary topology; for triangle lists prefer
/// `meshopt_encodeIndexBuffer`); returns the encoded size, or 0 if `buffer`
/// is too small (size it with `meshopt_encodeIndexSequenceBound`).
pub extern fn meshopt_encodeIndexSequence(buffer: [*]u8, buffer_size: usize, indices: [*]const u32, index_count: usize) usize;

/// Worst-case encoded size for `meshopt_encodeIndexSequence`.
pub extern fn meshopt_encodeIndexSequenceBound(index_count: usize, vertex_count: usize) usize;

/// Decodes an encoded index sequence; returns 0 on success, an error code
/// otherwise. Safe on untrusted input, but may produce garbage indices.
pub extern fn meshopt_decodeIndexSequence(destination: *anyopaque, index_count: usize, index_size: usize, buffer: [*]const u8, buffer_size: usize) c_int;
