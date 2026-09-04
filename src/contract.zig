//! Comptime contracts shared by the idiomatic layer.
//!
//! Every wrapper that takes a `[]const V` vertex stream funnels through these,
//! so the rules the C API states in prose — "positions must have a float3 in
//! the first 12 bytes", "stride must be a multiple of 4", "stride must not
//! exceed 256 bytes" — fail compilation instead of corrupting a run.

const std = @import("std");

/// A vertex type whose first `leading_floats * 4` bytes are the floats the
/// C function reads; the stride is `@sizeOf(V)`. Data whose float stream does
/// not lead the vertex layout can always call the raw externs under `c`.
pub fn checkVertex(comptime V: type, comptime leading_floats: usize) void {
    comptime {
        if (@sizeOf(V) < leading_floats * @sizeOf(f32)) @compileError("zmeshopt: " ++ @typeName(V) ++ " is smaller than the " ++
            "leading floats this function reads from each vertex");
        if (@sizeOf(V) > 256) @compileError("zmeshopt: " ++ @typeName(V) ++ " is larger than the 256-byte stride " ++
            "ceiling every position- and vertex-taking meshoptimizer entry point asserts");
        if (@sizeOf(V) % 4 != 0) @compileError("zmeshopt: " ++ @typeName(V) ++ "'s size is not a multiple of 4, " ++
            "which meshoptimizer requires of every vertex stride");
        if (@alignOf(V) < @alignOf(f32)) @compileError("zmeshopt: " ++ @typeName(V) ++ " is under-aligned for the f32 " ++
            "reads meshoptimizer performs on it");
    }
}

/// A vertex type upstream takes as opaque bytes rather than floats: it hashes
/// or copies `@sizeOf(V)` of each vertex and bounds that at both ends
/// (indexgenerator.cpp:395). No stride rule applies — these entry points read
/// whole vertices, not a leading float run.
pub fn checkVertexSize(comptime V: type) void {
    comptime if (@sizeOf(V) == 0 or @sizeOf(V) > 256) @compileError("zmeshopt: " ++ @typeName(V) ++ "'s size is outside " ++
        "the 1 to 256 bytes meshoptimizer reads from each vertex");
}

/// The leading-float3 pointer of a checked vertex stream.
pub fn floatPtr(comptime V: type, vertices: []const V) [*]const f32 {
    return @ptrCast(@alignCast(vertices.ptr));
}

/// Mutable variant of `floatPtr`, for the in-place update entry points.
pub fn floatPtrMut(comptime V: type, vertices: []V) [*]f32 {
    return @ptrCast(@alignCast(vertices.ptr));
}

test checkVertex {
    // Both ceilings are inclusive: a 256-byte vertex is the largest one
    // meshoptimizer accepts, so it must still compile.
    checkVertex([64]f32, 3);
    checkVertex([3]f32, 3);
    checkVertex([2]f32, 2);
    checkVertexSize([256]u8);
    checkVertexSize(u8);
}
