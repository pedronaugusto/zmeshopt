//! `EXT_meshopt_compression` end to end against zcgltf 0.2.0, both packages
//! in one process: zmeshopt encodes a mesh, the test writes the glTF JSON a
//! compressed asset carries, zcgltf parses it, zmeshopt decodes what cgltf's
//! metadata points at, and cgltf's accessor API reads the decoded bytes,
//! through every `mode` the extension defines and one of its filters.
//!
//! The asset is built here rather than checked in, so the values read back
//! are compared against the exact values encoded.

const std = @import("std");
const zcgltf = @import("zcgltf");
const zmeshopt = @import("zmeshopt");

const positions: [3][3]f32 = .{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } };
const triangle: [3]u32 = .{ 0, 1, 2 };
const outline: [4]u32 = .{ 0, 1, 2, 0 };

// Buffer 0 is the fallback: no uri, so `loadBuffers` leaves it unloaded and
// every byte read must come through the decoded views. Buffers 1 to 3 hold
// the compressed streams as data URIs: the positions (ATTRIBUTES, through
// the exponential filter), the triangle (TRIANGLES) and its outline as a
// line strip (INDICES).
const gltf_template =
    \\{{
    \\  "asset": {{ "version": "2.0" }},
    \\  "extensionsUsed": ["EXT_meshopt_compression"],
    \\  "extensionsRequired": ["EXT_meshopt_compression"],
    \\  "meshes": [{{ "primitives": [
    \\    {{ "attributes": {{ "POSITION": 0 }}, "indices": 1 }},
    \\    {{ "attributes": {{ "POSITION": 0 }}, "indices": 2, "mode": 3 }}
    \\  ] }}],
    \\  "accessors": [
    \\    {{ "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3" }},
    \\    {{ "bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR" }},
    \\    {{ "bufferView": 2, "componentType": 5123, "count": 4, "type": "SCALAR" }}
    \\  ],
    \\  "bufferViews": [
    \\    {{ "buffer": 0, "byteOffset": 0, "byteLength": 36, "byteStride": 12, "extensions": {{
    \\      "EXT_meshopt_compression": {{ "buffer": 1, "byteLength": {d}, "byteStride": 12, "count": 3, "mode": "ATTRIBUTES", "filter": "EXPONENTIAL" }} }} }},
    \\    {{ "buffer": 0, "byteOffset": 36, "byteLength": 6, "extensions": {{
    \\      "EXT_meshopt_compression": {{ "buffer": 2, "byteLength": {d}, "byteStride": 2, "count": 3, "mode": "TRIANGLES" }} }} }},
    \\    {{ "buffer": 0, "byteOffset": 42, "byteLength": 8, "extensions": {{
    \\      "EXT_meshopt_compression": {{ "buffer": 3, "byteLength": {d}, "byteStride": 2, "count": 4, "mode": "INDICES" }} }} }}
    \\  ],
    \\  "buffers": [
    \\    {{ "byteLength": 50 }},
    \\    {{ "byteLength": {d}, "uri": "data:application/octet-stream;base64,{s}" }},
    \\    {{ "byteLength": {d}, "uri": "data:application/octet-stream;base64,{s}" }},
    \\    {{ "byteLength": {d}, "uri": "data:application/octet-stream;base64,{s}" }}
    \\  ]
    \\}}
;

/// A decoded view's bytes, allocated through the document's own memory
/// options: `free` releases every non-null `view.data` through
/// `memory.free_func`, so a foreign allocator would be a mismatched free.
fn allocView(data: *zcgltf.Data, comptime T: type, count: usize) ![]T {
    const raw = data.memory.alloc_func.?(data.memory.user_data, count * @sizeOf(T)) orelse
        return error.OutOfMemory;
    return @as([*]T, @ptrCast(@alignCast(raw)))[0..count]; // safe: cgltf's allocator returns malloc-aligned blocks of the size asked
}

fn compressed(view: *const zcgltf.BufferView) zmeshopt.Encoded {
    const mc = &view.meshopt_compression;
    return .init(@as([*]const u8, @ptrCast(mc.buffer.?.data.?))[mc.offset..][0..mc.size]); // safe: loadBuffers loaded the buffer, and validate held the view inside it
}

fn base64(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const out = try gpa.alloc(u8, encoder.calcSize(bytes.len));
    _ = encoder.encode(out, bytes);
    return out;
}

