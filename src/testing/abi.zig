//! Comptime cross-check: the hand-written externs in `src/c/` against the
//! vendored `meshoptimizer.h`, and `src/shim.zig` against `src/abi_shim.h`,
//! translated by the build for the test module alone as `meshoptimizer_h`
//! (the shipped module stays translate-c-free), compared per declaration via
//! reflection; an unclassified declaration errors at compile time.
//!
//! Naming conventions are load-bearing: extern functions carry the C name
//! itself, type `Foo` pairs with `meshopt_Foo`, and a mask or enum whose C
//! enumerators are loose constants carries an `upstream_prefix` decl that,
//! with the PascalCased field name, reconstructs each enumerator. The
//! reverse sweep is the completeness gate: every header function must be
//! bound. Pointees compare by size and alignment only; function pointers
//! compare deep.

const std = @import("std");
const c = @import("../c.zig");
const shim = @import("../shim.zig");

const h = @import("meshoptimizer_h");

/// What a comparison found: null where the two sides agree, else what
/// drifted, naming both sides. Every comparison returns one, so the drift
/// tests below can hold each to the message it gives; the sweep test makes
/// a drift a compile error.
const Drift = ?[]const u8;

fn num(comptime value: anytype) []const u8 {
    return std.fmt.comptimePrint("{d}", .{value});
}

//=============================================================================
// Name conventions, computed rather than tabulated
//=============================================================================

/// `lock_border` -> `LockBorder`, `shared_vector` -> `SharedVector`.
fn pascal(comptime name: []const u8) []const u8 {
    comptime {
        var out: []const u8 = "";
        var upper_next = true;
        for (name) |ch| {
            if (ch == '_') {
                upper_next = true;
            } else if (upper_next) {
                out = out ++ [_]u8{std.ascii.toUpper(ch)};
                upper_next = false;
            } else {
                out = out ++ [_]u8{ch};
            }
        }
        return out;
    }
}

fn typeCName(comptime name: []const u8) []const u8 {
    return "meshopt_" ++ name;
}

//=============================================================================
// Comparison primitives
//=============================================================================

/// A drift when `Header` does not declare `name`, which `because` expects.
fn missing(comptime Header: type, comptime name: []const u8, comptime because: []const u8) Drift {
    if (@hasDecl(Header, name)) return null;
    return "`" ++ because ++ "` expects `" ++ name ++ "` from the C headers, which do not declare it";
}

fn sameSizeAndAlign(comptime what: []const u8, comptime Ours: type, comptime Theirs: type) Drift {
    if (@sizeOf(Ours) != @sizeOf(Theirs)) {
        return what ++ " is " ++ num(@sizeOf(Ours)) ++ " bytes on the Zig side but " ++
            num(@sizeOf(Theirs)) ++ " in the C header";
    }
    if (@alignOf(Ours) != @alignOf(Theirs)) {
        return what ++ " has alignment " ++ num(@alignOf(Ours)) ++ " on the Zig side but " ++
            num(@alignOf(Theirs)) ++ " in the C header";
    }
    return null;
}

/// The scalar a type really is at the boundary, with the Zig-side wrapper
/// removed. translate-c renders every C enum as a plain integer; this side
/// keeps enums as `enum(...)` and masks as `packed struct`, so each is
/// resolved to its backing integer first: an `enum(u32)` against a C `int`
/// enum is a real signedness disagreement, and this is what surfaces it.
fn ScalarIdentity(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .@"enum" => |e| e.tag_type,
        .@"struct" => |st| st.backing_integer orelse T,
        else => T,
    };
}

/// A `*const fn`/`?*const fn` unwrapped to the fn type, or null when the
/// type is not a function pointer. translate-c makes every C function
/// pointer optional; both sides unwrap the same way.
fn fnPointee(comptime T: type) ?type {
    const Base = switch (@typeInfo(T)) {
        .optional => |o| o.child,
        else => T,
    };
    if (@typeInfo(Base) == .pointer and @typeInfo(@typeInfo(Base).pointer.child) == .@"fn") {
        return @typeInfo(Base).pointer.child;
    }
    return null;
}

