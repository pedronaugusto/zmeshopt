//! Comptime cross-check: the hand-written externs in `src/c/` against the
//! vendored `meshoptimizer.h`, translated by the build for the test module
//! alone (the shipped module stays translate-c-free), compared per
//! declaration via reflection;
//! an unclassified declaration errors at compile time, not silently.
//!
//! Naming conventions are load-bearing: extern functions carry the C name
//! itself, type `Foo` pairs with `meshopt_Foo`, and a mask or enum whose C
//! enumerators are loose constants carries an `upstream_prefix` decl that,
//! with the PascalCased field name, reconstructs each enumerator. The
//! reverse sweep is the completeness gate: every header function must be
//! bound, enforced at compile time rather than promised in prose.
//!
//! Pointees compare by size/alignment only (the check never descends into a
//! pointee; the behavioural tests hold those); function pointers compare deep.

const std = @import("std");
const c = @import("c.zig");
const shim = @import("shim.zig");

const h = @import("meshoptimizer_h");

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
//
// Every failure is a compile error naming both sides — a guard that cannot
// state which declaration drifted costs more to read than the drift it found.
//=============================================================================

fn fail(comptime msg: []const u8) void {
    @compileError("zmeshopt ABI drift: " ++ msg);
}

fn theirDecl(comptime name: []const u8, comptime because: []const u8) type {
    if (!@hasDecl(h, name)) {
        fail("`" ++ because ++ "` expects `" ++ name ++
            "` from the C headers, which do not declare it");
    }
    return @TypeOf(@field(h, name));
}

fn sameSizeAndAlign(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    if (@sizeOf(Ours) != @sizeOf(Theirs)) {
        fail(what ++ " is " ++ std.fmt.comptimePrint("{d}", .{@sizeOf(Ours)}) ++
            " bytes on the Zig side but " ++ std.fmt.comptimePrint("{d}", .{@sizeOf(Theirs)}) ++
            " in the C header");
    }
    if (@alignOf(Ours) != @alignOf(Theirs)) {
        fail(what ++ " has alignment " ++ std.fmt.comptimePrint("{d}", .{@alignOf(Ours)}) ++
            " on the Zig side but " ++ std.fmt.comptimePrint("{d}", .{@alignOf(Theirs)}) ++
            " in the C header");
    }
}

/// The scalar a type really is at the boundary, with the Zig-side wrapper
/// removed. translate-c renders every C enum as a plain integer; this side
/// deliberately keeps enums as `enum(...)` and masks as `packed struct`, so
/// each is resolved to its backing integer first — not a loosening: an
/// `enum(u32)` against a C `int` enum is a real signedness disagreement, and
/// this is what surfaces it.
fn scalarIdentity(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .@"enum" => |e| e.tag_type,
        .@"struct" => |st| st.backing_integer orelse T,
        else => T,
    };
}

/// A `*const fn`/`?*const fn` unwrapped to the fn type, or null when the type
/// is not a function pointer. translate-c makes every C function pointer
/// optional; both sides unwrap the same way.
fn fnPointee(comptime T: type) ?type {
    const Base = switch (@typeInfo(T)) {
        .optional => |o| o.child,
        else => T,
    };
    if (@typeInfo(Base) == .pointer and
        @typeInfo(@typeInfo(Base).pointer.child) == .@"fn")
    {
        return @typeInfo(Base).pointer.child;
    }
    return null;
}

/// Size and alignment, plus the scalar identity they do not carry: a
/// `size_t` declared `isize` or a `float` declared `u32` passes both and
/// silently reinterprets every value — signedness and int-vs-float close
/// that. When BOTH sides are function pointers the pointed-to signatures
/// are compared deep; upstream has no named callback typedefs, so this is
/// the one place a callback's shape is held to the header.
fn sameScalar(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    sameSizeAndAlign(what, Ours, Theirs);

    if (fnPointee(Ours)) |OursFn| {
        if (fnPointee(Theirs)) |TheirsFn| {
            checkFnType(what ++ " (callback)", OursFn, TheirsFn);
            return;
        }
        fail(what ++ " is a function pointer on the Zig side but not in the C header");
    } else if (fnPointee(Theirs) != null) {
        fail(what ++ " is a function pointer in the C header but not on the Zig side");
    }

    const oi = @typeInfo(scalarIdentity(Ours));
    const ti = @typeInfo(scalarIdentity(Theirs));

    // Signedness, EXCEPT across an enum or mask: C leaves an enum's
    // underlying type to the implementation (clang/gcc pick unsigned when no
    // enumerator is negative, MSVC uses `int`), so comparing it would fail a
    // correct binding on one toolchain and pass on another. Safe to skip only
    // because every enumerator here is non-negative — `checkEnumValues`
    // asserts that precondition rather than assuming it.
    const across_enum = scalarIdentity(Ours) != Ours or scalarIdentity(Theirs) != Theirs;
    if (!across_enum and oi == .int and ti == .int and
        oi.int.signedness != ti.int.signedness)
    {
        fail(what ++ " is " ++ @tagName(oi.int.signedness) ++ " on the Zig side but " ++
            @tagName(ti.int.signedness) ++ " in the C header");
    }
    if ((oi == .int) != (ti == .int) or (oi == .float) != (ti == .float)) {
        fail(what ++ " is a " ++ @tagName(oi) ++ " on the Zig side but a " ++
            @tagName(ti) ++ " in the C header");
    }
}

