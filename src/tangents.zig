//! Idiomatic layer: tangent space generation.
//!
//! Slice-based wrapper over `src/c/tangents.zig`. EXPERIMENTAL upstream.

const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").tangents;
const contract = @import("contract.zig");

pub const TangentOptions = c.TangentOptions;

/// EXPERIMENTAL upstream: computes per-corner tangents — normalized xyz plus
/// orientation w (+/-1); bitangent = `cross(normal, tangent.xyz) * w`.
/// `result` holds one float4 per index; `indices == null` treats the input
/// as unindexed (same tangents, ~30% slower). `P`'s first 12 bytes are the
/// position float3, `N`'s the unit normal float3, `U`'s first 8 the UV
/// float2.
pub fn generateTangents(comptime P: type, comptime N: type, comptime U: type, result: [][4]f32, indices: ?[]const u32, positions: []const P, normals: []const N, uvs: []const U, options: TangentOptions) void {
    contract.checkVertex(P, 3);
    contract.checkVertex(N, 3);
    contract.checkVertex(U, 2);
    assert(normals.len == positions.len and uvs.len == positions.len);
    const index_count = if (indices) |ix| ix.len else positions.len;
    // tangentspace.cpp:383 asserts the count either way, so unindexed input
    // has to be whole triangles too.
    assert(index_count % 3 == 0);
    assert(result.len >= index_count);
    c.meshopt_generateTangents(
        @ptrCast(result.ptr),
        if (indices) |ix| ix.ptr else null,
        index_count,
        contract.floatPtr(P, positions),
        positions.len,
        @sizeOf(P),
        contract.floatPtr(N, normals),
        @sizeOf(N),
        contract.floatPtr(U, uvs),
        @sizeOf(U),
        options,
    );
}

test generateTangents {
    // A +Z-facing triangle with identity UVs: tangent is +X, w is +1.
    const positions = [_][3]f32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } };
    const normals = [_][3]f32{ .{ 0, 0, 1 }, .{ 0, 0, 1 }, .{ 0, 0, 1 } };
    const uvs = [_][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 } };
    const indices = [_]u32{ 0, 1, 2 };
    var tangents: [3][4]f32 = undefined;
    generateTangents([3]f32, [3]f32, [2]f32, &tangents, &indices, &positions, &normals, &uvs, .{});
    for (tangents) |t| {
        try std.testing.expectApproxEqAbs(@as(f32, 1), t[0], 1e-4);
        try std.testing.expectApproxEqAbs(@as(f32, 0), t[1], 1e-4);
        try std.testing.expectApproxEqAbs(@as(f32, 0), t[2], 1e-4);
        try std.testing.expectApproxEqAbs(@as(f32, 1), t[3], 1e-4);
    }

    // The unindexed path produces the same tangents.
    var unindexed: [3][4]f32 = undefined;
    generateTangents([3]f32, [3]f32, [2]f32, &unindexed, null, &positions, &normals, &uvs, .{});
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&tangents), std.mem.sliceAsBytes(&unindexed));
}