/// Size and alignment, plus the scalar identity they do not carry: a
/// `size_t` declared `isize` or a `float` declared `u32` passes both and
/// silently reinterprets every value. Function pointers on both sides
/// compare signature-deep: upstream names no callback typedefs, so this is
/// where a callback's shape is held to the header.
fn sameScalar(comptime what: []const u8, comptime Ours: type, comptime Theirs: type) Drift {
    if (sameSizeAndAlign(what, Ours, Theirs)) |d| return d;
    if (fnPointee(Ours)) |OursFn| {
        const TheirsFn = fnPointee(Theirs) orelse
            return what ++ " is a function pointer on the Zig side but not in the C header";
        return checkFnType(what ++ " (callback)", OursFn, TheirsFn);
    }
    if (fnPointee(Theirs) != null) return what ++ " is a function pointer in the C header but not on the Zig side";
    const oi = @typeInfo(ScalarIdentity(Ours));
    const ti = @typeInfo(ScalarIdentity(Theirs));
    // Signedness, EXCEPT across an enum or mask: C leaves an enum's
    // underlying type to the implementation (clang and gcc pick unsigned
    // when no enumerator is negative, MSVC uses `int`). Skipping it is sound
    // only while every enumerator is non-negative, which `checkEnumValues`
    // holds.
    const across_enum = ScalarIdentity(Ours) != Ours or ScalarIdentity(Theirs) != Theirs;
    if (!across_enum and oi == .int and ti == .int and oi.int.signedness != ti.int.signedness) {
        return what ++ " is " ++ @tagName(oi.int.signedness) ++ " on the Zig side but " ++
            @tagName(ti.int.signedness) ++ " in the C header";
    }
    if ((oi == .int) != (ti == .int) or (oi == .float) != (ti == .float)) {
        return what ++ " is a " ++ @tagName(oi) ++ " on the Zig side but a " ++
            @tagName(ti) ++ " in the C header";
    }
    return null;
}

/// Compares two function types by what translate-c preserves: how many
/// parameters there are, how each is passed, and whether it is variadic.
fn checkFnType(comptime what: []const u8, comptime Ours: type, comptime Theirs: type) Drift {
    const ours = @typeInfo(Ours).@"fn";
    const theirs = @typeInfo(Theirs).@"fn";
    if (ours.param_types.len != theirs.param_types.len) {
        return what ++ " takes " ++ num(ours.param_types.len) ++ " parameters on the Zig side but " ++
            num(theirs.param_types.len) ++ " in the C header";
    }
    if (ours.attrs.varargs != theirs.attrs.varargs) return what ++ " is variadic on one side of the boundary only";
    inline for (ours.param_types, theirs.param_types, 0..) |op, tp, i| {
        const OP = op orelse return what ++ " has an untyped parameter on the Zig side";
        const TP = tp orelse return what ++ " has an untyped parameter in the C header";
        if (sameScalar(what ++ " parameter " ++ num(i), OP, TP)) |d| return d;
    }
    const OR = ours.return_type orelse return what ++ " has no return type on the Zig side";
    const TR = theirs.return_type orelse return what ++ " has no return type in the C header";
    return sameScalar(what ++ " return value", OR, TR);
}

//=============================================================================
// Hazard shapes
//
// Two caller shapes were measured miscompiled by Zig 0.16.0 (hosted CI,
// 2026-09-02): a float argument after more than 6 integer-class parameters,
// and a small all-float struct returned by value. meshoptimizer's ABI is
// upstream's and has both, so the idiomatic layer crosses those functions
// through `src/abi_shim.c`. The counts are pinned below, so a re-vendor
// that adds one is a conscious act of extending the shim.
//=============================================================================

const max_int_class_params_before_float = 6;

/// True when `Fn` passes a float after more than 6 integer-class parameters.
fn hasLateFloat(comptime Fn: type) bool {
    comptime {
        var int_class: usize = 0;
        for (@typeInfo(Fn).@"fn".param_types) |param| {
            const P = param orelse continue;
            switch (@typeInfo(ScalarIdentity(P))) {
                .float, .vector => if (int_class > max_int_class_params_before_float) return true,
                else => int_class += 1,
            }
        }
        return false;
    }
}

