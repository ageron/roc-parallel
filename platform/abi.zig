// The 64-bit boxed-callable and list ABI in Roc 220fd47.
// See src/builtins/{erased_callable,list,utils}.zig in that compiler revision.
const std = @import("std");
const runtime = @import("runtime.zig");
extern fn roc_alloc(usize, usize) ?*anyopaque;
extern fn roc_dealloc(*anyopaque, usize) void;

// Every result is a nonempty Box({ value: a, marker: U8 }).
// The marker prevents zero-sized boxes/lists; Zig need not know a's layout.
pub fn List(comptime T: type) type {
    return extern struct {
        ptr: ?[*]T,
        len: usize,
        capacity: usize,

        pub fn slice(self: @This()) []T {
            return if (self.ptr) |ptr| ptr[0..self.len] else &.{};
        }
    };
}
pub const BoxList = List(?*anyopaque);
pub const Bytes = List(u8);
pub const Arguments = List(Bytes);
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
    return invokeWith(?*anyopaque, task, &index);
}

pub fn invokeWith(comptime Result: type, task: *Closure, argument: *const anyopaque) Result {
    var result: Result = undefined;
    var descriptor: ?*const anyopaque = null;
    // LLVM output uses linker-resolved runtime symbols, not a RocOps table.
    // Null reuse borrows the closure; ownership stays with parallel_run.
    task.call(null, @ptrCast(&result), argument, capture(task), null, &descriptor);
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

fn allocateList(comptime T: type, count: usize, comptime children_refcounted: bool) List(T) {
    if (count == 0) return .{ .ptr = null, .len = 0, .capacity = 0 };
    const header_bytes = (if (children_refcounted) @as(usize, 2) else 1) * @sizeOf(usize);
    const data_bytes = std.math.mul(usize, count, @sizeOf(T)) catch runtime.fail("Too many list elements");
    const size = std.math.add(usize, header_bytes, data_bytes) catch runtime.fail("Too many list elements");
    const base: [*]usize = @ptrCast(@alignCast(roc_alloc(size, @alignOf(usize)).?));
    if (children_refcounted) base[0] = count;
    base[header_bytes / @sizeOf(usize) - 1] = 1;
    return .{ .ptr = @ptrCast(base + header_bytes / @sizeOf(usize)), .len = count, .capacity = count << 1 };
}

pub fn allocateResults(count: usize) BoxList {
    return allocateList(?*anyopaque, count, true);
}

pub fn arguments(values: []const []const u8) Arguments {
    const result = allocateList(Bytes, values.len, true);
    for (values, result.slice()) |value, *slot| {
        slot.* = allocateList(u8, value.len, false);
        @memcpy(slot.slice(), value);
    }
    return result;
}

pub fn releaseBytes(bytes: Bytes) void {
    releasePlain(u8, bytes);
}

// Only for lists whose elements do not own references (bytes or indices).
pub fn releasePlain(comptime T: type, bytes: List(T)) void {
    if (bytes.ptr == null) return;
    const allocation = if (bytes.capacity & 1 != 0) bytes.capacity & ~@as(usize, 1) else @intFromPtr(bytes.ptr.?);
    const rc: *isize = @ptrFromInt(allocation - @sizeOf(usize));
    if (@atomicLoad(isize, rc, .acquire) == 0) return;
    if (@atomicRmw(isize, rc, .Sub, 1, .acq_rel) == 1) roc_dealloc(@ptrCast(rc), @alignOf(usize));
}

comptime {
    if (@sizeOf(usize) != 8) @compileError("This example supports 64-bit targets only");
}
