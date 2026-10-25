//! The Zig surface covers the C surface: every extern src/c/ declares has a
//! caller in the idiomatic layer or a reason in `excused`, and every excuse
//! names an extern that exists and has none. Upstream's C++-only inline
//! helpers have no symbol to bind, so each needs a Zig reimplementation in
//! `reimplemented`, with the list read from the header. Whether src/c/ binds
//! all of the header is src/testing/abi.zig's question, decided at compile time.
const std = @import("std");
const Io = std.Io;

/// Externs the idiomatic layer leaves to `zmeshopt.c`, each with its reason.
const excused = [_]struct { name: []const u8, reason: []const u8 }{
    .{ .name = "meshopt_simplify", .reason = "rerouted through zmeshopt_shim_simplify in src/abi_shim.c" },
    .{ .name = "meshopt_simplifyWithAttributes", .reason = "rerouted through zmeshopt_shim_simplifyWithAttributes in src/abi_shim.c" },
    .{ .name = "meshopt_simplifyWithUpdate", .reason = "rerouted through zmeshopt_shim_simplifyWithUpdate in src/abi_shim.c" },
    .{ .name = "meshopt_simplifySloppy", .reason = "rerouted through zmeshopt_shim_simplifySloppy in src/abi_shim.c" },
    .{ .name = "meshopt_buildMeshlets", .reason = "rerouted through zmeshopt_shim_buildMeshlets in src/abi_shim.c" },
    .{ .name = "meshopt_buildMeshletsFlex", .reason = "rerouted through zmeshopt_shim_buildMeshletsFlex in src/abi_shim.c" },
    .{ .name = "meshopt_buildMeshletsSpatial", .reason = "rerouted through zmeshopt_shim_buildMeshletsSpatial in src/abi_shim.c" },
    .{ .name = "meshopt_opacityMapMeasure", .reason = "rerouted through zmeshopt_shim_opacityMapMeasure in src/abi_shim.c" },
    .{ .name = "meshopt_analyzeCoverage", .reason = "rerouted through zmeshopt_shim_analyzeCoverage in src/abi_shim.c" },
};

/// The header's C++-only inline helpers (`#ifdef __cplusplus`, so a C
/// consumer never had them either), and the Zig declaration and test that
/// reimplement each.
const reimplemented = [_]Reimplementation{
    .{ .name = "meshopt_quantizeUnorm", .file = "src/quantize.zig", .decl = "quantizeUnorm", .@"test" = "quantizeUnorm" },
    .{ .name = "meshopt_quantizeSnorm", .file = "src/quantize.zig", .decl = "quantizeSnorm", .@"test" = "quantizeSnorm" },
};

const Reimplementation = struct { name: []const u8, file: []const u8, decl: []const u8, @"test": []const u8 };

const header = "libs/meshoptimizer/src/meshoptimizer.h";
/// Where the header's C++ template wrappers start: they only re-spell
/// functions the C ABI already exports, so the inline scan stops there.
const wrappers = "MESHOPTIMIZER_NO_WRAPPERS";
/// The largest source file read.
const max_file_bytes = 1 << 20;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const cwd = Io.Dir.cwd();
    var declared: Names = .empty;
    var called: Names = .empty;
    try collect(a, io, "src/c", .declared, &declared);
    // src/c.zig and src/c/ are the declarations; src/testing/ is the oracle.
    try collect(a, io, "src", .called, &called);
    var inline_only: Names = .empty;
    try inlineHelpers(a, try cwd.readFileAlloc(io, header, a, .limited(max_file_bytes)), &inline_only);
    var findings: std.ArrayList(u8) = .empty;
    try judge(a, declared, called, &excused, &findings);
    try ledger(a, inline_only, &reimplemented, &findings);
    for (reimplemented) |row| {
        const text = cwd.readFileAlloc(io, row.file, a, .limited(max_file_bytes)) catch |err| switch (err) {
            error.FileNotFound => {
                try findings.print(a, "{s}: {s} does not exist\n", .{ row.name, row.file });
                continue;
            },
            else => |e| return e,
        };
        try reimplementation(a, row, text, &findings);
    }
    if (findings.items.len == 0) return 0;
    var buffer: [4096]u8 = undefined;
    var stderr = Io.File.stderr().writer(io, &buffer);
    try stderr.interface.writeAll(findings.items);
    try stderr.interface.flush();
    return 1;
}