/// True when `Fn` returns by value a struct of at most 16 bytes holding
/// only floats, the shape measured miscompiled; a larger or mixed struct
/// returns through memory or integer registers and is not that shape.
fn hasFloatAggregateReturn(comptime Fn: type) bool {
    const R = @typeInfo(Fn).@"fn".return_type orelse return false;
    if (@typeInfo(R) != .@"struct" or @sizeOf(R) > 16) return false;
    for (@typeInfo(R).@"struct".field_types) |F| {
        const Element = switch (@typeInfo(F)) {
            .array => |a| a.child,
            else => F,
        };
        if (@typeInfo(Element) != .float) return false;
    }
    return true;
}

//=============================================================================
// Struct, enum and mask comparisons
//=============================================================================

/// Struct layout, compared field by NAME rather than by position: two
/// same-sized adjacent fields swapping places leave the sequence of offsets
/// identical, so a positional comparison passes a swap that silently
/// reinterprets both; pairing each name with its own offset catches it.
fn checkStructLayout(comptime what: []const u8, comptime Ours: type, comptime Theirs: type) Drift {
    if (sameSizeAndAlign(what, Ours, Theirs)) |d| return d;
    const ours = @typeInfo(Ours).@"struct";
    const theirs = switch (@typeInfo(Theirs)) {
        .@"struct" => |s| s,
        else => return what ++ " is a struct in src/c/ but not in the C header",
    };
    if (ours.field_names.len != theirs.field_names.len) {
        return what ++ " has " ++ num(ours.field_names.len) ++ " fields in src/c/ but " ++
            num(theirs.field_names.len) ++ " in the C header";
    }
    inline for (ours.field_names, ours.field_types) |name, Field| {
        if (!@hasField(Theirs, name)) return what ++ " has field `" ++ name ++ "` in src/c/, which the C header does not";
        if (@offsetOf(Ours, name) != @offsetOf(Theirs, name)) {
            return what ++ "." ++ name ++ " is at byte " ++ num(@offsetOf(Ours, name)) ++ " in src/c/ but " ++
                num(@offsetOf(Theirs, name)) ++ " in the C header";
        }
        if (sameScalar(what ++ "." ++ name, Field, @FieldType(Theirs, name))) |d| return d;
    }
    return null;
}

/// Enumerator values, paired by `prefix` ++ PascalCase(field). translate-c
/// flattens a C enum to an integer alias and loses which enumerators belong
/// to it; the prefix convention is what puts them back together.
fn checkEnumValues(comptime Header: type, comptime what: []const u8, comptime Ours: type, comptime prefix: []const u8) Drift {
    const info = @typeInfo(Ours).@"enum";
    inline for (info.field_names, info.field_values) |name, value| {
        const cname = prefix ++ pascal(name);
        if (missing(Header, cname, what ++ "." ++ name)) |d| return d;
        // The precondition that lets sameScalar skip signedness across an
        // enum: the underlying type is unobservable only while every
        // enumerator is non-negative.
        if (value < 0) {
            return what ++ "." ++ name ++ " is negative, which makes the enum's underlying type " ++
                "observable; C leaves that to the implementation and MSVC and clang choose differently";
        }
        if (@as(i128, @field(Header, cname)) != @as(i128, value)) {
            return what ++ "." ++ name ++ " is " ++ num(value) ++ " in src/c/ but " ++ cname ++ " is " ++
                num(@field(Header, cname)) ++ " in the C header";
        }
    }
    return null;
}

/// Bit values for a packed struct whose C counterpart is an ANONYMOUS enum
/// of bits: upstream gives the set no type name, so each bit is compared
/// against the enumerator its name reconstructs. Padding fields (leading
/// underscore) have no counterpart and are skipped.
fn checkMaskBits(comptime Header: type, comptime what: []const u8, comptime Ours: type, comptime prefix: []const u8) Drift {
    const s = @typeInfo(Ours).@"struct";
    const Backing = s.backing_integer.?;
    inline for (s.field_names, s.field_types) |name, Field| {
        if (comptime std.mem.startsWith(u8, name, "_")) continue;
        if (Field != bool) return what ++ "." ++ name ++ " is not a bool, so its bit value cannot be derived; give this mask an explicit check";
        const cname = prefix ++ pascal(name);
        if (missing(Header, cname, what ++ "." ++ name)) |d| return d;
        var one: Ours = std.mem.zeroes(Ours);
        @field(one, name) = true;
        const bit: Backing = @bitCast(one);
        if (@as(i128, @field(Header, cname)) != @as(i128, bit)) {
            return what ++ "." ++ name ++ " is bit " ++ std.fmt.comptimePrint("0x{x}", .{bit}) ++ " in src/c/ but " ++
                cname ++ " is " ++ std.fmt.comptimePrint("0x{x}", .{@field(Header, cname)}) ++ " in the C header";
        }
    }
    return null;
}

