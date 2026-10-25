//! Each binding against the same upstream work called directly from C
//! (bench/baseline.c), measured through shakedown in ReleaseFast, so the
//! Zig layer's cost is a number. Where the idiomatic layer crosses
//! src/abi_shim.c, a third row loops the forwarder from C, so the hop alone
//! is the difference of two C rows. Timings are evidence, never a
//! correctness gate; `--smoke` runs each row once.
const std = @import("std");
const shakedown = @import("shakedown");
const zmeshopt = @import("zmeshopt");
const baseline = @import("baseline");
const provenance = @import("preflight_bench_options");

/// The mesh: a grid this many quads a side, two triangles each, with a
/// gentle height field so simplification has error to weigh.
const grid_side = 64;
const vertex_count = (grid_side + 1) * (grid_side + 1);
const index_count = grid_side * grid_side * 6;
/// Simplification keeps a quarter of the triangles, within 1% of the extents.
const target_index_count = index_count / 4;
const target_error = 0.01;
/// Meshlets of the size mesh shaders commonly launch.
const max_vertices = 64;
const max_triangles = 96;
const cone_weight = 0.25;

const Vertex = [3]f32;
const stride = @sizeOf(Vertex);

const Failed = error{Failed};

const Context = struct {
    vertices: [vertex_count]Vertex,
    indices: [index_count]u32,
    destination: [index_count]u32 = undefined,
    meshlets: []zmeshopt.Meshlet,
    meshlet_vertices: []u32,
    meshlet_triangles: []u8,
    encoded_indices: []const u8,
    encoded_vertices: []const u8,
    decoded_vertices: [vertex_count]Vertex = undefined,

    fn positions(c: *const Context) [*]const f32 {
        return @ptrCast(&c.vertices);
    }

    fn simplifyZig(c: *Context, n: u64) Failed!void {
        var failure: zmeshopt.Failure = .{};
        var total: usize = 0;
        for (0..n) |_| {
            const result = zmeshopt.simplify(Vertex, &c.destination, &c.indices, &c.vertices, target_index_count, target_error, .{}, &failure) catch return error.Failed;
            total += result.indices.len;
        }
        std.mem.doNotOptimizeAway(total);
    }

    fn simplifyShim(c: *Context, n: u64) Failed!void {
        std.mem.doNotOptimizeAway(baseline.zmeshopt_baseline_simplify_shim(target_error, &c.destination, &c.indices, index_count, c.positions(), vertex_count, stride, target_index_count, n));
    }

    fn simplifyC(c: *Context, n: u64) Failed!void {
        std.mem.doNotOptimizeAway(baseline.zmeshopt_baseline_simplify(target_error, &c.destination, &c.indices, index_count, c.positions(), vertex_count, stride, target_index_count, n));
    }

    fn meshletsZig(c: *Context, n: u64) Failed!void {
        var failure: zmeshopt.Failure = .{};
        var total: usize = 0;
        for (0..n) |_| {
            const meshlets = zmeshopt.buildMeshlets(Vertex, c.meshlets, c.meshlet_vertices, c.meshlet_triangles, &c.indices, &c.vertices, max_vertices, max_triangles, cone_weight, &failure) catch return error.Failed;
            total += meshlets.len;
        }
        std.mem.doNotOptimizeAway(total);
    }

    fn meshletsShim(c: *Context, n: u64) Failed!void {
        std.mem.doNotOptimizeAway(baseline.zmeshopt_baseline_build_meshlets_shim(cone_weight, c.meshlets.ptr, c.meshlet_vertices.ptr, c.meshlet_triangles.ptr, &c.indices, index_count, c.positions(), vertex_count, stride, max_vertices, max_triangles, n));
    }

    fn meshletsC(c: *Context, n: u64) Failed!void {
        std.mem.doNotOptimizeAway(baseline.zmeshopt_baseline_build_meshlets(cone_weight, c.meshlets.ptr, c.meshlet_vertices.ptr, c.meshlet_triangles.ptr, &c.indices, index_count, c.positions(), vertex_count, stride, max_vertices, max_triangles, n));
    }

    fn coverageZig(c: *Context, n: u64) Failed!void {
        var failure: zmeshopt.Failure = .{};
        var total: f32 = 0;
        for (0..n) |_| {
            const statistics = zmeshopt.analyzeCoverage(Vertex, &c.indices, &c.vertices, &failure) catch return error.Failed;
            total += statistics.coverage[0];
        }
        std.mem.doNotOptimizeAway(total);
    }

    fn coverageShim(c: *Context, n: u64) Failed!void {
        std.mem.doNotOptimizeAway(baseline.zmeshopt_baseline_analyze_coverage_shim(&c.indices, index_count, c.positions(), vertex_count, stride, n));
    }

    fn coverageC(c: *Context, n: u64) Failed!void {
        std.mem.doNotOptimizeAway(baseline.zmeshopt_baseline_analyze_coverage(&c.indices, index_count, c.positions(), vertex_count, stride, n));
    }

    fn vertexCacheZig(c: *Context, n: u64) Failed!void {
        var failure: zmeshopt.Failure = .{};
        for (0..n) |_| zmeshopt.optimizeVertexCache(&c.destination, &c.indices, vertex_count, &failure) catch return error.Failed;
        std.mem.doNotOptimizeAway(c.destination[0]);
    }

    fn vertexCacheC(c: *Context, n: u64) Failed!void {
        baseline.zmeshopt_baseline_optimize_vertex_cache(&c.destination, &c.indices, index_count, vertex_count, n);
        std.mem.doNotOptimizeAway(c.destination[0]);
    }

    fn decodeIndicesZig(c: *Context, n: u64) Failed!void {
        var failure: zmeshopt.Failure = .{};
        for (0..n) |_| zmeshopt.decodeIndexBuffer(u32, &c.destination, .init(c.encoded_indices), &failure) catch return error.Failed;
        std.mem.doNotOptimizeAway(c.destination[0]);
    }

    fn decodeIndicesC(c: *Context, n: u64) Failed!void {
        if (baseline.zmeshopt_baseline_decode_index_buffer(&c.destination, index_count, c.encoded_indices.ptr, c.encoded_indices.len, n) != 0) return error.Failed;
    }

    fn decodeVerticesZig(c: *Context, n: u64) Failed!void {
        var failure: zmeshopt.Failure = .{};
        for (0..n) |_| zmeshopt.decodeVertexBuffer(Vertex, &c.decoded_vertices, .init(c.encoded_vertices), &failure) catch return error.Failed;
        std.mem.doNotOptimizeAway(c.decoded_vertices[0]);
    }

    fn decodeVerticesC(c: *Context, n: u64) Failed!void {
        if (baseline.zmeshopt_baseline_decode_vertex_buffer(&c.decoded_vertices, vertex_count, stride, c.encoded_vertices.ptr, c.encoded_vertices.len, n) != 0) return error.Failed;
    }
};

