//! The fuzz targets, one per decoder. Whatever bytes arrive, and whatever
//! counts the caller asks for, a decoder either decodes or refuses with one
//! frame saying why, and writes nothing past what its contract gives it:
//! guard words after every destination must survive. Each property mutates
//! encodings of a small mesh; under `bay fuzz` Zig's fuzzer drives the same
//! properties.
const std = @import("std");
const shakedown = @import("shakedown");
const zmeshopt = @import("../zmeshopt.zig");

/// The most bytes a case's encoding holds.
const max_encoded = 512;
/// The most elements a case asks a decoder for.
const max_count = 9;
/// Elements past each destination that no decoder may write.
const guard = 8;
const guard_word: u32 = 0xa5a5a5a5;

/// Encodings of one mesh, the seeds every property mutates.
const Seeds = struct {
    index_buffer: [max_encoded]u8 = undefined,
    index_buffer_len: usize = 0,
    index_sequence: [max_encoded]u8 = undefined,
    index_sequence_len: usize = 0,
    vertex_buffer: [max_encoded]u8 = undefined,
    vertex_buffer_len: usize = 0,
    meshlet: [max_encoded]u8 = undefined,
    meshlet_len: usize = 0,

    fn init() !Seeds {
        var seeds: Seeds = .{};
        var failure: zmeshopt.Failure = .{};
        const indices = [_]u32{ 0, 1, 2, 2, 1, 3, 3, 1, 4 };
        seeds.index_buffer_len = (try zmeshopt.encodeIndexBuffer(&seeds.index_buffer, &indices, &failure)).len;
        seeds.index_sequence_len = (try zmeshopt.encodeIndexSequence(&seeds.index_sequence, &indices, &failure)).len;
        const vertices = [_][4]f32{ .{ 0, 0, 0, 1 }, .{ 1, 0, 0, 1 }, .{ 0, 1, 0, 1 }, .{ 1, 1, 0, 1 }, .{ 2, 1, 0, 1 } };
        seeds.vertex_buffer_len = (try zmeshopt.encodeVertexBuffer([4]f32, &seeds.vertex_buffer, &vertices, &failure)).len;
        const references = [_]u32{ 10, 11, 12, 13, 14 };
        const triangles = [_]u8{ 0, 1, 2, 2, 1, 3, 3, 1, 4 };
        seeds.meshlet_len = (try zmeshopt.encodeMeshlet(&seeds.meshlet, &references, &triangles, &failure)).len;
        return seeds;
    }
};

/// A decoder's outcome is a decode with no frame, or a refusal with one.
fn expectOutcome(result: anyerror!void, failure: *const zmeshopt.Failure) !void {
    if (result) |_| {
        try std.testing.expectEqual(@as(usize, 0), failure.frames().len);
    } else |_| {
        try std.testing.expectEqual(@as(usize, 1), failure.frames().len);
    }
}

fn expectGuard(comptime T: type, tail: []const T) !void {
    for (std.mem.sliceAsBytes(tail)) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
}

fn count(case: *shakedown.Case) usize {
    return shakedown.gen.intRange(case.source, usize, 0, max_count);
}

fn indexBuffer(seeds: *const Seeds, case: *shakedown.Case) !void {
    var storage: [max_encoded]u8 = undefined;
    const bytes = shakedown.gen.mutated(case.source, &storage, &.{seeds.index_buffer[0..seeds.index_buffer_len]});
    const corners = count(case);
    var out: [max_count + guard]u32 = @splat(guard_word);
    var failure: zmeshopt.Failure = .{};
    try expectOutcome(zmeshopt.decodeIndexBuffer(u32, out[0..corners], .init(bytes), &failure), &failure);
    try expectGuard(u32, out[corners..]);
}

fn indexSequence(seeds: *const Seeds, case: *shakedown.Case) !void {
    var storage: [max_encoded]u8 = undefined;
    const bytes = shakedown.gen.mutated(case.source, &storage, &.{seeds.index_sequence[0..seeds.index_sequence_len]});
    const n = count(case);
    var out: [max_count + guard]u16 = @splat(0xa5a5);
    var failure: zmeshopt.Failure = .{};
    try expectOutcome(zmeshopt.decodeIndexSequence(u16, out[0..n], .init(bytes), &failure), &failure);
    try expectGuard(u16, out[n..]);
}

fn indexVersion(seeds: *const Seeds, case: *shakedown.Case) !void {
    var storage: [max_encoded]u8 = undefined;
    const bytes = shakedown.gen.mutated(case.source, &storage, &.{ seeds.index_buffer[0..seeds.index_buffer_len], seeds.index_sequence[0..seeds.index_sequence_len] });
    if (zmeshopt.decodeIndexVersion(.init(bytes))) |version| try std.testing.expect(version <= 1);
}