//=============================================================================
// The sweep
//=============================================================================

const Counts = struct {
    types: usize = 0,
    functions: usize = 0,
    fields: usize = 0,
    enumerators: usize = 0,
    late_float_fns: usize = 0,
    float_aggregate_return_fns: usize = 0,
};

const Swept = struct { counts: Counts = .{}, drift: Drift = null };

/// Every public declaration in `modules`, classified and compared against
/// `Header`. A declaration this does not know how to check is a drift: a
/// hole in the guard stops the build rather than counting as a pass.
fn sweepOurs(comptime modules: anytype, comptime Header: type) Swept {
    comptime {
        var n: Counts = .{};
        for (modules, 0..) |m, mi| for (@typeInfo(m).@"struct".decl_names) |name| {
            // A name an EARLIER module already declared is a re-export,
            // checked once where it is declared, and must stay the same one.
            var earlier = false;
            for (modules, 0..) |other, oi| {
                if (oi >= mi or !@hasDecl(other, name)) continue;
                if (@TypeOf(@field(other, name)) == type and @TypeOf(@field(m, name)) == type and
                    @field(other, name) != @field(m, name))
                {
                    return .{ .drift = "`" ++ name ++ "` is declared in two of src/c.zig's modules and they are not the same declaration" };
                }
                earlier = true;
            }
            if (earlier) continue;
            const Decl = @TypeOf(@field(m, name));
            if (Decl == type) {
                if (sweepType(Header, name, @field(m, name), &n)) |d| return .{ .drift = d };
            } else if (@typeInfo(Decl) == .@"fn") {
                if (sweepFn(Header, name, Decl, &n)) |d| return .{ .drift = d };
            } else {
                return .{ .drift = "src/c/ declares `" ++ name ++ "` as a " ++ @tagName(@typeInfo(Decl)) ++
                    ", which this check does not know how to compare; add a case rather than leaving it unchecked" };
            }
        };
        return .{ .counts = n };
    }
}

/// One type declaration of src/c/, against its header counterpart.
fn sweepType(comptime Header: type, comptime name: []const u8, comptime Ours: type, comptime n: *Counts) Drift {
    const what = "type " ++ name;
    n.types += 1;
    switch (@typeInfo(Ours)) {
        .@"struct" => |s| switch (s.layout) {
            .@"extern" => {
                if (missing(Header, typeCName(name), what)) |d| return d;
                n.fields += s.field_names.len;
                return checkStructLayout(what, Ours, @field(Header, typeCName(name)));
            },
            // A bit mask over an anonymous C enum: no header type exists, so
            // the check is per bit.
            .@"packed" => {
                if (!@hasDecl(Ours, "upstream_prefix")) {
                    return what ++ " has no `upstream_prefix` decl, so its bits cannot be paired with the header's constants";
                }
                n.enumerators += s.field_names.len - 1; // minus padding
                return checkMaskBits(Header, what, Ours, Ours.upstream_prefix);
            },
            .auto => return what ++ " has automatic layout, so it has no defined ABI; declare it extern or packed",
        },
        .@"enum" => |e| {
            if (missing(Header, typeCName(name), what)) |d| return d;
            if (!@hasDecl(Ours, "upstream_prefix")) {
                return what ++ " has no `upstream_prefix` decl, so its enumerators cannot be paired with the header's constants";
            }
            n.enumerators += e.field_names.len;
            if (sameSizeAndAlign(what, Ours, @field(Header, typeCName(name)))) |d| return d;
            return checkEnumValues(Header, what, Ours, Ours.upstream_prefix);
        },
        // A callback alias of the binding's own. Upstream declares its
        // function-pointer parameters inline and names no typedef; the
        // signature is checked, deep, at every extern that takes it.
        .pointer => {
            const Fn = fnPointee(Ours) orelse return what ++ " is a non-function pointer alias, which this check does not know how to compare";
            if (hasLateFloat(Fn)) n.late_float_fns += 1;
            return null;
        },
        else => return what ++ " is a " ++ @tagName(@typeInfo(Ours)) ++ ", which this check does not know how to compare against the header",
    }
}