/// Compares two function types by the things translate-c preserves: how many
/// parameters there are, how each one is passed, and whether the signature is
/// variadic.
fn checkFnType(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    const ours = @typeInfo(Ours).@"fn";
    const theirs = @typeInfo(Theirs).@"fn";

    if (ours.param_types.len != theirs.param_types.len) {
        fail(what ++ " takes " ++ std.fmt.comptimePrint("{d}", .{ours.param_types.len}) ++
            " parameters on the Zig side but " ++ std.fmt.comptimePrint("{d}", .{theirs.param_types.len}) ++
            " in the C header");
    }
    if (ours.attrs.varargs != theirs.attrs.varargs) {
        fail(what ++ " is variadic on one side of the boundary only");
    }

    inline for (ours.param_types, theirs.param_types, 0..) |op, tp, i| {
        const OP = op orelse fail(what ++ " has an untyped parameter on the Zig side");
        const TP = tp orelse fail(what ++ " has an untyped parameter in the C header");
        sameScalar(
            what ++ " parameter " ++ std.fmt.comptimePrint("{d}", .{i}),
            OP,
            TP,
        );
    }

    const OR = ours.return_type orelse fail(what ++ " has no return type on the Zig side");
    const TR = theirs.return_type orelse fail(what ++ " has no return type in the C header");
    sameScalar(what ++ " return value", OR, TR);
}

//=============================================================================
// Late-float parameter shapes
//
// Zig 0.16.0's self-hosted x86-64 backend was measured (zjolt, 2026-09-01,
// by disassembling minimal reproductions) misallocating an f32/f64 argument
// preceded by MORE than 6 integer-class arguments, on x86_64-linux where
// that backend is the Debug default. meshoptimizer's ABI is upstream's, and
// 8 of its functions have exactly that shape, so this package cannot forbid
// them; the idiomatic layer crosses them through `src/abi_shim.c` instead.
// This sweep classifies them and pins the count, so a re-vendor that adds
// one is a conscious act of extending the shim; `abi_canary_test.zig`
// proves both the raw hazard and the shim shapes at runtime.
//=============================================================================

const max_int_class_params_before_float = 6;

/// True when `Fn` passes a float after more than 6 integer-class parameters.
fn hasLateFloat(comptime Fn: type) bool {
    comptime {
        var int_class: usize = 0;
        for (@typeInfo(Fn).@"fn".param_types) |param| {
            const P = param orelse continue;
            switch (@typeInfo(scalarIdentity(P))) {
                .float, .vector => {
                    if (int_class > max_int_class_params_before_float) return true;
                },
                else => int_class += 1,
            }
        }
        return false;
    }
}

//=============================================================================
// Struct, enum and mask comparisons
//=============================================================================

