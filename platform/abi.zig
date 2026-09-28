// The 64-bit boxed-callable and list ABI in Roc 220fd47.
// See src/builtins/{erased_callable,list,utils}.zig in that compiler revision.
const std = @import("std");
const runtime = @import("runtime.zig");
extern fn roc_alloc(usize, usize) ?*anyopaque;
extern fn roc_dealloc(*anyopaque, usize) void;

// Every result is a nonempty Box({ value: a, marker: U8 }).
// The marker prevents zero-sized boxes/lists; Zig need not know a's layout.
pub const BoxList = extern struct { ptr: ?[*]?*anyopaque, len: usize, capacity: usize };
pub const Closure = extern struct {
    call: *const fn (?*anyopaque, ?*anyopaque, ?*const anyopaque, ?*anyopaque, ?*anyopaque, *?*const anyopaque) callconv(.c) void,
    drop: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
};
// Roc sorts U64 fields alphabetically before pointer fields.
pub const Request = extern struct { item_count: u64, workers: u64, task: *Closure };

const capture_alignment = 16;
const capture_offset = std.mem.alignForward(usize, @sizeOf(Closure), capture_alignment);

fn capture(task: *Closure) *anyopaque {
    return @ptrFromInt(@intFromPtr(task) + capture_offset);
}

pub fn invoke(task: *Closure, index: u64) ?*anyopaque {
    var argument = index;
    var result: ?*anyopaque = null;
    var descriptor: ?*const anyopaque = null;
    // LLVM output uses linker-resolved runtime symbols, not a RocOps table.
    // Null reuse borrows the closure; ownership stays with parallel_run.
    task.call(null, @ptrCast(&result), &argument, capture(task), null, &descriptor);
    return result;
}

pub fn release(task: *Closure) void {
    const rc: *isize = @ptrFromInt(@intFromPtr(task) - @sizeOf(usize));
    if (@atomicLoad(isize, rc, .acquire) == 0) return; // Static allocation.
    if (@atomicRmw(isize, rc, .Sub, 1, .acq_rel) == 1) {
        if (task.drop) |drop| drop(capture(task), null);
        roc_dealloc(@ptrFromInt(@intFromPtr(task) - capture_alignment), capture_alignment);
    }
}

pub fn allocateResults(count: usize) BoxList {
    const header_bytes = 2 * @sizeOf(usize);
    const data_bytes = std.math.mul(usize, count, @sizeOf(?*anyopaque)) catch runtime.fail("Too many results");
    const size = std.math.add(usize, header_bytes, data_bytes) catch runtime.fail("Too many results");
    const base: [*]usize = @ptrCast(@alignCast(roc_alloc(size, @alignOf(usize)).?));
    base[0] = count; // Allocation element count: elements themselves are refcounted.
    base[1] = 1; // List reference count.
    return .{ .ptr = @ptrCast(base + 2), .len = count, .capacity = count << 1 };
}

comptime {
    if (@sizeOf(usize) != 8) @compileError("This example supports 64-bit targets only");
}