/// One function declaration of src/c/. A Zig helper is allowed, but not on
/// a boundary name: the reverse sweep only checks that a name exists, so a
/// helper on an exported symbol's name would satisfy it while the extern it
/// displaced vanishes.
fn sweepFn(comptime Header: type, comptime name: []const u8, comptime Decl: type, comptime n: *Counts) Drift {
    if (@typeInfo(Decl).@"fn".attrs.@"callconv" == .auto) {
        if (!std.mem.startsWith(u8, name, "meshopt_")) return null;
        return "src/c/ declares `" ++ name ++ "` as a Zig function, not an extern; the `meshopt_` prefix " ++
            "is reserved for the C boundary here, so rename the helper";
    }
    const what = "function " ++ name;
    if (missing(Header, name, what)) |d| return d;
    if (hasLateFloat(Decl)) n.late_float_fns += 1;
    if (hasFloatAggregateReturn(Decl)) n.float_aggregate_return_fns += 1;
    n.functions += 1;
    return checkFnType(what, Decl, @TypeOf(@field(Header, name)));
}

const Bound = struct { functions: usize = 0, drift: Drift = null };

/// The other direction, the completeness gate: a function `Header` declares
/// that `modules` never bound is invisible to the sweep above, which walks
/// only what src/c/ has.
fn sweepTheirs(comptime modules: anytype, comptime Header: type) Bound {
    comptime {
        var found: usize = 0;
        for (@typeInfo(Header).@"struct".decl_names) |name| {
            // Filter by name BEFORE touching the value: translate-c emits
            // `@compileError` declarations for system macros it cannot render.
            if (!std.mem.startsWith(u8, name, "meshopt_")) continue;
            if (@typeInfo(@TypeOf(@field(Header, name))) != .@"fn") continue;
            found += 1;
            var home: ?type = null;
            for (modules) |m| {
                if (@hasDecl(m, name)) home = m;
            }
            const m = home orelse return .{ .drift = "the C headers declare `" ++ name ++ "` but no module in " ++
                "src/c.zig binds it; the binding is complete by contract, so declare it in the module its header region names" };
            // The name must resolve to something that links: the forward
            // sweep refuses helpers on boundary names first, and this is the
            // backstop, which depends only on the header.
            const Ours = @TypeOf(@field(m, name));
            if (@typeInfo(Ours) != .@"fn") {
                return .{ .drift = "the C headers declare `" ++ name ++ "` but src/c/ declares that name as a " ++
                    @tagName(@typeInfo(Ours)) ++ " rather than a function" };
            }
            if (@typeInfo(Ours).@"fn".attrs.@"callconv" == .auto) {
                return .{ .drift = "the C headers declare `" ++ name ++ "` but src/c/ declares that name as a " ++
                    "Zig function rather than an extern, so nothing binds the symbol" };
            }
        }
        return .{ .functions = found };
    }
}

/// The shim seam: `Shim`'s externs against `Header`'s forwarders, both
/// ways. The forwarders exist to dodge a measured miscompile, so a drifted
/// shim signature would corrupt exactly the calls it is there to protect.
fn sweepShim(comptime Shim: type, comptime Header: type) Bound {
    comptime {
        var found: usize = 0;
        for (@typeInfo(Shim).@"struct".decl_names) |name| {
            const Decl = @TypeOf(@field(Shim, name));
            if (@typeInfo(Decl) != .@"fn") continue;
            const what = "shim function " ++ name;
            if (missing(Header, name, what)) |d| return .{ .drift = d };
            if (checkFnType(what, Decl, @TypeOf(@field(Header, name)))) |d| return .{ .drift = d };
            found += 1;
        }
        for (@typeInfo(Header).@"struct".decl_names) |name| {
            if (!std.mem.startsWith(u8, name, "zmeshopt_shim_")) continue;
            if (@typeInfo(@TypeOf(@field(Header, name))) != .@"fn") continue;
            if (!@hasDecl(Shim, name)) {
                return .{ .drift = "src/abi_shim.h declares `" ++ name ++ "` but src/shim.zig " ++
                    "does not bind it, so the forwarder is unreachable from Zig" };
            }
        }
        return .{ .functions = found };
    }
}

