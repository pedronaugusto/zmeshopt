//! Idiomatic layer: routing meshoptimizer's temporary allocations through a
//! `std.mem.Allocator`.
//!
//! The C hook (`meshopt_setAllocator`) hands the deallocate callback a bare
//! pointer, and a Zig allocator needs the allocation's length back — so the
//! adapter prefixes every allocation with a 16-byte header holding the total
//! size. 16 bytes keeps the pointer meshoptimizer sees aligned the way
//! `operator new` would align it. (Upstream also documents a strict LIFO
//! alloc/free order; the header makes the adapter correct without relying
//! on it.)

const std = @import("std");
const c = @import("c.zig").allocator;

pub const AllocateFn = c.AllocateFn;
pub const DeallocateFn = c.DeallocateFn;

/// Raw hook: replaces operator new/delete for ALL of the library's temporary
/// allocations, process-wide. NOT thread safe: must not run concurrently
/// with any other meshoptimizer call.
pub fn setAllocator(allocate: AllocateFn, deallocate: DeallocateFn) void {
    c.meshopt_setAllocator(allocate, deallocate);
}

/// Installs `allocator` as the process-wide meshoptimizer allocator via the
/// header-prefix adapter. The allocator must outlive every subsequent
/// meshoptimizer call — there is no way back to operator new/delete, so pass
/// something process-lived. Same thread-safety contract as `setAllocator`;
/// on allocation failure the callback returns null, which upstream does NOT
/// check — treat memory exhaustion here as fatal.
pub fn installZigAllocator(allocator: std.mem.Allocator) void {
    installed = allocator;
    c.meshopt_setAllocator(zigAllocate, zigDeallocate);
}

var installed: ?std.mem.Allocator = null;

const header_size = 16;
const alignment = std.mem.Alignment.@"16";

comptime {
    // The header must not lower the alignment of what follows it.
    std.debug.assert(header_size % alignment.toByteUnits() == 0);
    std.debug.assert(header_size >= @sizeOf(usize));
}

fn zigAllocate(size: usize) callconv(.c) ?*anyopaque {
    const allocator = installed orelse return null;
    const total = std.math.add(usize, size, header_size) catch return null;
    const memory = allocator.alignedAlloc(u8, alignment, total) catch return null;
    @as(*usize, @ptrCast(memory.ptr)).* = total;
    return memory.ptr + header_size;
}

fn zigDeallocate(ptr: ?*anyopaque) callconv(.c) void {
    const p = ptr orelse return;
    const base: [*]align(alignment.toByteUnits()) u8 = @alignCast(@as([*]u8, @ptrCast(p)) - header_size);
    const total = @as(*const usize, @ptrCast(base)).*;
    const allocator = installed orelse unreachable;
    allocator.free(base[0..total]);
}

/// A counting allocator over the page allocator, in static storage because
/// the install is irreversible: whatever backs the hook must live as long as
/// the process keeps calling meshoptimizer.
const counting = struct {
    var allocations: usize = 0;
    var deallocations: usize = 0;
    var live_bytes: usize = 0;

    fn alloc(_: *anyopaque, len: usize, a: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const p = std.heap.page_allocator.rawAlloc(len, a, ret_addr);
        if (p != null) {
            allocations += 1;
            live_bytes += len;
        }
        return p;
    }
    fn free(_: *anyopaque, memory: []u8, a: std.mem.Alignment, ret_addr: usize) void {
        deallocations += 1;
        live_bytes -= memory.len;
        std.heap.page_allocator.rawFree(memory, a, ret_addr);
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
        .free = free,
    };
    var state: u8 = 0;
    const allocator = std.mem.Allocator{ .ptr = &state, .vtable = &vtable };
};

test installZigAllocator {
    installZigAllocator(counting.allocator);

    // generateVertexRemap allocates its hash table through the hook.
    const vertices = [_][3]f32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } };
    const indices = [_]u32{ 0, 1, 2 };
    var remap: [3]u32 = undefined;
    const unique = @import("remap.zig").generateVertexRemap([3]f32, &remap, &indices, &vertices);
    try std.testing.expectEqual(@as(usize, 3), unique);

    try std.testing.expect(counting.allocations > 0);
    try std.testing.expectEqual(counting.allocations, counting.deallocations);
    try std.testing.expectEqual(@as(usize, 0), counting.live_bytes);
}
