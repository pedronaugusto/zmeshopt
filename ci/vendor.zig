//! Proves libs/meshoptimizer is upstream at the pinned commit, byte for
//! byte: every taken path holds the same files with the same bytes, nothing
//! else sits beside them, the design document names the commit
//! build.zig.zon pins, and build.zig compiles every translation unit taken.
//! Behaviour the package needs that upstream lacks lives in src/, on the
//! package's side of the boundary.
//!
//! zmeshopt-vendor VENDORED UPSTREAM MANIFEST RECORD BUILD
const std = @import("std");
const Io = std.Io;

/// What was taken from upstream: directories whole, files as they are.
const taken = [_][]const u8{ "src", "LICENSE.md" };
/// The largest file compared.
const max_file_bytes = 1 << 22;
/// Where build.zig names a translation unit.
const unit_prefix = "\"libs/meshoptimizer/src/";

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 6) return error.Usage;
    const cwd = Io.Dir.cwd();
    var vendored = try cwd.openDir(io, args[1], .{ .iterate = true });
    defer vendored.close(io);
    var upstream = try cwd.openDir(io, args[2], .{ .iterate = true });
    defer upstream.close(io);
    var findings: std.ArrayList(u8) = .empty;
    try compareTop(a, io, vendored, upstream, &findings);
    const manifest = try cwd.readFileAlloc(io, args[3], a, .limited(1 << 20));
    const record = try cwd.readFileAlloc(io, args[4], a, .limited(1 << 20));
    try checkRecord(a, manifest, record, &findings);
    const build = try cwd.readFileAlloc(io, args[5], a, .limited(1 << 20));
    try checkUnits(a, try listFiles(a, io, vendored, "src"), build, &findings);
    if (findings.items.len == 0) return 0;
    var buffer: [4096]u8 = undefined;
    var stderr = Io.File.stderr().writer(io, &buffer);
    try stderr.interface.print("libs/meshoptimizer is not upstream verbatim:\n{s}", .{findings.items});
    try stderr.interface.flush();
    return 1;
}

/// Compares each taken path, and refuses a vendored entry that is not one.
fn compareTop(a: std.mem.Allocator, io: Io, vendored: Io.Dir, upstream: Io.Dir, findings: *std.ArrayList(u8)) !void {
    var it = vendored.iterate();
    while (try it.next(io)) |entry| {
        if (!contains(&taken, entry.name)) try findings.print(a, "  {s}: not taken from upstream\n", .{entry.name});
    }
    for (taken) |name| {
        const kind = (upstream.statFile(io, name, .{}) catch {
            try findings.print(a, "  {s}: upstream has no such path\n", .{name});
            continue;
        }).kind;
        if (kind == .directory) try compareTrees(a, io, vendored, upstream, name, findings) else try compareFiles(a, io, vendored, upstream, name, findings);
    }
}

/// Compares two trees under `path`, both directions, by file.
fn compareTrees(a: std.mem.Allocator, io: Io, vendored: Io.Dir, upstream: Io.Dir, path: []const u8, findings: *std.ArrayList(u8)) !void {
    const ours = try listFiles(a, io, vendored, path);
    const theirs = try listFiles(a, io, upstream, path);
    for (theirs) |name| {
        if (!contains(ours, name)) try findings.print(a, "  {s}: missing from the vendored copy\n", .{name});
    }
    for (ours) |name| {
        if (!contains(theirs, name)) try findings.print(a, "  {s}: added to the vendored copy\n", .{name}) else try compareFiles(a, io, vendored, upstream, name, findings);
    }
}

/// Every file under `path`, as paths with `/`.
fn listFiles(a: std.mem.Allocator, io: Io, root: Io.Dir, path: []const u8) ![]const []const u8 {
    var dir = root.openDir(io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => |e| return e,
    };
    defer dir.close(io);
    var walker = try dir.walk(a);
    defer walker.deinit();
    var names: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const relative = try a.dupe(u8, entry.path);
        std.mem.replaceScalar(u8, relative, '\\', '/');
        try names.append(a, try a.print("{s}/{s}", .{ path, relative }));
    }
    return names.items;
}