/// Struct layout, compared field by NAME rather than by position — the
/// distinction that makes the check worth having. Two same-sized adjacent
/// fields swapping places leaves the *sequence* of offsets identical, so a
/// positional comparison passes a swap that silently reinterprets both
/// fields; pairing each name with its own offset catches it.
fn checkStructLayout(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    sameSizeAndAlign(what, Ours, Theirs);

    const ours = @typeInfo(Ours).@"struct";
    const theirs = switch (@typeInfo(Theirs)) {
        .@"struct" => |s| s,
        else => fail(what ++ " is a struct in src/c/ but not in meshoptimizer.h"),
    };

    if (ours.field_names.len != theirs.field_names.len) {
        fail(what ++ " has " ++ std.fmt.comptimePrint("{d}", .{ours.field_names.len}) ++
            " fields in src/c/ but " ++ std.fmt.comptimePrint("{d}", .{theirs.field_names.len}) ++
            " in meshoptimizer.h");
    }

    inline for (ours.field_names, ours.field_types) |field_name, Field| {
        if (!@hasField(Theirs, field_name)) {
            fail(what ++ " has field `" ++ field_name ++ "` in src/c/, which meshoptimizer.h does not");
        }
        if (@offsetOf(Ours, field_name) != @offsetOf(Theirs, field_name)) {
            fail(what ++ "." ++ field_name ++ " is at byte " ++
                std.fmt.comptimePrint("{d}", .{@offsetOf(Ours, field_name)}) ++ " in src/c/ but " ++
                std.fmt.comptimePrint("{d}", .{@offsetOf(Theirs, field_name)}) ++ " in meshoptimizer.h");
        }
        sameScalar(
            what ++ "." ++ field_name,
            Field,
            @FieldType(Theirs, field_name),
        );
    }
}

/// Enumerator values, paired by `upstream_prefix` ++ PascalCase(field).
///
/// translate-c flattens a C enum to an integer alias and loses which
/// enumerators belonged to it, so the values cannot be recovered from the
/// type; the prefix convention is what puts them back together.
fn checkEnumValues(
    comptime what: []const u8,
    comptime Ours: type,
) void {
    if (!@hasDecl(Ours, "upstream_prefix")) {
        fail(what ++ " has no `upstream_prefix` decl, so its enumerators cannot " ++
            "be paired with the header's constants");
    }
    const info = @typeInfo(Ours).@"enum";
    inline for (info.field_names, info.field_values) |field_name, value| {
        const cname = Ours.upstream_prefix ++ pascal(field_name);
        _ = theirDecl(cname, what ++ "." ++ field_name);
        // The precondition that lets sameScalar skip signedness across an
        // enum. C leaves the underlying type to the implementation, and the
        // implementations disagree; that is only unobservable while every
        // enumerator is non-negative.
        if (value < 0) {
            fail(what ++ "." ++ field_name ++ " is negative, which makes the enum's " ++
                "underlying type observable — C leaves that to the implementation " ++
                "and MSVC and clang choose differently.");
        }
        if (@as(i128, @field(h, cname)) != @as(i128, value)) {
            fail(what ++ "." ++ field_name ++ " is " ++
                std.fmt.comptimePrint("{d}", .{value}) ++ " in src/c/ but " ++ cname ++
                " is " ++ std.fmt.comptimePrint("{d}", .{@field(h, cname)}) ++ " in meshoptimizer.h");
        }
    }
}

/// Bit-mask values for a packed struct whose C counterpart is an ANONYMOUS
/// enum of bits — upstream gives the set no type name, so there is nothing to
/// compare the type against; each bit is compared against the enumerator its
/// name reconstructs. Padding fields (leading underscore) have no counterpart
/// and are skipped.
fn checkMaskBits(
    comptime what: []const u8,
    comptime Ours: type,
) void {
    if (!@hasDecl(Ours, "upstream_prefix")) {
        fail(what ++ " has no `upstream_prefix` decl, so its bits cannot be " ++
            "paired with the header's constants");
    }
    const Backing = @typeInfo(Ours).@"struct".backing_integer.?;
    const fields = @typeInfo(Ours).@"struct";
    inline for (fields.field_names, fields.field_types) |field_name, Field| {
        if (comptime std.mem.startsWith(u8, field_name, "_")) continue;
        if (Field != bool) {
            fail(what ++ "." ++ field_name ++ " is not a bool, so its bit value cannot " ++
                "be derived; give this mask an explicit check");
        }
        const cname = Ours.upstream_prefix ++ pascal(field_name);
        _ = theirDecl(cname, what ++ "." ++ field_name);

        var one: Ours = std.mem.zeroes(Ours);
        @field(one, field_name) = true;
        const bit: Backing = @bitCast(one);

        if (@as(i128, @field(h, cname)) != @as(i128, bit)) {
            fail(what ++ "." ++ field_name ++ " is bit " ++
                std.fmt.comptimePrint("0x{x}", .{bit}) ++ " in src/c/ but " ++ cname ++
                " is " ++ std.fmt.comptimePrint("0x{x}", .{@field(h, cname)}) ++ " in meshoptimizer.h");
        }
    }
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
};