fn vertexBuffer(seeds: *const Seeds, case: *shakedown.Case) !void {
    var storage: [max_encoded]u8 = undefined;
    const bytes = shakedown.gen.mutated(case.source, &storage, &.{seeds.vertex_buffer[0..seeds.vertex_buffer_len]});
    const n = count(case);
    var out: [max_count + guard][4]f32 = @splat(@splat(@bitCast(guard_word)));
    var failure: zmeshopt.Failure = .{};
    try expectOutcome(zmeshopt.decodeVertexBuffer([4]f32, out[0..n], .init(bytes), &failure), &failure);
    try expectGuard([4]f32, out[n..]);
}

fn vertexVersion(seeds: *const Seeds, case: *shakedown.Case) !void {
    var storage: [max_encoded]u8 = undefined;
    const bytes = shakedown.gen.mutated(case.source, &storage, &.{seeds.vertex_buffer[0..seeds.vertex_buffer_len]});
    if (zmeshopt.decodeVertexVersion(.init(bytes))) |version| try std.testing.expect(version <= 1);
}

fn meshlet(seeds: *const Seeds, case: *shakedown.Case) !void {
    var storage: [max_encoded]u8 = undefined;
    const bytes = shakedown.gen.mutated(case.source, &storage, &.{seeds.meshlet[0..seeds.meshlet_len]});
    const vertex_count = count(case);
    const triangle_count = count(case);
    // The room the contract asks for: each count's bytes rounded up to 4.
    const vertex_room = std.mem.alignForward(usize, vertex_count * 2, 4) / 2;
    const triangle_room = (std.mem.alignForward(usize, triangle_count * 3, 4) + 2) / 3;
    var vertices: [max_count + 1 + guard]u16 align(4) = @splat(0xa5a5);
    var triangles: [max_count + 1 + guard][3]u8 align(4) = @splat(@splat(0xa5));
    var failure: zmeshopt.Failure = .{};
    try expectOutcome(zmeshopt.decodeMeshlet(u16, [3]u8, vertices[0..vertex_room], vertex_count, triangles[0..triangle_room], triangle_count, .init(bytes), &failure), &failure);
    try expectGuard(u16, vertices[vertex_room..]);
    try expectGuard(u8, std.mem.sliceAsBytes(triangles[0..])[std.mem.alignForward(usize, triangle_count * 3, 4)..]);
}

fn meshletRaw(seeds: *const Seeds, case: *shakedown.Case) !void {
    var storage: [max_encoded]u8 = undefined;
    const bytes = shakedown.gen.mutated(case.source, &storage, &.{seeds.meshlet[0..seeds.meshlet_len]});
    const vertex_count = count(case);
    const triangle_count = count(case);
    const vertex_room = std.mem.alignForward(usize, vertex_count, 4);
    const triangle_room = std.mem.alignForward(usize, triangle_count, 4);
    var vertices: [16 + guard]u32 align(16) = @splat(guard_word);
    var triangles: [16 + guard]u32 align(16) = @splat(guard_word);
    var failure: zmeshopt.Failure = .{};
    try expectOutcome(zmeshopt.decodeMeshletRaw(vertices[0..vertex_room], vertex_count, triangles[0..triangle_room], triangle_count, .init(bytes), &failure), &failure);
    try expectGuard(u32, vertices[vertex_room..]);
    try expectGuard(u32, triangles[triangle_room..]);
}

test "any bytes decoded as an index buffer decode or refuse, and write only the destination" {
    const seeds: Seeds = try .init();
    try shakedown.check(std.testing.allocator, &seeds, indexBuffer, .{});
}

test "any bytes decoded as an index sequence decode or refuse, and write only the destination" {
    const seeds: Seeds = try .init();
    try shakedown.check(std.testing.allocator, &seeds, indexSequence, .{});
}

test "any bytes read for an index codec version give a version the decoder reads, or none" {
    const seeds: Seeds = try .init();
    try shakedown.check(std.testing.allocator, &seeds, indexVersion, .{});
}

test "any bytes decoded as a vertex buffer decode or refuse, and write only the destination" {
    const seeds: Seeds = try .init();
    try shakedown.check(std.testing.allocator, &seeds, vertexBuffer, .{});
}

test "any bytes read for a vertex codec version give a version the decoder reads, or none" {
    const seeds: Seeds = try .init();
    try shakedown.check(std.testing.allocator, &seeds, vertexVersion, .{});
}

test "any bytes decoded as a meshlet decode or refuse, and write only the destinations" {
    const seeds: Seeds = try .init();
    try shakedown.check(std.testing.allocator, &seeds, meshlet, .{});
}

test "any bytes decoded as a raw meshlet decode or refuse, and write only the padded destinations" {
    const seeds: Seeds = try .init();
    try shakedown.check(std.testing.allocator, &seeds, meshletRaw, .{});
}
