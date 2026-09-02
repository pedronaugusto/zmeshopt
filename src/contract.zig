//! Comptime contracts shared by the idiomatic layer.
//!
//! Every wrapper that takes a `[]const V` vertex stream funnels through these,
//! so the rules the C API states in prose — "positions must have a float3 in
//! the first 12 bytes", "stride must be a multiple of 4" — fail compilation
//! instead of corrupting a run.

const std = @import("std");

/// A vertex type whose first `leading_floats * 4` bytes are the floats the
/// C function reads; the stride is `@sizeOf(V)`. Data whose float stream does
/// not lead the vertex layout can always call the raw externs under `c`.
pub fn checkVertex(comptime V: type, comptime leading_floats: usize) void {
    comptime {
        if (@sizeOf(V) < leading_floats * @sizeOf(f32)) @compileError("zmeshopt: " ++ @typeName(V) ++ " is smaller than the " ++
            "leading floats this function reads from each vertex");
        if (@sizeOf(V) % 4 != 0) @compileError("zmeshopt: " ++ @typeName(V) ++ "'s size is not a multiple of 4, " ++
            "which meshoptimizer requires of every vertex stride");
        if (@alignOf(V) < @alignOf(f32)) @compileError("zmeshopt: " ++ @typeName(V) ++ " is under-aligned for the f32 " ++
            "reads meshoptimizer performs on it");
    }
}

/// The leading-float3 pointer of a checked vertex stream.
pub fn floatPtr(comptime V: type, vertices: []const V) [*]const f32 {
    return @ptrCast(@alignCast(vertices.ptr));
}

/// Mutable variant of `floatPtr`, for the in-place update entry points.
pub fn floatPtrMut(comptime V: type, vertices: []V) [*]f32 {
    return @ptrCast(@alignCast(vertices.ptr));
}
