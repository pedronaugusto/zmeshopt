//! What a refusal leaves on the caller's `Failure`: the call that refused
//! and why. The decoders read bytes from outside the program, and the error
//! alone does not say which header, length or tail upstream refused.

const std = @import("std");
const aegis = @import("aegis");
const check = @import("check.zig");

/// The call a refusal names: upstream's entry point without `meshopt_`, in
/// snake case.
pub const Call = enum {
    decode_index_buffer,
    decode_index_sequence,
    decode_meshlet,
    decode_meshlet_raw,
    decode_vertex_buffer,
};

/// Why the call refused. The last three are upstream's decoder results
/// (`indexcodec.cpp:386-394`, `vertexcodec.cpp:1828-1869`,
/// `meshletcodec.cpp:366-373`); the rest are refused before upstream runs.
pub const Reason = enum {
    not_triangles,
    buffer_too_small,
    length_mismatch,
    out_of_range,
    /// Upstream's -1: a header that is not this codec's, or a version newer
    /// than this decoder reads.
    header,
    /// Upstream's -2: the bytes end before the encoding does.
    truncated,
    /// Upstream's -3: the encoding does not end where the bytes do.
    mismatched_end,
};

/// One refusal.
pub const Frame = struct {
    pub const aegis_public_frame = true;
    call: Call,
    reason: Reason,
};

/// What refused, oldest first. A call that refuses pushes one frame; four
/// are kept, and a fifth sets `truncated`.
pub const Failure = aegis.err.Context(Frame, 4);

/// Encoded bytes from outside the program, which every decoder takes.
pub const Encoded = aegis.input.Untrusted([]const u8);

pub const DecodeError = check.Error || error{Malformed};

/// `precondition`'s refusal with a frame naming `call` and the check.
pub fn held(failure: *Failure, call: Call, precondition: check.Error!void) check.Error!void {
    precondition catch |e| {
        failure.push(.{ .call = call, .reason = switch (e) {
            error.NotTriangles => .not_triangles,
            error.BufferTooSmall => .buffer_too_small,
            error.LengthMismatch => .length_mismatch,
            error.OutOfRange => .out_of_range,
        } });
        return e;
    };
}

/// Nothing for upstream's 0; otherwise a frame naming `call` and the code,
/// and `error.Malformed`.
pub fn decoded(failure: *Failure, call: Call, result: c_int) error{Malformed}!void {
    const reason: Reason = switch (result) {
        0 => return,
        -1 => .header,
        -2 => .truncated,
        -3 => .mismatched_end,
        else => aegis.assert.never("upstream's decoders return 0, -1, -2 or -3"),
    };
    failure.push(.{ .call = call, .reason = reason });
    return error.Malformed;
}

test decoded {
    var failure: Failure = .{};
    try decoded(&failure, .decode_vertex_buffer, 0);
    try std.testing.expectEqual(@as(usize, 0), failure.frames().len);
    try std.testing.expectError(error.Malformed, decoded(&failure, .decode_vertex_buffer, -2));
    try std.testing.expectEqual(Frame{ .call = .decode_vertex_buffer, .reason = .truncated }, failure.frames()[0]);
}

test held {
    var failure: Failure = .{};
    try std.testing.expectError(error.NotTriangles, held(&failure, .decode_index_buffer, check.triangles(4)));
    try std.testing.expectEqual(Frame{ .call = .decode_index_buffer, .reason = .not_triangles }, failure.frames()[0]);
}