/// Every public declaration in `c.zig`'s modules, classified and compared.
/// The `else` arms are compile errors: a declaration this does not know how
/// to check is a hole in the guard, and a hole should stop the build rather
/// than be counted as a pass.
fn sweepOurs() Counts {
    comptime {
        var n = Counts{};

        for (c.modules, 0..) |m, mi| for (@typeInfo(m).@"struct".decl_names) |name| {
            // A name an EARLIER module already declared is a re-export,
            // checked once where it is declared; a re-export that stops being
            // the same declaration refuses the build.
            var earlier = false;
            for (c.modules, 0..) |other, oi| {
                if (oi < mi and @hasDecl(other, name)) {
                    if (@TypeOf(@field(other, name)) == type and
                        @TypeOf(@field(m, name)) == type and
                        @field(other, name) != @field(m, name))
                    {
                        fail("`" ++ name ++ "` is declared in two of src/c.zig's " ++
                            "modules and they are not the same declaration.");
                    }
                    earlier = true;
                }
            }
            if (earlier) continue;

            const Decl = @TypeOf(@field(m, name));

            // ---- types -----------------------------------------------------
            if (Decl == type) {
                const Ours = @field(m, name);
                const what = "type " ++ name;
                n.types += 1;

                switch (@typeInfo(Ours)) {
                    .@"struct" => |s| switch (s.layout) {
                        .@"extern" => {
                            _ = theirDecl(typeCName(name), what);
                            checkStructLayout(what, Ours, @field(h, typeCName(name)));
                            n.fields += s.field_names.len;
                        },
                        .@"packed" => {
                            // A bit mask over an anonymous C enum: no header
                            // type exists, so the check is per bit.
                            checkMaskBits(what, Ours);
                            n.enumerators += s.field_names.len - 1; // minus padding
                        },
                        .auto => fail(what ++ " has automatic layout, so it has no " ++
                            "defined ABI; declare it extern or packed"),
                    },
                    .@"enum" => |e| {
                        _ = theirDecl(typeCName(name), what);
                        sameSizeAndAlign(what, Ours, @field(h, typeCName(name)));
                        checkEnumValues(what, Ours);
                        n.enumerators += e.field_names.len;
                    },
                    .pointer => {
                        // A callback alias of this binding's own. Upstream
                        // declares its function-pointer parameters inline and
                        // names no typedef, so there is no header decl to pair
                        // with — the signature IS checked, deep, at every
                        // extern fn that takes it (sameScalar recurses into
                        // function pointers).
                        if (fnPointee(Ours) == null) {
                            fail(what ++ " is a non-function pointer alias, which " ++
                                "this check does not know how to compare");
                        }
                        if (hasLateFloat(fnPointee(Ours).?)) n.late_float_fns += 1;
                    },
                    else => fail("type " ++ name ++ " is a " ++
                        @tagName(@typeInfo(Ours)) ++ ", which this check does not know " ++
                        "how to compare against the header"),
                }
                continue;
            }

            // ---- functions -------------------------------------------------
            if (@typeInfo(Decl) == .@"fn") {
                if (@typeInfo(Decl).@"fn".attrs.@"callconv" == .auto) {
                    // A Zig helper, not an extern — allowed, but not on a
                    // boundary name: the reverse sweep only checks a name
                    // exists, so a helper on an exported symbol's name would
                    // satisfy it while the extern it displaced vanishes.
                    if (std.mem.startsWith(u8, name, "meshopt_")) {
                        fail("src/c/ declares `" ++ name ++ "` as a Zig function, " ++
                            "not an extern. The `meshopt_` prefix is reserved for " ++
                            "the C boundary here. Rename the helper.");
                    }
                    continue;
                }
                const what = "function " ++ name;
                _ = theirDecl(name, what);
                checkFnType(what, Decl, @TypeOf(@field(h, name)));
                if (hasLateFloat(Decl)) n.late_float_fns += 1;
                n.functions += 1;
                continue;
            }

            // ---- string constants (the upstream_prefix pattern lives inside
            // types, not at module level; nothing else is expected) ----------
            fail("src/c/ declares `" ++ name ++ "` as a " ++ @tagName(@typeInfo(Decl)) ++
                ", which this check does not know how to compare. Add a case rather " ++
                "than leaving it unchecked.");
        };

        return n;
    }
}

