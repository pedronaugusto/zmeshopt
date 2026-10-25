//! Production source layers, lowest first. Every production source has one
//! place; test code is in no layer.
const gantry = @import("gantry");

pub const layers: []const gantry.rules.Layer = &.{
    .{ .name = "externs", .patterns = &.{"src/c/*.zig"} },
    .{ .name = "C surface", .patterns = &.{ "src/c.zig", "src/shim.zig" } },
    .{ .name = "contracts", .patterns = &.{"src/contract.zig"} },
    .{ .name = "idiomatic layer", .patterns = &.{
        "src/analyze.zig",
        "src/cache.zig",
        "src/clusterize.zig",
        "src/decode_filters.zig",
        "src/encode_filters.zig",
        "src/index_codec.zig",
        "src/memory.zig",
        "src/meshlet_codec.zig",
        "src/opacity.zig",
        "src/partition.zig",
        "src/quantize.zig",
        "src/remap.zig",
        "src/simplify.zig",
        "src/spatial.zig",
        "src/stripify.zig",
        "src/tangents.zig",
        "src/vertex_codec.zig",
    } },
    .{ .name = "bindings", .patterns = &.{"src/zmeshopt.zig"} },
};

pub const entries: []const []const u8 = &.{"src/zmeshopt.zig"};

pub const modules: []const gantry.NamedModule = &.{};

pub const references: []const gantry.rules.ReferenceRule = &.{
    .{ .name = "named dependencies", .unresolved_only = true, .except_targets = &.{
        "builtin",
        "meshoptimizer_h",
        "shakedown",
        "std",
        "zmeshopt_options",
    } },
    .{ .name = "source siblings", .suffix = ".zig", .relative = true, .except_targets = &.{"src/**"} },
};

pub const required = [_][]const u8{
    "src/c.zig",
    "src/shim.zig",
    "src/zmeshopt.zig",
    "src/testing/abi.zig",
};

/// Tokens only their owners may spell: the C boundary is declared in src/c/
/// and src/shim.zig alone, which the ABI check reads, and the header is
/// translated only for that check.
pub const owned: []const gantry.rules.TokenRule = &.{
    .{ .name = "the C boundary", .sequences = &.{&.{ "extern", "fn" }}, .owners = &.{ "src/c/**", "src/shim.zig", "src/testing/**" } },
    .{ .name = "the translated header", .kind = .string, .tokens = &.{"meshoptimizer_h"}, .owners = &.{ "src/testing/abi.zig", "build.zig", "ci/layers.zig" } },
};
