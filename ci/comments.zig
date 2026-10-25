//! Refuses comment blocks that have stopped being reference documentation:
//! a block longer than its cap, or a comment line in the narrative register.
//! Length per block, not density. Only the package's own sources: the
//! vendored tree is upstream's to comment.
const std = @import("std");
const Io = std.Io;

/// Comment lines directly above one declaration.
const max_declaration = 6;
/// The block at the top of a file, or one headed by a `//====` banner, which
/// heads a whole section and holds the conventions covering everything below.
const max_header = 14;
/// The largest source file read.
const max_file_bytes = 1 << 20;

/// The directories checked, each read one level deep, and the files.
const directories = [_][]const u8{ "src", "src/c", "src/testing", "examples", "tests", "bench", "ci" };
const files = [_][]const u8{"build.zig"};

/// Phrases that read as a person talking, not as documentation. Matched
/// case-insensitively, on word boundaries.
const narrative = [_][]const u8{
    "we",             "our",          "note that",        "worth stating", "worth noting",    "worth saying",
    "used to be",     "they used to", "it used to",       "the reason is", "the reason it",   "which is why",
    "that is why",    "turns out",    "in practice this", "do not be",     "you might think", "you might expect",
    "it is tempting",
};

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var findings: std.ArrayList(u8) = .empty;
    const cwd = Io.Dir.cwd();
    for (directories) |path| {
        var dir = cwd.openDir(io, path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |e| return e,
        };
        defer dir.close(io);
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .file or !checked(entry.name)) continue;
            const name = try a.print("{s}/{s}", .{ path, entry.name });
            try check(a, name, try dir.readFileAlloc(io, entry.name, a, .limited(max_file_bytes)), &findings);
        }
    }
    for (files) |name| try check(a, name, try cwd.readFileAlloc(io, name, a, .limited(max_file_bytes)), &findings);
    if (findings.items.len == 0) return 0;
    var buffer: [4096]u8 = undefined;
    var stderr = Io.File.stderr().writer(io, &buffer);
    try stderr.interface.writeAll(findings.items);
    try stderr.interface.flush();
    return 1;
}

/// Whether a file of this name is one of the package's own sources.
fn checked(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".zig") or std.mem.endsWith(u8, name, ".c") or std.mem.endsWith(u8, name, ".h");
}

/// Appends a line to `findings` for every over-long block and narrative line of `text`.
fn check(a: std.mem.Allocator, name: []const u8, text: []const u8, findings: *std.ArrayList(u8)) !void {
    var run: usize = 0;
    var start: usize = 0;
    var banner = false;
    var first = true;
    var number: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        number += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (isComment(line)) {
            if (run == 0) {
                start = number;
                banner = false;
            }
            if (std.mem.startsWith(u8, line, "//====")) banner = true;
            run += 1;
            if (narrativePhrase(line)) |phrase| try findings.print(a, "{s}:{d}: narrative register (\"{s}\")\n", .{ name, number, phrase });
            continue;
        }
        if (run > 0) {
            const cap: usize = if ((first and start <= 3) or banner) max_header else max_declaration;
            if (run > cap) try findings.print(a, "{s}:{d}: {d} comment lines in one block (max {d})\n", .{ name, start, run, cap });
        }
        first = false;
        run = 0;
    }
}

fn isComment(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "//") or std.mem.startsWith(u8, line, "/*") or std.mem.startsWith(u8, line, "*");
}

/// The first narrative phrase in a comment line, or null.
fn narrativePhrase(line: []const u8) ?[]const u8 {
    for (narrative) |phrase| {
        var from: usize = 0;
        while (std.ascii.findIgnoreCasePos(line, from, phrase)) |at| : (from = at + 1) {
            const before = at == 0 or !std.ascii.isAlphanumeric(line[at - 1]);
            const end = at + phrase.len;
            const after = end == line.len or !std.ascii.isAlphanumeric(line[end]);
            if (before and after) return phrase;
        }
    }
    return null;
}

test "a declaration's block over six lines is refused, a file header's is not" {
    const a = std.testing.allocator;
    var findings: std.ArrayList(u8) = .empty;
    defer findings.deinit(a);
    const header = "//! 1\n//! 2\n//! 3\n//! 4\n//! 5\n//! 6\n//! 7\nconst x = 1;\n";
    try check(a, "f.zig", header, &findings);
    try std.testing.expectEqual(@as(usize, 0), findings.items.len);
    const long = "const y = 0;\n/// 1\n/// 2\n/// 3\n/// 4\n/// 5\n/// 6\n/// 7\nconst x = 1;\n";
    try check(a, "f.zig", long, &findings);
    try std.testing.expectEqualStrings("f.zig:2: 7 comment lines in one block (max 6)\n", findings.items);
}

test "a banner heads a section and takes the header's cap" {
    const a = std.testing.allocator;
    var findings: std.ArrayList(u8) = .empty;
    defer findings.deinit(a);
    const text = "const y = 0;\n//====\n// 1\n// 2\n// 3\n// 4\n// 5\n// 6\n//====\nconst x = 1;\n";
    try check(a, "f.zig", text, &findings);
    try std.testing.expectEqual(@as(usize, 0), findings.items.len);
}

test "the narrative register is matched on word boundaries" {
    try std.testing.expectEqualStrings("we", narrativePhrase("// so We call it").?);
    try std.testing.expect(narrativePhrase("// weights and ours are fine") == null);
    try std.testing.expectEqualStrings("which is why", narrativePhrase("/// Which is why it fails").?);
}