test "a compressed glTF asset round-trips through zcgltf" {
    const gpa = std.testing.allocator;
    var failure: zmeshopt.Failure = .{};

    // 1. Encode with zmeshopt. The positions pass through the exponential
    //    filter first; 16 mantissa bits keep 0 and 1 exact, so the values
    //    read back are compared bit for bit. Vertex codec version 0 is the
    //    older of the two the decoder reads; the round trip holds for both.
    var filtered: [3][3]u32 = undefined;
    try zmeshopt.encodeFilterExp([3]u32, &filtered, 16, @as([*]const f32, @ptrCast(&positions))[0 .. 3 * 3], .separate, &failure);
    const vertex_buffer = try gpa.alloc(u8, zmeshopt.encodeVertexBufferBound([3]u32, filtered.len));
    defer gpa.free(vertex_buffer);
    const encoded_vertices = try zmeshopt.encodeVertexBufferLevel([3]u32, vertex_buffer, &filtered, 2, .v0, &failure);

    const index_buffer = try gpa.alloc(u8, try zmeshopt.encodeIndexBufferBound(triangle.len, positions.len, &failure));
    defer gpa.free(index_buffer);
    const encoded_triangle = try zmeshopt.encodeIndexBuffer(index_buffer, &triangle, &failure);

    const sequence_buffer = try gpa.alloc(u8, zmeshopt.encodeIndexSequenceBound(outline.len, positions.len));
    defer gpa.free(sequence_buffer);
    const encoded_outline = try zmeshopt.encodeIndexSequence(sequence_buffer, &outline, &failure);

    // 2. Write the JSON of a compressed asset around the three streams.
    const vertices64 = try base64(gpa, encoded_vertices);
    defer gpa.free(vertices64);
    const triangle64 = try base64(gpa, encoded_triangle);
    defer gpa.free(triangle64);
    const outline64 = try base64(gpa, encoded_outline);
    defer gpa.free(outline64);
    const json = try std.fmt.allocPrint(gpa, gltf_template, .{
        encoded_vertices.len, encoded_triangle.len, encoded_outline.len,
        encoded_vertices.len, vertices64,           encoded_triangle.len,
        triangle64,           encoded_outline.len,  outline64,
    });
    defer gpa.free(json);

    // 3. Parse with zcgltf. The fallback buffer has no uri, so it stays
    //    unloaded; the compressed buffers load from their data URIs.
    var options = std.mem.zeroes(zcgltf.Options);
    options.memory = zcgltf.memoryOptions(&gpa);
    const data = try zcgltf.parse(&options, .init(json));
    defer zcgltf.free(data);
    try zcgltf.loadBuffers(&options, data, null);
    try zcgltf.validate(data);

    const views = data.buffer_views.?;
    try std.testing.expect(views[0].has_meshopt_compression != 0);
    try std.testing.expectEqual(.attributes, views[0].meshopt_compression.mode);
    try std.testing.expectEqual(.exponential, views[0].meshopt_compression.filter);
    try std.testing.expectEqual(@as(usize, 12), views[0].meshopt_compression.stride);
    try std.testing.expectEqual(.triangles, views[1].meshopt_compression.mode);
    try std.testing.expectEqual(.indices, views[2].meshopt_compression.mode);
    // Before decoding, the compressed views expose no bytes at all.
    try std.testing.expect(zcgltf.bufferViewData(&views[0]) == null);

    // 4. Decode each view's compressed region with zmeshopt and hand the
    //    result to cgltf through `view.data`. Each pointer is set before its
    //    decode, so `free` owns it on every path.
    const vertices = try allocView(data, [3]u32, views[0].meshopt_compression.count);
    views[0].data = vertices.ptr;
    try zmeshopt.decodeVertexBuffer([3]u32, vertices, compressed(&views[0]), &failure);
    // In place: each u32 becomes the f32 it encoded.
    zmeshopt.decodeFilterExp([3]u32, vertices);

    const indices = try allocView(data, u16, views[1].meshopt_compression.count);
    views[1].data = indices.ptr;
    try zmeshopt.decodeIndexBuffer(u16, indices, compressed(&views[1]), &failure);

    const strip = try allocView(data, u16, views[2].meshopt_compression.count);
    views[2].data = strip.ptr;
    try zmeshopt.decodeIndexSequence(u16, strip, compressed(&views[2]), &failure);

    // 5. Read back through cgltf's accessor API, which prefers `view.data`.
    const accessors = data.accessors.?;
    var vertex: [3]f32 = undefined;
    for (positions, 0..) |expected, i| {
        try std.testing.expect(zcgltf.readFloat(&accessors[0], i, &vertex));
        try std.testing.expectEqualSlices(f32, &expected, &vertex);
    }
    var read_triangle: [3]u32 = undefined;
    try std.testing.expectEqualSlices(u32, &triangle, zcgltf.unpackIndices(&accessors[1], u32, &read_triangle));
    var read_outline: [4]u32 = undefined;
    try std.testing.expectEqualSlices(u32, &outline, zcgltf.unpackIndices(&accessors[2], u32, &read_outline));
    try std.testing.expectEqual(@as(usize, 0), failure.frames().len);
}