/// The grid's corners, row by row, and its triangles, two per quad.
fn grid(context: *Context) void {
    for (&context.vertices, 0..) |*vertex, i| {
        const x: f32 = @floatFromInt(i % (grid_side + 1));
        const z: f32 = @floatFromInt(i / (grid_side + 1));
        vertex.* = .{ x, @sin(x * 0.1) * @cos(z * 0.1), z };
    }
    var at: usize = 0;
    for (0..grid_side) |row| {
        for (0..grid_side) |column| {
            const corner: u32 = @intCast(row * (grid_side + 1) + column);
            const below = corner + grid_side + 1;
            for ([_]u32{ corner, below, corner + 1, corner + 1, below, below + 1 }) |index| {
                context.indices[at] = index;
                at += 1;
            }
        }
    }
}

pub fn main(init: std.process.Init) !void {
    var failure: zmeshopt.Failure = .{};
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const options = try shakedown.bench.Options.fromArguments(args[1..]);
    const metadata: shakedown.bench.Metadata = .{ .commit = provenance.commit };
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const Row = shakedown.bench.Row(Context, Failed);

    // The fixtures, untimed: the grid, room for its meshlets, and the
    // encodings both decoders read.
    const context = try arena.create(Context);
    context.* = .{
        .vertices = undefined,
        .indices = undefined,
        .meshlets = try arena.alloc(zmeshopt.Meshlet, try zmeshopt.buildMeshletsBound(index_count, max_vertices, max_triangles, &failure)),
        .meshlet_vertices = try arena.alloc(u32, index_count),
        .meshlet_triangles = try arena.alloc(u8, index_count),
        .encoded_indices = undefined,
        .encoded_vertices = undefined,
    };
    grid(context);
    const index_buffer = try arena.alloc(u8, try zmeshopt.encodeIndexBufferBound(index_count, vertex_count, &failure));
    context.encoded_indices = try zmeshopt.encodeIndexBuffer(index_buffer, &context.indices, &failure);
    const vertex_buffer = try arena.alloc(u8, zmeshopt.encodeVertexBufferBound(Vertex, vertex_count));
    context.encoded_vertices = try zmeshopt.encodeVertexBuffer(Vertex, vertex_buffer, &context.vertices, &failure);

    const rows = [_]Row{
        .{ .name = "simplify_zig", .unit = "mesh", .run = Context.simplifyZig },
        .{ .name = "simplify_shim", .unit = "mesh", .run = Context.simplifyShim },
        .{ .name = "simplify_c", .unit = "mesh", .run = Context.simplifyC },
        .{ .name = "meshlets_zig", .unit = "mesh", .run = Context.meshletsZig },
        .{ .name = "meshlets_shim", .unit = "mesh", .run = Context.meshletsShim },
        .{ .name = "meshlets_c", .unit = "mesh", .run = Context.meshletsC },
        .{ .name = "coverage_zig", .unit = "mesh", .run = Context.coverageZig },
        .{ .name = "coverage_shim", .unit = "mesh", .run = Context.coverageShim },
        .{ .name = "coverage_c", .unit = "mesh", .run = Context.coverageC },
        .{ .name = "vertex_cache_zig", .unit = "mesh", .run = Context.vertexCacheZig },
        .{ .name = "vertex_cache_c", .unit = "mesh", .run = Context.vertexCacheC },
        .{ .name = "decode_indices_zig", .unit = "mesh", .initial = 10, .run = Context.decodeIndicesZig },
        .{ .name = "decode_indices_c", .unit = "mesh", .initial = 10, .run = Context.decodeIndicesC },
        .{ .name = "decode_vertices_zig", .unit = "mesh", .initial = 10, .run = Context.decodeVerticesZig },
        .{ .name = "decode_vertices_c", .unit = "mesh", .initial = 10, .run = Context.decodeVerticesC },
    };
    try shakedown.bench.run(Failed, init.gpa, init.io, &stdout.interface, context, &rows, metadata, options);
    try stdout.interface.flush();
}
