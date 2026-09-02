//! meshoptimizer C declarations: cache, fetch, overdraw and coverage
//! analyzers.
//!
//! Mirrors the analysis region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check. All four return
//! their statistics struct BY VALUE.

pub const VertexCacheStatistics = extern struct {
    vertices_transformed: u32,
    warps_executed: u32,
    /// Transformed vertices / triangle count; best case 0.5, worst case 3.0.
    acmr: f32,
    /// Transformed vertices / vertex count; optimum 1.0 (each vertex once).
    atvr: f32,
};

pub const VertexFetchStatistics = extern struct {
    bytes_fetched: u32,
    /// Fetched bytes / vertex buffer size; best case 1.0.
    overfetch: f32,
};

pub const OverdrawStatistics = extern struct {
    pixels_covered: u32,
    pixels_shaded: u32,
    /// Shaded pixels / covered pixels; best case 1.0.
    overdraw: f32,
};

pub const CoverageStatistics = extern struct {
    /// Ratio of viewport pixels covered, from each axis.
    coverage: [3]f32,
    /// Viewport size in mesh coordinates.
    extent: f32,
};

/// Vertex transform cache statistics under a simplified FIFO model. Results
/// may not match actual GPU performance.
pub extern fn meshopt_analyzeVertexCache(indices: [*]const u32, index_count: usize, vertex_count: usize, cache_size: u32, warp_size: u32, primgroup_size: u32) VertexCacheStatistics;

/// Vertex fetch statistics under a simplified direct-mapped cache model.
/// Results may not match actual GPU performance.
pub extern fn meshopt_analyzeVertexFetch(indices: [*]const u32, index_count: usize, vertex_count: usize, vertex_size: usize) VertexFetchStatistics;

/// Overdraw statistics from a software rasterizer. Results may not match
/// actual GPU performance.
pub extern fn meshopt_analyzeOverdraw(indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) OverdrawStatistics;

/// Coverage statistics (per-axis covered viewport ratio) from a software
/// rasterizer.
pub extern fn meshopt_analyzeCoverage(indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) CoverageStatistics;
