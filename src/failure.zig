//! What a refusal leaves on the caller's `Failure`: the call that refused
//! and why. Every call that can refuse takes a `*Failure` last, since the
//! error alone says neither which call refused nor, for a decoder, which of
//! header, length or end upstream refused.

const std = @import("std");
const aegis = @import("aegis");
const check = @import("check.zig");

/// The call a refusal names: upstream's entry point without `meshopt_`, in
/// snake case.
pub const Call = enum {
    analyze_coverage,
    analyze_overdraw,
    analyze_vertex_fetch,
    analyze_vertex_cache,
    build_meshlets,
    build_meshlets_bound,
    build_meshlets_flex,
    build_meshlets_scan,
    build_meshlets_spatial,
    compute_cluster_bounds,
    compute_meshlet_bounds,
    compute_sphere_bounds,
    decode_index_buffer,
    decode_index_sequence,
    decode_meshlet,
    decode_meshlet_raw,
    decode_vertex_buffer,
    encode_filter_color,
    encode_filter_exp,
    encode_filter_oct,
    encode_filter_quat,
    encode_index_buffer,
    encode_index_buffer_bound,
    encode_index_sequence,
    encode_meshlet,
    encode_vertex_buffer,
    encode_vertex_buffer_level,
    extract_meshlet_indices,
    filter_index_buffer,
    filter_index_buffer_multi,
    generate_adjacency_index_buffer,
    generate_position_remap,
    generate_provoking_index_buffer,
    generate_shadow_index_buffer,
    generate_shadow_index_buffer_multi,
    generate_tangents,
    generate_tessellation_index_buffer,
    generate_vertex_remap,
    generate_vertex_remap_custom,
    generate_vertex_remap_multi,
    opacity_map_compact,
    opacity_map_measure,
    opacity_map_rasterize,
    optimize_meshlet,
    optimize_meshlet_level,
    optimize_overdraw,
    optimize_vertex_cache,
    optimize_vertex_cache_fifo,
    optimize_vertex_cache_strip,
    optimize_vertex_fetch,
    optimize_vertex_fetch_remap,
    partition_clusters,
    partition_clusters_by_sharing,
    remap_index_buffer,
    remap_vertex_buffer,
    simplify,
    simplify_prune,
    simplify_sloppy,
    simplify_with_attributes,
    simplify_with_update,
    spatial_cluster_points,
    spatial_sort_remap,
    spatial_sort_triangles,
    stripify,
    stripify_bound,
    unstripify,
};

/// Why the call refused. The last three are upstream's decoder results
/// (`indexcodec.cpp:386-394`, `vertexcodec.cpp:1828-1869`,
/// `meshletcodec.cpp:366-373`); the rest are refused before upstream runs.
pub const Reason = enum {
    not_triangles,
    buffer_too_small,
    length_mismatch,
    out_of_range,
    /// Upstream's -1: a header that is not this codec's, or a version newer
    /// than this decoder reads.
    header,
    /// Upstream's -2: the bytes end before the encoding does.
    truncated,
    /// Upstream's -3: the encoding does not end where the bytes do.
    mismatched_end,
    /// An index at or past the count of what it indexes; `at` is its
    /// position. Upstream reads or writes there and only asserts.
    index_out_of_range,
};

/// One refusal.
pub const Frame = struct {
    pub const aegis_public_frame = true;
    call: Call,
    reason: Reason,
    /// For `index_out_of_range`, the position of the first index past the
    /// count; 0 for every other reason.
    at: u64 = 0,
};

/// What refused, oldest first. A call that refuses pushes one frame; four
/// are kept, and a fifth sets `truncated`.
pub const Failure = aegis.err.Context(Frame, 4);

/// Encoded bytes from outside the program, which every decoder takes.
pub const Encoded = aegis.input.Untrusted([]const u8);

/// Every refusal: the boundary's checks, and encoded bytes upstream would
/// not decode.
pub const Error = check.Error || error{
    /// Encoded bytes upstream refused to decode; the frame says why.
    Malformed,
};

/// `result`'s value, or its refusal with a frame naming `call` and the check.
pub fn held(failure: *Failure, call: Call, result: anytype) check.Error!@typeInfo(@TypeOf(result)).error_union.payload {
    return result catch |e| return refuse(failure, call, e);
}

/// A boundary refusal: a frame naming `call` and the check, and the error.
pub fn refuse(failure: *Failure, call: Call, e: check.Error) check.Error {
    failure.push(.{ .call = call, .reason = switch (e) {
        error.NotTriangles => .not_triangles,
        error.BufferTooSmall => .buffer_too_small,
        error.LengthMismatch => .length_mismatch,
        error.OutOfRange => .out_of_range,
    } });
    return e;
}

/// Refuses `indices` unless each is below `count`, with a frame naming
/// `call` and the first that is not.
pub fn bounded(failure: *Failure, call: Call, indices: anytype, count: usize) error{OutOfRange}!void {
    const at = check.firstPast(indices, count) orelse return;
    failure.push(.{ .call = call, .reason = .index_out_of_range, .at = at });
    return error.OutOfRange;
}

/// `bounded` for a remap table, whose unused entries (`~0`) map nowhere.
pub fn boundedRemap(failure: *Failure, call: Call, remap: []const u32, count: usize) error{OutOfRange}!void {
    const at = check.firstRemapPast(remap, count) orelse return;
    failure.push(.{ .call = call, .reason = .index_out_of_range, .at = at });
    return error.OutOfRange;
}

