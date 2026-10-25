//! What a project that depends on zmeshopt writes.
const zmeshopt = @import("zmeshopt");

pub fn main() !void {
    var failure: zmeshopt.Failure = .{};
    // A quad with one duplicate corner vertex, as a minimal soup.
    const soup = [_][3]f32{
        .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 },
        .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 0 },
    };
    var remap: [6]u32 = undefined;
    const unique = try zmeshopt.generateVertexRemap([3]f32, &remap, null, &soup, &failure);
    if (unique != 4) return error.RemapMissedDuplicates;
    var vertices: [4][3]f32 = undefined;
    var indices: [6]u32 = undefined;
    try zmeshopt.remapVertexBuffer([3]f32, &vertices, &soup, &remap, &failure);
    try zmeshopt.remapIndexBuffer(&indices, null, &remap, &failure);
    try zmeshopt.optimizeVertexCache(&indices, &indices, unique, &failure);
    var encoded_buffer: [128]u8 = undefined;
    const encoded = try zmeshopt.encodeIndexBuffer(&encoded_buffer, &indices, &failure);
    var decoded: [6]u32 = undefined;
    try zmeshopt.decodeIndexBuffer(u32, &decoded, .init(encoded), &failure);
}