/// The other direction — the completeness gate. A function the header
/// declares that `c.zig` never bound is invisible to the sweep above, because
/// that sweep only walks what `c.zig` has; this one walks the header.
fn sweepTheirs() usize {
    comptime {
        var found: usize = 0;

        for (@typeInfo(h).@"struct".decl_names) |name| {
            // Filter by name BEFORE touching the value: translate-c emits
            // `@compileError` declarations for system macros it cannot
            // render, and evaluating one would fail the build for a reason
            // that has nothing to do with zmeshopt.
            if (!std.mem.startsWith(u8, name, "meshopt_")) continue;
            if (@typeInfo(@TypeOf(@field(h, name))) != .@"fn") continue;

            found += 1;
            var home: ?type = null;
            for (c.modules) |m| {
                if (@hasDecl(m, name)) home = m;
            }
            if (home == null) {
                fail("meshoptimizer.h declares `" ++ name ++ "` but no module in " ++
                    "src/c.zig binds it. This binding is complete by contract: " ++
                    "declare it in the module its header region names.");
            }
            // Existence is not enough: the name must resolve to something
            // that actually links. The forward sweep rejects helpers on
            // boundary names first; this is the backstop, and it depends only
            // on the header.
            const Ours = @TypeOf(@field(home.?, name));
            if (@typeInfo(Ours) != .@"fn") {
                fail("meshoptimizer.h declares `" ++ name ++ "` but src/c/ declares " ++
                    "that name as a " ++ @tagName(@typeInfo(Ours)) ++ " rather than a function");
            }
            if (@typeInfo(Ours).@"fn".attrs.@"callconv" == .auto) {
                fail("meshoptimizer.h declares `" ++ name ++ "` but src/c/ declares " ++
                    "that name as a Zig function rather than an extern, so nothing " ++
                    "binds the symbol");
            }
        }
        return found;
    }
}

/// The shim seam: src/shim.zig's externs against src/abi_shim.h, both ways.
/// The forwarders exist to dodge a measured backend miscompile, so a drifted
/// shim signature would corrupt exactly the calls it is there to protect.
fn sweepShim() usize {
    comptime {
        var found: usize = 0;
        for (@typeInfo(shim).@"struct".decl_names) |name| {
            const Decl = @TypeOf(@field(shim, name));
            if (@typeInfo(Decl) != .@"fn") continue;
            const what = "shim function " ++ name;
            _ = theirDecl(name, what);
            checkFnType(what, Decl, @TypeOf(@field(h, name)));
            found += 1;
        }
        for (@typeInfo(h).@"struct".decl_names) |name| {
            if (!std.mem.startsWith(u8, name, "zmeshopt_shim_")) continue;
            if (@typeInfo(@TypeOf(@field(h, name))) != .@"fn") continue;
            if (!@hasDecl(shim, name)) {
                fail("src/abi_shim.h declares `" ++ name ++ "` but src/shim.zig " ++
                    "does not bind it, so the forwarder is unreachable from Zig");
            }
        }
        return found;
    }
}

//=============================================================================
// The test
//
// The comparisons above are compile errors, so reaching this body means they
// passed. What's left: assert they actually ran — a sweep matching nothing
// silently would be indistinguishable from one matching everything.
//=============================================================================

test "ABI: src/c/ agrees with meshoptimizer.h, and binds all of it" {
    @setEvalBranchQuota(4_000_000);

    const ours = comptime sweepOurs();
    const theirs = comptime sweepTheirs();

    // The counted surface of meshoptimizer v1.2. Floors, not equalities, for
    // everything except functions: the reverse sweep already fails on an
    // unbound function, so `functions == theirs` pins completeness exactly.
    try std.testing.expect(ours.types >= 14);
    try std.testing.expect(ours.functions >= 85);
    try std.testing.expect(ours.fields >= 25);
    try std.testing.expect(ours.enumerators >= 16);
    try std.testing.expectEqual(ours.functions, theirs);

    // The 8 upstream signatures passing a float after more than 6
    // integer-class parameters (see the Late-float section above). Pinned
    // exactly: a re-vendor that adds one must extend `src/abi_shim.c`,
    // `abi_canary_test.zig` and this count together.
    try std.testing.expectEqual(@as(usize, 8), ours.late_float_fns);

    // Those 8, plus the all-float-struct-return forwarder for
    // `meshopt_analyzeCoverage` — the shim seam checked by sweepShim.
    try std.testing.expectEqual(@as(usize, 9), comptime sweepShim());
}