const Names = std.array_hash_map.String(void);
const Kind = enum { declared, called };

/// The `meshopt_` names of every `.zig` file directly in `path`: the externs
/// it declares, or the ones its code (comments stripped) names.
fn collect(a: std.mem.Allocator, io: Io, path: []const u8, kind: Kind, names: *Names) !void {
    var dir = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
        if (kind == .called and std.mem.eql(u8, entry.name, "c.zig")) continue;
        const text = try dir.readFileAlloc(io, entry.name, a, .limited(max_file_bytes));
        switch (kind) {
            .declared => try externs(a, text, names),
            .called => try mentions(a, text, names),
        }
    }
}

/// Every `pub extern fn meshopt_…` of `text`.
fn externs(a: std.mem.Allocator, text: []const u8, names: *Names) !void {
    const prefix = "pub extern fn ";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const rest = line[prefix.len..];
        if (std.mem.startsWith(u8, rest, "meshopt_")) try names.put(a, identifier(rest), {});
    }
}

/// Every `meshopt_…` identifier in the code of `text`, comments excluded: a
/// doc comment naming an entry point does not call it. One inside a longer
/// identifier (`zmeshopt_shim_simplify`) is not that name.
fn mentions(a: std.mem.Allocator, text: []const u8, names: *Names) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const code = if (std.mem.find(u8, line, "//")) |at| line[0..at] else line;
        var from: usize = 0;
        while (std.mem.findPos(u8, code, from, "meshopt_")) |at| {
            const name = identifier(code[at..]);
            from = at + name.len;
            if (at > 0 and (std.ascii.isAlphanumeric(code[at - 1]) or code[at - 1] == '_')) continue;
            try names.put(a, name, {});
        }
    }
}

/// The identifier `text` starts with.
fn identifier(text: []const u8) []const u8 {
    var end: usize = 0;
    while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1;
    return text[0..end];
}

/// The `meshopt_` name of every line starting `inline` before the template
/// wrappers.
fn inlineHelpers(a: std.mem.Allocator, text: []const u8, names: *Names) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.find(u8, line, wrappers) != null) return;
        if (!std.mem.startsWith(u8, line, "inline")) continue;
        const at = std.mem.find(u8, line, "meshopt_") orelse continue;
        try names.put(a, identifier(line[at..]), {});
    }
}

/// Appends a line for every extern with no caller and no excuse, and for
/// every excuse that names an extern which is called or does not exist.
fn judge(a: std.mem.Allocator, declared: Names, called: Names, excuses: []const @TypeOf(excused[0]), findings: *std.ArrayList(u8)) !void {
    for (declared.keys()) |name| {
        if (called.contains(name) or isExcused(excuses, name)) continue;
        try findings.print(a, "{s}: an extern with no idiomatic caller and no excuse in ci/coverage.zig\n", .{name});
    }
    for (excuses) |e| {
        if (!declared.contains(e.name)) try findings.print(a, "{s}: excused, but src/c/ declares no such extern\n", .{e.name});
        if (called.contains(e.name)) try findings.print(a, "{s}: excused, but the idiomatic layer calls it\n", .{e.name});
    }
}

fn isExcused(excuses: []const @TypeOf(excused[0]), name: []const u8) bool {
    for (excuses) |e| if (std.mem.eql(u8, e.name, name)) return true;
    return false;
}

/// Appends a line for every inline helper with no row, and every row for a
/// helper the header no longer declares inline-only.
fn ledger(a: std.mem.Allocator, inline_only: Names, rows: []const Reimplementation, findings: *std.ArrayList(u8)) !void {
    for (inline_only.keys()) |name| {
        for (rows) |row| {
            if (std.mem.eql(u8, row.name, name)) break;
        } else try findings.print(a, "{s}: a C++-only inline helper with no Zig reimplementation on record in ci/coverage.zig\n", .{name});
    }
    for (rows) |row| {
        if (!inline_only.contains(row.name)) try findings.print(a, "{s}: on record as reimplemented, but the header declares no such inline helper\n", .{row.name});
    }
}

