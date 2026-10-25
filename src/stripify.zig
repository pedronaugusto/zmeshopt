//! Idiomatic layer: triangle strip conversion.
//!
//! Slice-based wrappers over `src/c/stripify.zig`.

const std = @import("std");
const check = @import("check.zig");
const failure_ = @import("failure.zig");
const c = @import("c.zig").stripify;

/// Converts a (vertex-cache-optimized) triangle list to a strip, stitching
/// with `restart_index` (0xffff / 0xffffffff) or, when it is 0, degenerate
/// triangles; returns the written prefix. Size `destination` with
/// `stripifyBound`.
pub fn stripify(destination: []u32, indices: []const u32, vertex_count: usize, restart_index: u32, failure: *failure_.Failure) failure_.Error![]u32 {
    try failure_.held(failure, .stripify, check.triangles(indices.len));
    try failure_.held(failure, .stripify, check.room(destination.len, try stripifyBound(indices.len, failure)));
    try failure_.bounded(failure, .stripify, indices, vertex_count);
    const n = c.meshopt_stripify(destination.ptr, indices.ptr, indices.len, vertex_count, restart_index);
    return destination[0..n];
}

/// Worst-case output size for `stripify`.
pub fn stripifyBound(index_count: usize, failure: *failure_.Failure) failure_.Error!usize {
    try failure_.held(failure, .stripify_bound, check.triangles(index_count));
    return c.meshopt_stripifyBound(index_count);
}

/// Converts a triangle strip back to a triangle list; returns the written
/// prefix. Size `destination` with `unstripifyBound`.
pub fn unstripify(destination: []u32, indices: []const u32, restart_index: u32, failure: *failure_.Failure) failure_.Error![]u32 {
    try failure_.held(failure, .unstripify, check.room(destination.len, unstripifyBound(indices.len)));
    const n = c.meshopt_unstripify(destination.ptr, indices.ptr, indices.len, restart_index);
    return destination[0..n];
}

/// Worst-case output size for `unstripify`.
pub fn unstripifyBound(index_count: usize) usize {
    return c.meshopt_unstripifyBound(index_count);
}

test stripify {
    var failure: failure_.Failure = .{};
    const indices = [_]u32{ 0, 1, 2, 2, 1, 3, 2, 3, 4 };
    var strip_buffer: [64]u32 = undefined;
    const strip = try stripify(&strip_buffer, &indices, 5, 0xffffffff, &failure);
    try std.testing.expect(strip.len >= 5);

    var list_buffer: [64]u32 = undefined;
    const list = try unstripify(&list_buffer, strip, 0xffffffff, &failure);
    try std.testing.expectEqual(indices.len, list.len);
    // The round trip preserves the triangle SET (winding-normalized), not
    // necessarily the order.
    var found: usize = 0;
    var i: usize = 0;
    while (i < indices.len) : (i += 3) {
        var j: usize = 0;
        while (j < list.len) : (j += 3) {
            const a = [3]u32{ indices[i], indices[i + 1], indices[i + 2] };
            for (0..3) |r| {
                const b = [3]u32{ list[j + r], list[j + (r + 1) % 3], list[j + (r + 2) % 3] };
                if (std.mem.eql(u32, &a, &b)) {
                    found += 1;
                    break;
                }
            } else continue;
            break;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), found);
}