/// Compares one file's bytes.
fn compareFiles(a: std.mem.Allocator, io: Io, vendored: Io.Dir, upstream: Io.Dir, name: []const u8, findings: *std.ArrayList(u8)) !void {
    const ours = vendored.readFileAlloc(io, name, a, .limited(max_file_bytes)) catch |err| switch (err) {
        error.FileNotFound => return findings.print(a, "  {s}: missing from the vendored copy\n", .{name}),
        else => |e| return e,
    };
    const theirs = try upstream.readFileAlloc(io, name, a, .limited(max_file_bytes));
    if (!std.mem.eql(u8, ours, theirs)) try findings.print(a, "  {s}: differs from upstream\n", .{name});
}

/// Requires the record to name the commit the manifest pins upstream at.
fn checkRecord(a: std.mem.Allocator, manifest: []const u8, record: []const u8, findings: *std.ArrayList(u8)) !void {
    const commit = pinnedCommit(manifest) orelse return findings.print(a, "  build.zig.zon pins meshoptimizer at no commit\n", .{});
    if (std.mem.find(u8, record, commit) == null) try findings.print(a, "  the vendor record does not name the pinned commit {s}\n", .{commit});
}

/// The commit after `#` in the meshoptimizer pin's URL.
fn pinnedCommit(manifest: []const u8) ?[]const u8 {
    const at = std.mem.find(u8, manifest, ".meshoptimizer = .{") orelse return null;
    const url = std.mem.findPos(u8, manifest, at, "github.com/zeux/meshoptimizer") orelse return null;
    const hash = std.mem.findScalarPos(u8, manifest, url, '#') orelse return null;
    const end = std.mem.findScalarPos(u8, manifest, hash, '"') orelse return null;
    return manifest[hash + 1 .. end];
}

/// Requires build.zig to compile every vendored `.cpp` and name none that is
/// not there: a re-vendor that adds a unit would otherwise leave it out, and
/// one that removes a unit would fail far from the cause.
fn checkUnits(a: std.mem.Allocator, files: []const []const u8, build: []const u8, findings: *std.ArrayList(u8)) !void {
    var listed: std.ArrayList([]const u8) = .empty;
    var from: usize = 0;
    while (std.mem.findPos(u8, build, from, unit_prefix)) |at| {
        const start = at + "\"libs/meshoptimizer/".len;
        const end = std.mem.findScalarPos(u8, build, start, '"') orelse break;
        from = end + 1;
        if (std.mem.endsWith(u8, build[start..end], ".cpp")) try listed.append(a, build[start..end]);
    }
    for (files) |name| {
        if (std.mem.endsWith(u8, name, ".cpp") and !contains(listed.items, name)) try findings.print(a, "  {s}: vendored, but build.zig does not compile it\n", .{name});
    }
    for (listed.items) |name| {
        if (!contains(files, name)) try findings.print(a, "  {s}: build.zig compiles it, but it is not vendored\n", .{name});
    }
}

fn contains(list: []const []const u8, item: []const u8) bool {
    for (list) |candidate| if (std.mem.eql(u8, candidate, item)) return true;
    return false;
}

test "the pinned commit is read from the manifest's URL" {
    const manifest =
        \\        .meshoptimizer = .{
        \\            .url = "git+https://github.com/zeux/meshoptimizer?ref=v1.2#9d9890c7",
    ;
    try std.testing.expectEqualStrings("9d9890c7", pinnedCommit(manifest).?);
    try std.testing.expect(pinnedCommit(".other = .{}") == null);
}

test "a unit vendored but not compiled, or compiled but not vendored, is refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var findings: std.ArrayList(u8) = .empty;
    const build = "    \"libs/meshoptimizer/src/allocator.cpp\",\n    \"libs/meshoptimizer/src/gone.cpp\",\n";
    try checkUnits(a, &.{ "src/allocator.cpp", "src/added.cpp", "src/meshoptimizer.h" }, build, &findings);
    try std.testing.expectEqualStrings("  src/added.cpp: vendored, but build.zig does not compile it\n" ++
        "  src/gone.cpp: build.zig compiles it, but it is not vendored\n", findings.items);
}