//=============================================================================
// The tests
//
// The first holds the real binding to the real headers; reaching its body
// means no comparison drifted, so what is left to assert is that the sweeps
// ran: one matching nothing would read the same as one matching everything.
// The rest give the guard one deliberate drift each, of a kind a review
// would miss, and require it to name it.
//=============================================================================

test "ABI: src/c/ agrees with meshoptimizer.h, and binds all of it" {
    @setEvalBranchQuota(8_000_000);
    const ours = comptime sweepOurs(c.modules, h);
    const theirs = comptime sweepTheirs(c.modules, h);
    const forwarders = comptime sweepShim(shim, h);
    if (ours.drift) |d| @compileError("zmeshopt ABI drift: " ++ d);
    if (theirs.drift) |d| @compileError("zmeshopt ABI drift: " ++ d);
    if (forwarders.drift) |d| @compileError("zmeshopt ABI drift: " ++ d);

    // The counted surface of meshoptimizer v1.2. Floors, not equalities, for
    // all but functions: the reverse sweep fails on an unbound function, so
    // `functions == theirs` pins completeness exactly.
    try std.testing.expect(ours.counts.types >= 14);
    try std.testing.expect(ours.counts.functions >= 85);
    try std.testing.expect(ours.counts.fields >= 25);
    try std.testing.expect(ours.counts.enumerators >= 16);
    try std.testing.expectEqual(ours.counts.functions, theirs.functions);
    // The two hazard shapes, pinned: 8 late-float signatures and one
    // all-float struct return (meshopt_analyzeCoverage), each with its
    // forwarder in src/abi_shim.c. A re-vendor that adds one fails here.
    try std.testing.expectEqual(@as(usize, 8), ours.counts.late_float_fns);
    try std.testing.expectEqual(@as(usize, 1), ours.counts.float_aggregate_return_fns);
    try std.testing.expectEqual(ours.counts.late_float_fns + ours.counts.float_aggregate_return_fns, forwarders.functions);
}

fn expectDrift(comptime drift: Drift, comptime says: []const u8) !void {
    const found = drift orelse return error.DriftNotCaught;
    if (std.mem.find(u8, found, says) == null) {
        std.log.err("expected a drift saying \"{s}\", got: {s}", .{ says, found });
        return error.WrongDrift;
    }
}

/// The position of the field called `name`.
fn fieldIndex(comptime names: []const [:0]const u8, comptime name: []const u8) usize {
    for (names, 0..) |field, k| {
        if (std.mem.eql(u8, field, name)) return k;
    }
    @compileError("no field " ++ name);
}

/// `T` with fields `a` and `b` exchanged in declaration order.
fn Swapped(comptime T: type, comptime a: []const u8, comptime b: []const u8) type {
    const s = @typeInfo(T).@"struct";
    var names = s.field_names[0..s.field_names.len].*;
    var types = s.field_types[0..s.field_types.len].*;
    const i = fieldIndex(&names, a);
    const j = fieldIndex(&names, b);
    std.mem.swap([:0]const u8, &names[i], &names[j]);
    std.mem.swap(type, &types[i], &types[j]);
    return @Struct(s.layout, s.backing_integer, &names, &types, s.field_attrs);
}

/// `T` with field `name` renamed `to`.
fn Renamed(comptime T: type, comptime name: []const u8, comptime to: [:0]const u8) type {
    const s = @typeInfo(T).@"struct";
    var names = s.field_names[0..s.field_names.len].*;
    names[fieldIndex(&names, name)] = to;
    return @Struct(s.layout, s.backing_integer, &names, s.field_types, s.field_attrs);
}

/// `T` with field `name` of type `F`.
fn Retyped(comptime T: type, comptime name: []const u8, comptime F: type) type {
    const s = @typeInfo(T).@"struct";
    var types = s.field_types[0..s.field_types.len].*;
    types[fieldIndex(s.field_names, name)] = F;
    return @Struct(s.layout, s.backing_integer, s.field_names, &types, s.field_attrs);
}

/// Enum `E` over tag type `Tag`, with enumerator `name` (if given) set to `value`.
fn Reenumerated(comptime E: type, comptime Tag: type, comptime name: ?[]const u8, comptime value: comptime_int) type {
    const e = @typeInfo(E).@"enum";
    var values: [e.field_values.len]Tag = undefined;
    for (e.field_values, &values) |v, *slot| slot.* = v;
    if (name) |n| values[fieldIndex(e.field_names, n)] = value;
    return @Enum(Tag, e.mode, e.field_names, &values);
}