/// Nothing for upstream's 0; otherwise a frame naming `call` and the code,
/// and `error.Malformed`.
pub fn decoded(failure: *Failure, call: Call, result: c_int) error{Malformed}!void {
    const reason: Reason = switch (result) {
        0 => return,
        -1 => .header,
        -2 => .truncated,
        -3 => .mismatched_end,
        else => aegis.assert.never("upstream's decoders return 0, -1, -2 or -3"),
    };
    failure.push(.{ .call = call, .reason = reason });
    return error.Malformed;
}

test decoded {
    var failure: Failure = .{};
    try decoded(&failure, .decode_vertex_buffer, 0);
    try std.testing.expectEqual(@as(usize, 0), failure.frames().len);
    try std.testing.expectError(error.Malformed, decoded(&failure, .decode_vertex_buffer, -2));
    try std.testing.expectEqual(Frame{ .call = .decode_vertex_buffer, .reason = .truncated }, failure.frames()[0]);
}

test held {
    var failure: Failure = .{};
    try std.testing.expectError(error.NotTriangles, held(&failure, .decode_index_buffer, check.triangles(4)));
    try std.testing.expectEqual(Frame{ .call = .decode_index_buffer, .reason = .not_triangles }, failure.frames()[0]);
}

/// `generateVertexRemap` -> `generate_vertex_remap`, as `Call` spells it.
fn callName(fn_name: []const u8, buf: []u8) []const u8 {
    var len: usize = 0;
    for (fn_name) |ch| {
        if (std.ascii.isUpper(ch)) {
            buf[len] = '_';
            len += 1;
        }
        buf[len] = std.ascii.toLower(ch);
        len += 1;
    }
    return buf[0..len];
}

/// Every module that refuses, read as it is compiled.
const sources = [_][]const u8{
    @embedFile("analyze.zig"),        @embedFile("cache.zig"),          @embedFile("clusterize.zig"),
    @embedFile("decode_filters.zig"), @embedFile("encode_filters.zig"), @embedFile("index_codec.zig"),
    @embedFile("memory.zig"),         @embedFile("meshlet_codec.zig"),  @embedFile("opacity.zig"),
    @embedFile("partition.zig"),      @embedFile("quantize.zig"),       @embedFile("remap.zig"),
    @embedFile("simplify.zig"),       @embedFile("spatial.zig"),        @embedFile("stripify.zig"),
    @embedFile("tangents.zig"),       @embedFile("vertex_codec.zig"),   @embedFile("zmeshopt.zig"),
};

test "every frame a call pushes names that call" {
    // Inside `pub fn x`, every function that pushes must name `.x` as
    // `Call` spells it, so a frame can never name a call other than the one
    // that refused. The compiler proves the name exists.
    var checked: usize = 0;
    for (sources) |source| {
        var function: []const u8 = "";
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "pub fn ") or std.mem.startsWith(u8, line, "fn ")) {
                const name = line[std.mem.findScalar(u8, line, ' ').? + 1 ..];
                function = if (std.mem.startsWith(u8, line, "pub fn ")) name["fn ".len..std.mem.findScalar(u8, name, '(').?] else "";
            }
            inline for (.{ "held", "refuse", "decoded", "bounded", "boundedRemap" }) |pusher| {
                const marker = "failure_." ++ pusher ++ "(failure, .";
                var rest: []const u8 = line;
                while (std.mem.find(u8, rest, marker)) |at| {
                    rest = rest[at + marker.len ..];
                    const named = rest[0..std.mem.findScalar(u8, rest, ',').?];
                    // A private helper pushes no frame; its public caller does.
                    try std.testing.expect(function.len != 0);
                    var buf: [64]u8 = undefined;
                    try std.testing.expectEqualStrings(callName(function, &buf), named);
                    checked += 1;
                }
            }
        }
    }
    try std.testing.expect(checked > 100);
}

test "no module refuses without a frame" {
    // A refusal is made by `held`, `refuse` or `decoded`, which push the
    // frame; only `check.zig`'s checks return the bare error they wrap. One
    // returned any other way would reach the caller with nothing on its
    // `Failure`.
    inline for (@typeInfo(Error).error_set.error_names.?) |error_name| {
        inline for (.{ "return ", "catch ", "orelse " }) |verb| {
            inline for (.{ "error.", "Error." }) |spelling| {
                for (sources) |source| {
                    try std.testing.expect(std.mem.find(u8, source, verb ++ spelling ++ error_name) == null);
                }
            }
        }
    }
    for (sources) |source| {
        // A module never makes a `Failure` of its own outside a test, since
        // no caller would see its frames.
        var in_test = false;
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "test ")) in_test = true;
            if (std.mem.startsWith(u8, line, "fn ") or std.mem.startsWith(u8, line, "pub fn ")) in_test = false;
            if (std.mem.find(u8, line, "Failure = .{}") != null) try std.testing.expect(in_test);
        }
    }
}

test bounded {
    var failure: Failure = .{};
    try bounded(&failure, .optimize_vertex_cache, @as([]const u32, &.{ 0, 1, 2 }), 3);
    try std.testing.expectError(error.OutOfRange, bounded(&failure, .optimize_vertex_cache, @as([]const u32, &.{ 0, 1, 2, 2, 1, 3 }), 3));
    try std.testing.expectEqualSlices(Frame, &.{.{ .call = .optimize_vertex_cache, .reason = .index_out_of_range, .at = 5 }}, failure.frames());
}
