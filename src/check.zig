//! The preconditions the idiomatic layer holds before it calls upstream,
//! checked in every build. Upstream asserts each one, and with `NDEBUG` a
//! violation is a heap write or a wrong answer, so none may rest on
//! `std.debug.assert`.

const std = @import("std");
const aegis = @import("aegis");

pub const Error = error{
    /// An index buffer whose length is not a whole number of triangles.
    NotTriangles,
    /// A destination shorter than the result it must hold.
    BufferTooSmall,
    /// Two slices whose lengths the contract ties together differ.
    LengthMismatch,
    /// A parameter outside the range upstream accepts.
    OutOfRange,
};

/// `index_count` indices make whole triangles.
pub fn triangles(index_count: usize) Error!void {
    if (index_count % 3 != 0) return error.NotTriangles;
}

/// A destination of `have` elements holds the `need` the result takes.
pub fn room(have: usize, need: usize) Error!void {
    if (have < need) return error.BufferTooSmall;
}

/// Two lengths the contract ties together agree.
pub fn same(a: usize, b: usize) Error!void {
    if (a != b) return error.LengthMismatch;
}

/// A parameter upstream bounds is inside its range.
pub fn range(inside: bool) Error!void {
    if (!inside) return error.OutOfRange;
}

/// The position of the first of `indices` at or past `count`, or null.
/// Upstream reads or writes at every index and only asserts the bound.
pub fn firstPast(indices: anytype, count: usize) ?usize {
    return firstPastExcept(indices, count, null);
}

/// `firstPast` over a remap table, skipping upstream's mark for an entry
/// that maps nowhere (`~0`).
pub fn firstRemapPast(remap: []const u32, count: usize) ?usize {
    return firstPastExcept(remap, count, std.math.maxInt(u32));
}

fn firstPastExcept(indices: anytype, count: usize, comptime unused: ?u32) ?usize {
    const Index = @typeInfo(@TypeOf(indices)).pointer.child;
    // The largest first, in a loop that vectorizes; the position is looked
    // for only when there is a refusal to name.
    var largest: Index = 0;
    for (indices) |index| largest = @max(largest, if (unused != null and index == unused.?) 0 else index);
    if (indices.len == 0 or largest < count) return null;
    for (indices, 0..) |index, at| {
        if (unused != null and index == unused.?) continue;
        if (index >= count) return at;
    }
    aegis.assert.never("the largest index is at or past `count`, so some index is");
}

test triangles {
    try triangles(6);
    try std.testing.expectError(error.NotTriangles, triangles(4));
}

test room {
    try room(3, 3);
    try std.testing.expectError(error.BufferTooSmall, room(2, 3));
}

test same {
    try same(3, 3);
    try std.testing.expectError(error.LengthMismatch, same(3, 4));
}

test range {
    try range(true);
    try std.testing.expectError(error.OutOfRange, range(false));
}

test firstPast {
    try std.testing.expectEqual(@as(?usize, null), firstPast(@as([]const u32, &.{ 0, 2, 1 }), 3));
    try std.testing.expectEqual(@as(?usize, 1), firstPast(@as([]const u32, &.{ 0, 3, 4 }), 3));
    try std.testing.expectEqual(@as(?usize, 2), firstPast(@as([]const u8, &.{ 1, 0, 9 }), 2));
    try std.testing.expectEqual(@as(?usize, null), firstPast(@as([]const u32, &.{}), 0));
    try std.testing.expectEqual(@as(?usize, 0), firstPast(@as([]const u32, &.{0}), 0));
}

test firstRemapPast {
    const unused = std.math.maxInt(u32);
    try std.testing.expectEqual(@as(?usize, null), firstRemapPast(&.{ 1, unused, 0 }, 2));
    try std.testing.expectEqual(@as(?usize, 2), firstRemapPast(&.{ 1, unused, 2 }, 2));
}