/// Appends a line when `text`, the row's file, declares no `pub fn` of the
/// row's name or has no test of the row's name.
fn reimplementation(a: std.mem.Allocator, row: Reimplementation, text: []const u8, findings: *std.ArrayList(u8)) !void {
    if (!hasLine(text, try a.print("pub fn {s}(", .{row.decl}))) try findings.print(a, "{s}: {s} declares no pub fn {s}\n", .{ row.name, row.file, row.decl });
    if (!hasLine(text, try a.print("test {s} {{", .{row.@"test"}))) try findings.print(a, "{s}: {s} has no test named {s}\n", .{ row.name, row.file, row.@"test" });
}

fn hasLine(text: []const u8, start: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, start)) return true;
    return false;
}

test "an extern needs a caller or an excuse, and an excuse needs a stranded extern" {
    const a = std.testing.allocator;
    var declared: Names = .empty;
    defer declared.deinit(a);
    var called: Names = .empty;
    defer called.deinit(a);
    try externs(a, "pub extern fn meshopt_stripify(x: u8) u8;\npub extern fn meshopt_stripifyBound() void;\n", &declared);
    // The idiomatic caller of meshopt_stripifyBound removed: named in a comment only.
    try mentions(a, "    return c.meshopt_stripify(x); // meshopt_stripifyBound is named here only\n", &called);
    var findings: std.ArrayList(u8) = .empty;
    defer findings.deinit(a);
    try judge(a, declared, called, &.{}, &findings);
    try std.testing.expectEqualStrings("meshopt_stripifyBound: an extern with no idiomatic caller and no excuse in ci/coverage.zig\n", findings.items);
}

test "an excuse for an extern the layer calls is refused" {
    const a = std.testing.allocator;
    var declared: Names = .empty;
    defer declared.deinit(a);
    var called: Names = .empty;
    defer called.deinit(a);
    try externs(a, "pub extern fn meshopt_stripifyBound(index_count: usize) usize;\n", &declared);
    try mentions(a, "    return c.meshopt_stripifyBound(index_count);\n", &called);
    var findings: std.ArrayList(u8) = .empty;
    defer findings.deinit(a);
    try judge(a, declared, called, &.{.{ .name = "meshopt_stripifyBound", .reason = "bound size helper" }}, &findings);
    try std.testing.expectEqualStrings("meshopt_stripifyBound: excused, but the idiomatic layer calls it\n", findings.items);
}

test "a name inside a longer identifier is not a call" {
    const a = std.testing.allocator;
    var called: Names = .empty;
    defer called.deinit(a);
    try mentions(a, "    return shim.zmeshopt_shim_simplify(x);\n", &called);
    try std.testing.expectEqual(@as(usize, 0), called.count());
}

test "an inline helper with no row, or a row for none, is refused" {
    const a = std.testing.allocator;
    var inline_only: Names = .empty;
    defer inline_only.deinit(a);
    try inlineHelpers(a, "inline int meshopt_quantizeUnorm(float v, int N);\ninline int meshopt_quantizeSnorm(float v, int N);\n" ++
        "#if defined(__cplusplus) && !defined(MESHOPTIMIZER_NO_WRAPPERS)\ninline size_t meshopt_generateVertexRemap(void);\n", &inline_only);
    try std.testing.expectEqual(@as(usize, 2), inline_only.count());
    var findings: std.ArrayList(u8) = .empty;
    defer findings.deinit(a);
    // The meshopt_quantizeUnorm row deleted.
    try ledger(a, inline_only, reimplemented[1..], &findings);
    try std.testing.expectEqualStrings("meshopt_quantizeUnorm: a C++-only inline helper with no Zig reimplementation on record in ci/coverage.zig\n", findings.items);
}

test "a row naming a declaration or a test that does not exist is refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var findings: std.ArrayList(u8) = .empty;
    const row: Reimplementation = .{ .name = "meshopt_quantizeSnorm", .file = "src/quantize.zig", .decl = "quantizeSnorm", .@"test" = "quantizeSnormAll" };
    try reimplementation(a, row, "pub fn quantizeSnorm(v: f32, bits: u5) i32 {\n}\ntest quantizeSnorm {\n}\n", &findings);
    try std.testing.expectEqualStrings("meshopt_quantizeSnorm: src/quantize.zig has no test named quantizeSnormAll\n", findings.items);
}
