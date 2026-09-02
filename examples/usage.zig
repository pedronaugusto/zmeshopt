//! The standard meshoptimizer pipeline on a generated mesh: index the raw
//! triangle soup, optimize the orders, simplify a LOD, cut meshlets, and
//! compress the buffers for storage.
//!
//! `zig build examples` builds AND runs this; `ci/readme_usage.sh` extracts
//! the region between the usage markers into README.md, so the snippet a
//! reader copies is code CI executes.

const std = @import("std");
const zmeshopt = @import("zmeshopt");

const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // --- README:usage ---

    // Route meshoptimizer's temporary allocations through a Zig allocator
    // (optional; the default is operator new/delete, and the install is
    // process-wide and permanent).
    zmeshopt.installZigAllocator(std.heap.page_allocator);

    // A 32x32 grid as unindexed triangle soup: 6144 corners, mostly shared.
    const soup = try generateGridSoup(arena, 32);

    // 1. Index: collapse duplicate vertices, then remap both buffers.
    const remap = try arena.alloc(u32, soup.len);
    const unique = zmeshopt.generateVertexRemap(Vertex, remap, null, soup);
    const vertices = try arena.alloc(Vertex, unique);
    const indices = try arena.alloc(u32, soup.len);
    zmeshopt.remapVertexBuffer(Vertex, vertices, soup, remap);
    zmeshopt.remapIndexBuffer(indices, null, remap);

    // 2. Optimize: vertex cache order, then overdraw, then fetch locality.
    zmeshopt.optimizeVertexCache(indices, indices, vertices.len);
    zmeshopt.optimizeOverdraw(Vertex, indices, indices, vertices, 1.05);
    _ = zmeshopt.optimizeVertexFetch(Vertex, vertices, indices, vertices);

    const cache = zmeshopt.analyzeVertexCache(indices, vertices.len, 16, 0, 0);

    // 3. Simplify: a quarter-size LOD within 1% of the mesh extents.
    const lod_buffer = try arena.alloc(u32, indices.len);
    const lod = zmeshopt.simplify(Vertex, lod_buffer, indices, vertices, indices.len / 4, 0.01, .{});

    // 4. Meshlets for GPU-driven rendering.
    const max_vertices = 64;
    const max_triangles = 96;
    const meshlet_buffer = try arena.alloc(zmeshopt.Meshlet, zmeshopt.buildMeshletsBound(indices.len, max_vertices, max_triangles));
    const meshlet_vertices = try arena.alloc(u32, indices.len);
    const meshlet_triangles = try arena.alloc(u8, indices.len);
    const meshlets = zmeshopt.buildMeshlets(Vertex, meshlet_buffer, meshlet_vertices, meshlet_triangles, indices, vertices, max_vertices, max_triangles, 0.25);
    const bounds = zmeshopt.computeMeshletBounds(
        Vertex,
        zmeshopt.meshletVertexSlice(meshlets[0], meshlet_vertices),
        zmeshopt.meshletTriangleSlice(meshlets[0], meshlet_triangles),
        vertices,
    );

    // 5. Compress both buffers for storage or transmission.
    const encoded_vertices_buffer = try arena.alloc(u8, zmeshopt.encodeVertexBufferBound(Vertex, vertices.len));
    const encoded_vertices = try zmeshopt.encodeVertexBuffer(Vertex, encoded_vertices_buffer, vertices);
    const encoded_indices_buffer = try arena.alloc(u8, zmeshopt.encodeIndexBufferBound(indices.len, vertices.len));
    const encoded_indices = try zmeshopt.encodeIndexBuffer(encoded_indices_buffer, indices);
    // --- README:usage ---

    std.debug.print("indexed:    {} corners -> {} vertices, {} triangles\n", .{ soup.len, vertices.len, indices.len / 3 });
    std.debug.print("optimized:  ACMR {d:.3}, {} vertices transformed\n", .{ cache.acmr, cache.vertices_transformed });
    std.debug.print("simplified: {} -> {} triangles (error {d:.4})\n", .{ indices.len / 3, lod.indices.len / 3, lod.err });
    std.debug.print("meshlets:   {} (first: {} vertices, {} triangles, radius {d:.2})\n", .{ meshlets.len, meshlets[0].vertex_count, meshlets[0].triangle_count, bounds.radius });
    std.debug.print("encoded:    vertices {} -> {} bytes, indices {} -> {} bytes\n", .{ vertices.len * @sizeOf(Vertex), encoded_vertices.len, indices.len * 4, encoded_indices.len });
}

/// `n` x `n` quads of a wavy heightfield as raw unindexed triangles — the
/// shape mesh data has before any of this library touches it.
fn generateGridSoup(allocator: std.mem.Allocator, comptime n: usize) ![]Vertex {
    const soup = try allocator.alloc(Vertex, n * n * 6);
    for (0..n) |y| {
        for (0..n) |x| {
            const quad = [4]Vertex{
                gridVertex(n, x, y),
                gridVertex(n, x + 1, y),
                gridVertex(n, x, y + 1),
                gridVertex(n, x + 1, y + 1),
            };
            const corners = [6]u2{ 0, 1, 2, 1, 3, 2 };
            for (corners, 0..) |corner, i| soup[(y * n + x) * 6 + i] = quad[corner];
        }
    }
    return soup;
}

fn gridVertex(comptime n: usize, x: usize, y: usize) Vertex {
    const fx = @as(f32, @floatFromInt(x)) / n;
    const fy = @as(f32, @floatFromInt(y)) / n;
    return .{
        .position = .{ fx, fy, 0.05 * @sin(fx * 12.0) * @cos(fy * 12.0) },
        .normal = .{ 0, 0, 1 },
    };
}
