//! meshoptimizer C declarations: mesh, point cloud and prune simplifiers.
//!
//! Mirrors the simplifier region of `libs/meshoptimizer/src/meshoptimizer.h`
//! exactly; listed in `src/c.zig` for the ABI cross-check.
//!
//! Upstream declares the option bits as anonymous enums taken as
//! `unsigned int`; here they are packed structs over u32, and
//! `src/abi_check.zig` proves each field sits on its upstream bit.

/// Simplification options (upstream `meshopt_Simplify*`, a bitmask).
pub const SimplifyOptions = packed struct(u32) {
    /// Upstream spells these as an ANONYMOUS enum, so there is no C type to
    /// pair with; `abi_check.zig` pairs each bit against the enumerator
    /// this prefix plus the PascalCased field name reconstructs.
    pub const upstream_prefix = "meshopt_Simplify";

    /// Do not move vertices on the topological border, for simplifying
    /// portions of a larger mesh (`meshopt_SimplifyLockBorder`).
    lock_border: bool = false,
    /// Input indices are a sparse subset of the mesh; error becomes relative
    /// to subset extents (`meshopt_SimplifySparse`).
    sparse: bool = false,
    /// Treat error limit and resulting error as absolute rather than relative
    /// to mesh extents (`meshopt_SimplifyErrorAbsolute`).
    error_absolute: bool = false,
    /// Remove disconnected parts of the mesh incrementally
    /// (`meshopt_SimplifyPrune`).
    prune: bool = false,
    /// More regular triangle sizes and shapes, at some cost to geometric and
    /// attribute quality (`meshopt_SimplifyRegularize`).
    regularize: bool = false,
    /// EXPERIMENTAL upstream: allow collapses across attribute
    /// discontinuities except at vertices tagged `.protect`
    /// (`meshopt_SimplifyPermissive`).
    permissive: bool = false,
    /// Lighter variant of `.regularize`, at a small quality cost
    /// (`meshopt_SimplifyRegularizeLight`).
    regularize_light: bool = false,
    _padding: u25 = 0,
};

/// Per-vertex flags for the `vertex_lock` arrays (upstream
/// `meshopt_SimplifyVertex_*`, a bitmask stored per vertex in a `u8`).
pub const SimplifyVertexFlags = packed struct(u8) {
    /// Upstream's enumerators here carry an underscore after the group name
    /// (`meshopt_SimplifyVertex_Lock`), so the prefix keeps it.
    pub const upstream_prefix = "meshopt_SimplifyVertex_";

    /// Do not move this vertex (`meshopt_SimplifyVertex_Lock`).
    lock: bool = false,
    /// Protect the attribute discontinuity at this vertex; requires the
    /// `.permissive` option (`meshopt_SimplifyVertex_Protect`).
    protect: bool = false,
    /// Make this vertex more likely to be preserved
    /// (`meshopt_SimplifyVertex_Priority`).
    priority: bool = false,
    _padding: u5 = 0,
};

/// Reduces triangle count while preserving appearance; returns the new index
/// count, written to `destination` (worst case `index_count` elements, NOT
/// `target_index_count`). May stop short on topology constraints or
/// `target_error` (relative to mesh extents unless `.error_absolute`).
/// `result_error` may be null.
pub extern fn meshopt_simplify(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, target_index_count: usize, target_error: f32, options: SimplifyOptions, result_error: ?*f32) usize;

/// `meshopt_simplify` with attribute values folded into the error metric.
/// `vertex_attributes` holds `attribute_count` floats per vertex
/// (`attribute_count` <= 32); `vertex_lock` may be null. Attributes with
/// zero weight are ignored.
pub extern fn meshopt_simplifyWithAttributes(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_attributes: ?[*]const f32, vertex_attributes_stride: usize, attribute_weights: ?[*]const f32, attribute_count: usize, vertex_lock: ?[*]const u8, target_index_count: usize, target_error: f32, options: SimplifyOptions, result_error: ?*f32) usize;

/// `meshopt_simplifyWithAttributes` variant that destructively updates
/// `indices`, `vertex_positions` and `vertex_attributes` in place for optimal
/// appearance; returns the new index count.
pub extern fn meshopt_simplifyWithUpdate(indices: [*]u32, index_count: usize, vertex_positions: [*]f32, vertex_count: usize, vertex_positions_stride: usize, vertex_attributes: ?[*]f32, vertex_attributes_stride: usize, attribute_weights: ?[*]const f32, attribute_count: usize, vertex_lock: ?[*]const u8, target_index_count: usize, target_error: f32, options: SimplifyOptions, result_error: ?*f32) usize;

/// Sloppy simplifier: does not preserve topology, sacrifices appearance for
/// speed. `vertex_lock` may be null; locked vertices must be flagged
/// consistently for all indices sharing a position. `target_error` in [0..1].
pub extern fn meshopt_simplifySloppy(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_lock: ?[*]const u8, target_index_count: usize, target_error: f32, result_error: ?*f32) usize;

/// Removes small isolated parts of the mesh; returns the new index count.
/// `target_error` in [0..1], relative to mesh extents.
pub extern fn meshopt_simplifyPrune(destination: [*]u32, indices: [*]const u32, index_count: usize, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, target_error: f32) usize;

/// Point cloud simplifier; returns the number of points kept, written to
/// `destination` (`target_vertex_count` elements). `vertex_colors` may be
/// null; `color_weight` 1.0 is a safe default.
pub extern fn meshopt_simplifyPoints(destination: [*]u32, vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize, vertex_colors: ?[*]const f32, vertex_colors_stride: usize, color_weight: f32, target_vertex_count: usize) usize;

/// The factor converting between absolute and relative simplifier error:
/// divide absolute error by it before passing `target_error`, multiply
/// `result_error` by it to get absolute error.
pub extern fn meshopt_simplifyScale(vertex_positions: [*]const f32, vertex_count: usize, vertex_positions_stride: usize) f32;
