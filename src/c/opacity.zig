//! meshoptimizer C declarations: opacity micromap generation.
//!
//! ALL FOUR functions are EXPERIMENTAL upstream. Mirrors the opacity micromap
//! region of `libs/meshoptimizer/src/meshoptimizer.h` exactly; listed in
//! `src/c.zig` for the ABI cross-check.

/// EXPERIMENTAL upstream: computes a subdivision level per triangle and
/// deduplicates triangles referencing the same UVs; returns the OMM entry
/// count. `levels`/`sources` need `index_count/3` elements worst case;
/// `omm_indices` needs `index_count/3`. `max_level` in [0..12];
/// `target_edge > 0` makes subdivision adaptive targeting `target_edge^2`
/// texel area.
pub extern fn meshopt_opacityMapMeasure(levels: [*]u8, sources: [*]u32, omm_indices: [*]c_int, indices: [*]const u32, index_count: usize, vertex_uvs: [*]const f32, vertex_count: usize, vertex_uvs_stride: usize, texture_width: u32, texture_height: u32, max_level: c_int, target_edge: f32) usize;

/// EXPERIMENTAL upstream: rasterizes opacity for one triangle entry by
/// sampling the alpha texture (bilinear, 0.5 cutoff). Size `result` with
/// `meshopt_opacityMapEntrySize`; `states` is 2 (opaque/transparent) or 4
/// (adds unknown); `texture_data` points at the first pixel's UNORM8 alpha.
pub extern fn meshopt_opacityMapRasterize(result: [*]u8, level: c_int, states: c_int, uv0: [*]const f32, uv1: [*]const f32, uv2: [*]const f32, texture_data: [*]const u8, texture_stride: usize, texture_pitch: usize, texture_width: u32, texture_height: u32) void;

/// EXPERIMENTAL upstream: bytes one OMM entry occupies at `level`/`states`.
pub extern fn meshopt_opacityMapEntrySize(level: c_int, states: c_int) usize;

/// EXPERIMENTAL upstream: compacts and deduplicates opacity data, merging
/// identical entries and substituting special indices (-4..-1) where
/// possible; returns the post-compaction entry count. `levels`, `offsets`
/// and `omm_indices` are updated in place; trim `data` using the last
/// offset/size.
pub extern fn meshopt_opacityMapCompact(data: [*]u8, data_size: usize, levels: [*]u8, offsets: [*]u32, omm_count: usize, omm_indices: [*]c_int, triangle_count: usize, states: c_int) usize;
