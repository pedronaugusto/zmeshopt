//! What a project that depends on zmeshopt writes.
const zmeshopt = @import("zmeshopt");

pub fn main() !void {
    // A quad with one duplicate corner vertex, as a minimal soup.
    const soup = [_][3]f32{
        .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 },
        .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 0 },
    };
    var remap: [6]u32 = undefined;
    const unique = try zmeshopt.generateVertexRemap([3]f32, &remap, null, &soup);
    if (unique != 4) return error.RemapMissedDuplicates;
    var vertices: [4][3]f32 = undefined;
    var indices: [6]u32 = undefined;
    try zmeshopt.remapVertexBuffer([3]f32, &vertices, &soup, &remap);
    try zmeshopt.remapIndexBuffer(&indices, null, &remap);
    try zmeshopt.optimizeVertexCache(&indices, &indices, unique);
    var encoded_buffer: [128]u8 = undefined;
    const encoded = try zmeshopt.encodeIndexBuffer(&encoded_buffer, &indices);
    var decoded: [6]u32 = undefined;
    var failure: zmeshopt.Failure = .{};
    try zmeshopt.decodeIndexBuffer(u32, &decoded, .init(encoded), &failure);
}