/// `T` with a field `name` of type `F` added first.
fn Prepended(comptime T: type, comptime name: [:0]const u8, comptime F: type) type {
    const s = @typeInfo(T).@"struct";
    const names = [_][:0]const u8{name} ++ s.field_names[0..s.field_names.len].*;
    const types = [_]type{F} ++ s.field_types[0..s.field_types.len].*;
    const attrs = [_]@TypeOf(s.field_attrs[0]){.{}} ++ s.field_attrs[0..s.field_attrs.len].*;
    return @Struct(s.layout, null, &names, &types, &attrs);
}

test "two same-sized fields swapped are caught by their offsets" {
    @setEvalBranchQuota(100_000);
    // cone_apex and cone_axis are both [3]f32, so the offset sequence is unchanged.
    const Ours = Swapped(c.clusterize.Bounds, "cone_apex", "cone_axis");
    try expectDrift(comptime checkStructLayout("type Bounds", Ours, h.meshopt_Bounds), "is at byte");
}

test "a callback's parameter widened is caught through the function pointer" {
    const Widened = fn ([*]u32, ?[*]const u32, usize, [*]const f32, usize, usize, ?*const fn (?*anyopaque, u64, u32) callconv(.c) c_int, ?*anyopaque) callconv(.c) usize;
    try expectDrift(comptime checkFnType("function meshopt_generateVertexRemapCustom", Widened, @TypeOf(h.meshopt_generateVertexRemapCustom)), "(callback) parameter 1 is 8 bytes");
}

test "a parameter dropped, or widened from f32 to f64, is caught" {
    const Dropped = fn ([*]const f32, usize) callconv(.c) f32;
    try expectDrift(comptime checkFnType("function meshopt_simplifyScale", Dropped, @TypeOf(h.meshopt_simplifyScale)), "takes 2 parameters");
    const Widened = fn ([*]u32, [*]const u32, usize, [*]const f32, usize, usize, f64) callconv(.c) void;
    try expectDrift(comptime checkFnType("function meshopt_optimizeOverdraw", Widened, @TypeOf(h.meshopt_optimizeOverdraw)), "parameter 6 is 8 bytes");
}

test "an enumerator renumbered, and a tag narrowed, are caught" {
    @setEvalBranchQuota(100_000);
    const E = c.encode_filters.EncodeExpMode;
    const Renumbered = Reenumerated(E, c_uint, "shared_component", 20);
    try expectDrift(comptime checkEnumValues(h, "type EncodeExpMode", Renumbered, E.upstream_prefix), "shared_component is 20");
    const Narrowed = Reenumerated(E, u8, null, 0);
    try expectDrift(comptime sameSizeAndAlign("type EncodeExpMode", Narrowed, h.meshopt_EncodeExpMode), "is 1 bytes");
}

test "two mask bits exchanged, and a flag renamed, are caught by name" {
    @setEvalBranchQuota(100_000);
    const O = c.simplify.SimplifyOptions;
    try expectDrift(comptime checkMaskBits(h, "type SimplifyOptions", Swapped(O, "prune", "regularize"), O.upstream_prefix), "regularize is bit 0x8");
    try expectDrift(comptime checkMaskBits(h, "type SimplifyOptions", Renamed(O, "regularize_light", "regularize_lite"), O.upstream_prefix), "expects `meshopt_SimplifyRegularizeLite`");
}

test "header-side drift: a field added, retyped signed, or retyped int" {
    @setEvalBranchQuota(200_000);
    try expectDrift(comptime checkStructLayout("type Stream", c.remap.Stream, Prepended(h.meshopt_Stream, "intruder", c_uint)), "bytes on the Zig side");
    try expectDrift(comptime checkStructLayout("type Meshlet", c.clusterize.Meshlet, Retyped(h.meshopt_Meshlet, "vertex_offset", c_int)), "vertex_offset is unsigned on the Zig side but signed");
    try expectDrift(comptime checkStructLayout("type Bounds", c.clusterize.Bounds, Retyped(h.meshopt_Bounds, "cone_cutoff", c_int)), "cone_cutoff is a float on the Zig side but a int");
}

