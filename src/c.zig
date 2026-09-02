//! The C declaration modules, and the list the guards walk.
//!
//! The split follows the header's own regions: one module per functional
//! group of `libs/meshoptimizer/src/meshoptimizer.h`, in header order. That
//! rule is mechanical, so a new declaration has exactly one home and nobody
//! has to argue about it.
//!
//! `modules` is the point of keeping this file at all: `abi_check.zig`
//! discovers what to check by walking it, so a module added here is swept
//! automatically, and a module not added here is a module the guard does not
//! cover — which its coverage floors turn into a build failure.

pub const remap = @import("c/remap.zig");
pub const cache = @import("c/cache.zig");
pub const index_codec = @import("c/index_codec.zig");
pub const meshlet_codec = @import("c/meshlet_codec.zig");
pub const vertex_codec = @import("c/vertex_codec.zig");
pub const decode_filters = @import("c/decode_filters.zig");
pub const encode_filters = @import("c/encode_filters.zig");
pub const simplify = @import("c/simplify.zig");
pub const stripify = @import("c/stripify.zig");
pub const analyze = @import("c/analyze.zig");
pub const clusterize = @import("c/clusterize.zig");
pub const partition = @import("c/partition.zig");
pub const spatial = @import("c/spatial.zig");
pub const opacity = @import("c/opacity.zig");
pub const tangents = @import("c/tangents.zig");
pub const quantize = @import("c/quantize.zig");
pub const allocator = @import("c/allocator.zig");

/// Every module above, in header order. Walked by `abi_check.zig`.
pub const modules = .{
    remap,
    cache,
    index_codec,
    meshlet_codec,
    vertex_codec,
    decode_filters,
    encode_filters,
    simplify,
    stripify,
    analyze,
    clusterize,
    partition,
    spatial,
    opacity,
    tangents,
    quantize,
    allocator,
};
