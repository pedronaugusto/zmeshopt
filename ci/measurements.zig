//! Recomputes every count README.md publishes, as the Markdown table its
//! generated block holds (`zig build measurements`). The docs check rebuilds
//! the block from this program and fails when the two differ, so no count in
//! the README is written by hand. Run from the repository root.
const std = @import("std");
const Io = std.Io;

/// The largest file read.
const max_file_bytes = 1 << 22;
const header = "libs/meshoptimizer/src/meshoptimizer.h";

const Row = struct { value: []const u8, description: []const u8 };

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const cwd = Io.Dir.cwd();

    // At the start of a line: the C++ allocator class indents the same
    // macro on a member, which is no entry point.
    const declarations = try cwd.readFileAlloc(io, header, a, .limited(max_file_bytes));
    const api = atLineStart(declarations, "MESHOPTIMIZER_API");
    const experimental = atLineStart(declarations, "MESHOPTIMIZER_EXPERIMENTAL");
    const externs = try countInDirectory(a, io, cwd, "src/c", ".zig", "pub extern fn meshopt_");
    var buffer: [4096]u8 = undefined;
    // The ABI guard's reverse sweep pairs every header function with its
    // extern, so a difference is a defect in this program.
    if (api + experimental != externs) {
        var stderr = Io.File.stderr().writer(io, &buffer);
        try stderr.interface.print("{d} C entry points but {d} Zig externs\n", .{ api + experimental, externs });
        try stderr.interface.flush();
        return 1;
    }
    const manifest = try cwd.readFileAlloc(io, "build.zig.zon", a, .limited(1 << 20));
    const rows = [_]Row{
        .{ .value = version(manifest) orelse return error.NoVersion, .description = "version (one home: `build.zig.zon`)" },
        .{ .value = try a.print("{d}", .{externs}), .description = "C entry points (`MESHOPTIMIZER_API` and `MESHOPTIMIZER_EXPERIMENTAL` in the vendored header), each with its Zig extern" },
        .{ .value = try a.print("{d}", .{experimental}), .description = "of them marked experimental by upstream, bound and labelled" },
        .{ .value = try a.print("{d}", .{try countLines(a, io, cwd, "src/abi_shim.h", "ZMESHOPT_SHIM_API size_t") + try countLines(a, io, cwd, "src/abi_shim.h", "ZMESHOPT_SHIM_API void")}), .description = "forwarders in `src/abi_shim.c` for the two caller shapes Zig 0.16.0 miscompiled" },
        .{ .value = try a.print("{d}", .{try countLines(a, io, cwd, "src/testing/abi.zig", "try expectDrift(")}), .description = "deliberate drifts the ABI guard must name (`src/testing/abi.zig`)" },
        .{ .value = try a.print("{d}", .{try countLines(a, io, cwd, "tests/c_smoke.c", "assert(")}), .description = "assertions in the standalone C smoke test" },
        .{ .value = try a.print("{d}", .{try countTranslationUnits(a, io, cwd)}), .description = "vendored meshoptimizer translation units `build.zig` compiles" },
    };
    var stdout = Io.File.stdout().writer(io, &buffer);
    try stdout.interface.writeAll("| | |\n|---:|---|\n");
    for (rows) |row| try stdout.interface.print("| **{s}** | {s} |\n", .{ row.value, row.description });
    try stdout.interface.flush();
    return 0;
}

/// The `.version` string of build.zig.zon.
fn version(manifest: []const u8) ?[]const u8 {
    const key = ".version = \"";
    const at = std.mem.find(u8, manifest, key) orelse return null;
    const start = at + key.len;
    const end = std.mem.findScalarPos(u8, manifest, start, '"') orelse return null;
    return manifest[start..end];
}

/// Lines starting with `prefix`, after indentation, in every `suffix` file of `path`.
fn countInDirectory(a: std.mem.Allocator, io: Io, root: Io.Dir, path: []const u8, suffix: []const u8, prefix: []const u8) !usize {
    var dir = try root.openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var total: usize = 0;
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, suffix)) continue;
        total += startingWith(try dir.readFileAlloc(io, entry.name, a, .limited(max_file_bytes)), prefix);
    }
    return total;
}

fn countLines(a: std.mem.Allocator, io: Io, root: Io.Dir, path: []const u8, prefix: []const u8) !usize {
    return startingWith(try root.readFileAlloc(io, path, a, .limited(max_file_bytes)), prefix);
}

fn startingWith(text: []const u8, prefix: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), prefix)) count += 1;
    }
    return count;
}

/// Lines starting with `prefix` exactly, indentation counting against them.
fn atLineStart(text: []const u8, prefix: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, prefix)) count += 1;
    }
    return count;
}

/// The quoted `libs/meshoptimizer/….cpp` paths in build.zig.
fn countTranslationUnits(a: std.mem.Allocator, io: Io, root: Io.Dir) !usize {
    const text = try root.readFileAlloc(io, "build.zig", a, .limited(max_file_bytes));
    var count: usize = 0;
    var from: usize = 0;
    while (std.mem.findPos(u8, text, from, "\"libs/meshoptimizer/")) |at| {
        const end = std.mem.findScalarPos(u8, text, at + 1, '"') orelse break;
        if (std.mem.endsWith(u8, text[at + 1 .. end], ".cpp")) count += 1;
        from = end + 1;
    }
    return count;
}

test "the version is read from the manifest" {
    try std.testing.expectEqualStrings("0.2.0", version(".{\n    .version = \"0.2.0\",\n").?);
    try std.testing.expect(version(".{}") == null);
}

test "a declaration counts at the start of a line only" {
    try std.testing.expectEqual(@as(usize, 1), atLineStart("MESHOPTIMIZER_API void f(void);\n\tMESHOPTIMIZER_API static Storage& storage();\n", "MESHOPTIMIZER_API"));
}

test "a line counts once, after its indentation" {
    try std.testing.expectEqual(@as(usize, 2), startingWith("  assert(a);\nassert(b); assert(c);\n// assert(d)\n", "assert("));
}
