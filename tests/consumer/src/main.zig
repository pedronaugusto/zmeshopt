//! A downstream consumer of the `zmeshopt` Zig module.
//!
//! What is under test: a consumer can reach the module through
//! `b.dependency` at all, the pipeline actually runs from out here, and the
//! build options zmeshopt was compiled with are visible downstream.
const std = @import("std");
const zmeshopt = @import("zmeshopt");

pub fn main() !void {
    // A quad with one duplicate corner vertex, as a minimal soup.
    const soup = [_][3]f32{
        .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 },
        .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 0 },
    };

    var remap: [6]u32 = undefined;
    const unique = zmeshopt.generateVertexRemap([3]f32, &remap, null, &soup);
    if (unique != 4) return error.RemapMissedDuplicates;

    var vertices: [4][3]f32 = undefined;
    var indices: [6]u32 = undefined;
    zmeshopt.remapVertexBuffer([3]f32, &vertices, &soup, &remap);
    zmeshopt.remapIndexBuffer(&indices, null, &remap);
    zmeshopt.optimizeVertexCache(&indices, &indices, unique);

    var encoded_buffer: [128]u8 = undefined;
    const encoded = try zmeshopt.encodeIndexBuffer(&encoded_buffer, &indices);
    var decoded: [6]u32 = undefined;
    try zmeshopt.decodeIndexBuffer(u32, &decoded, encoded);

    // The options module is a separate export the dependency has to carry
    // alongside the code; reaching it from out here is the test.
    std.debug.print(
        "zig consumer ok: zmeshopt {s}, simd {}, {} unique vertices, {} encoded bytes\n",
        .{ zmeshopt.version(), zmeshopt.options.simd, unique, encoded.len },
    );
}
