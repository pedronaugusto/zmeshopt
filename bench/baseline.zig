//! The C twins of the bench rows, defined in bench/baseline.c.

const Meshlet = @import("zmeshopt").Meshlet;

pub extern fn zmeshopt_baseline_simplify(target_error: f32, destination: [*]u32, indices: [*]const u32, index_count: usize, positions: [*]const f32, vertex_count: usize, stride: usize, target_index_count: usize, times: u64) usize;
pub extern fn zmeshopt_baseline_simplify_shim(target_error: f32, destination: [*]u32, indices: [*]const u32, index_count: usize, positions: [*]const f32, vertex_count: usize, stride: usize, target_index_count: usize, times: u64) usize;
pub extern fn zmeshopt_baseline_build_meshlets(cone_weight: f32, meshlets: [*]Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, positions: [*]const f32, vertex_count: usize, stride: usize, max_vertices: usize, max_triangles: usize, times: u64) usize;
pub extern fn zmeshopt_baseline_build_meshlets_shim(cone_weight: f32, meshlets: [*]Meshlet, meshlet_vertices: [*]u32, meshlet_triangles: [*]u8, indices: [*]const u32, index_count: usize, positions: [*]const f32, vertex_count: usize, stride: usize, max_vertices: usize, max_triangles: usize, times: u64) usize;
pub extern fn zmeshopt_baseline_analyze_coverage(indices: [*]const u32, index_count: usize, positions: [*]const f32, vertex_count: usize, stride: usize, times: u64) f32;
pub extern fn zmeshopt_baseline_analyze_coverage_shim(indices: [*]const u32, index_count: usize, positions: [*]const f32, vertex_count: usize, stride: usize, times: u64) f32;
pub extern fn zmeshopt_baseline_optimize_vertex_cache(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_count: usize, times: u64) void;
pub extern fn zmeshopt_baseline_decode_index_buffer(destination: [*]u32, index_count: usize, buffer: [*]const u8, buffer_size: usize, times: u64) c_int;
pub extern fn zmeshopt_baseline_decode_vertex_buffer(destination: *anyopaque, vertex_count: usize, vertex_size: usize, buffer: [*]const u8, buffer_size: usize, times: u64) c_int;
