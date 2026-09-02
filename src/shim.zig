//! Externs for `src/abi_shim.c` — the caller-shape forwarders.
//!
//! Zig 0.16.0 was measured (CI, 2026-09-02) miscompiling two caller shapes
//! upstream's ABI requires: an f32 argument after more than 6 integer-class
//! arguments (the self-hosted x86-64 backend on linux), and an all-float
//! 16-byte struct return (both measured backends, on every measured ABI
//! that returns it in registers). Each forwarder re-spells one affected
//! function with its floats FIRST or its struct return as an out-parameter,
//! and the idiomatic layer calls these on every backend — one path, tested
//! everywhere.
//!
//! `src/abi_check.zig` holds these declarations to `src/abi_shim.h`; the
//! canaries in `src/abi_canary_test.zig` prove the crossing bit-exact
//! and fail loudly when a fixed backend makes the shim retirable.

const simplify = @import("c/simplify.zig");
const clusterize = @import("c/clusterize.zig");
const analyze = @import("c/analyze.zig");

pub extern fn zmeshopt_shim_simplify(target_error: f32, destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, target_index_count: usize, options: simplify.SimplifyOptions, result_error: ?*f32) usize;
pub extern fn zmeshopt_shim_simplifyWithAttributes(target_error: f32, destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_attributes: ?[*]const f32, vertex_attributes_stride: usize, attribute_weights: ?[*]const f32, attribute_count: usize, vertex_lock: ?[*]const u8, target_index_count: usize, options: simplify.SimplifyOptions, result_error: ?*f32) usize;
pub extern fn zmeshopt_shim_simplifyWithUpdate(target_error: f32, indices: [*]u32, index_count: usize, vertex_positions: [*]f32, vertex_count: usize, vertex_positions_stride: usize, vertex_attributes: ?[*]f32, vertex_attributes_stride: usize, attribute_weights: ?[*]const f32, attribute_count: usize, vertex_lock: ?[*]const u8, target_index_count: usize, options: simplify.SimplifyOptions, result_error: ?*f32) usize;
pub extern fn zmeshopt_shim_simplifySloppy(target_error: f32, destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_lock: ?[*]const u8, target_index_count: usize, result_error: ?*f32) usize;
pub extern fn zmeshopt_shim_buildMeshlets(cone_weight: f32, meshlets: [*]clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, max_triangles: usize) usize;
pub extern fn zmeshopt_shim_buildMeshletsFlex(cone_weight: f32, split_factor: f32, meshlets: [*]clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize) usize;
pub extern fn zmeshopt_shim_buildMeshletsSpatial(fill_weight: f32, meshlets: [*]clusterize.Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, max_vertices: usize, min_triangles: usize, max_triangles: usize) usize;
pub extern fn zmeshopt_shim_opacityMapMeasure(target_edge: f32, levels: [*]u8, sources: [*]u32, omm_indices: [*]c_int, indices: [*]const u32, index_count: usize, vertex_uvs: [*]const f32, vertex_count: usize, vertex_uvs_stride: usize, texture_width: u32, texture_height: u32, max_level: c_int) usize;
pub extern fn zmeshopt_shim_analyzeCoverage(out: *analyze.CoverageStatistics, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) void;
