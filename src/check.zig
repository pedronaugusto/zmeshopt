//! The preconditions the idiomatic layer holds before it calls upstream,
//! checked in every build. Upstream asserts each one, and with `NDEBUG` a
//! violation is a heap write or a wrong answer, so none may rest on
//! `std.debug.assert`.

const std = @import("std");

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