test "the reverse sweep refuses a header function no module binds, or one deleted" {
    @setEvalBranchQuota(1_000_000);
    const Header = struct {
        pub extern fn meshopt_futureThing(destination: [*]u32, count: usize) void;
    };
    try expectDrift(comptime sweepTheirs(c.modules, Header).drift, "declare `meshopt_futureThing` but no module");
    const Deleted = struct {
        pub extern fn meshopt_stripifyBound(index_count: usize) usize;
    };
    try expectDrift(comptime sweepTheirs(.{c.remap}, Deleted).drift, "declare `meshopt_stripifyBound` but no module");
}

test "a Zig helper wearing an exported symbol's name is refused both ways" {
    @setEvalBranchQuota(100_000);
    const Helper = struct {
        // glint-ignore: Z001 -- the test's subject is a helper wearing the C symbol's name
        pub fn meshopt_encodeIndexBufferBound(index_count: usize, vertex_count: usize) usize {
            _ = vertex_count;
            return index_count;
        }
    };
    try expectDrift(comptime sweepOurs(.{Helper}, h).drift, "as a Zig function, not an extern");
    const Header = struct {
        pub extern fn meshopt_encodeIndexBufferBound(index_count: usize, vertex_count: usize) usize;
    };
    try expectDrift(comptime sweepTheirs(.{Helper}, Header).drift, "rather than an extern");
}

test "a shim extern widened, or a forwarder declared in the header only, is caught" {
    @setEvalBranchQuota(1_000_000);
    const Widened = struct {
        pub extern fn zmeshopt_shim_opacityMapMeasure(target_edge: f32, levels: [*]u8, sources: [*]u32, omm_indices: [*]c_int, indices: [*]const u32, index_count: usize, vertex_uvs: [*]const f32, vertex_count: usize, vertex_uvs_stride: usize, texture_width: u64, texture_height: u32, max_level: c_int) usize;
    };
    try expectDrift(comptime sweepShim(Widened, struct {
        pub const zmeshopt_shim_opacityMapMeasure = h.zmeshopt_shim_opacityMapMeasure;
    }).drift, "shim function zmeshopt_shim_opacityMapMeasure parameter 9");
    const Header = struct {
        pub const zmeshopt_shim_analyzeCoverage = h.zmeshopt_shim_analyzeCoverage;
        pub extern fn zmeshopt_shim_futureThing(first: f32, destination: [*]u32) void;
    };
    const Bound1 = struct {
        pub const zmeshopt_shim_analyzeCoverage = shim.zmeshopt_shim_analyzeCoverage;
    };
    try expectDrift(comptime sweepShim(Bound1, Header).drift, "does not bind it, so the forwarder is unreachable");
}

test "the hazard shapes are recognised and counted" {
    try std.testing.expect(comptime hasLateFloat(fn (u8, u8, u8, u8, u8, u8, u8, f32) callconv(.c) void));
    try std.testing.expect(!comptime hasLateFloat(fn (u8, u8, u8, u8, u8, u8, f32) callconv(.c) void));
    try std.testing.expect(comptime hasFloatAggregateReturn(@TypeOf(h.meshopt_analyzeCoverage)));
    try std.testing.expect(!comptime hasFloatAggregateReturn(@TypeOf(h.meshopt_stripifyBound)));
    try std.testing.expect(!comptime hasFloatAggregateReturn(@TypeOf(h.meshopt_analyzeOverdraw)));
    try std.testing.expect(!comptime hasFloatAggregateReturn(@TypeOf(h.meshopt_computeSphereBounds)));
    // A late-float extern added to a module raises the pinned count.
    const Planted = struct {
        pub extern fn meshopt_futureLate(p0: usize, p1: usize, p2: usize, p3: usize, p4: usize, p5: usize, p6: usize, x: f32) void;
    };
    const Header = struct {
        pub extern fn meshopt_futureLate(p0: usize, p1: usize, p2: usize, p3: usize, p4: usize, p5: usize, p6: usize, x: f32) void;
    };
    const swept = comptime sweepOurs(.{Planted}, Header);
    try std.testing.expect(swept.drift == null);
    try std.testing.expectEqual(@as(usize, 1), swept.counts.late_float_fns);
}
