// Runtime symbols required by Roc nightly-2026-09-12 (220fd47).
// libc allocation is thread-safe; values may be released on another thread.
const std = @import("std");
extern "c" fn malloc(usize) ?*anyopaque;
extern "c" fn free(*anyopaque) void;
extern "c" fn exit(c_int) noreturn;

pub var live_allocations = std.atomic.Value(usize).init(0);

const Header = extern struct { base: *anyopaque, length: usize };

pub fn fail(message: []const u8) noreturn {
    std.debug.print("{s}\n", .{message});
    exit(2);
}

fn header(ptr: *anyopaque) *Header {
    return @ptrFromInt(@intFromPtr(ptr) - @sizeOf(Header));
}

export fn roc_alloc(length: usize, requested_alignment: usize) ?*anyopaque {
    const alignment = @max(requested_alignment, @alignOf(Header));
    const overhead = std.math.add(usize, alignment - 1, @sizeOf(Header)) catch fail("Allocation overflow");
    const size = std.math.add(usize, length, overhead) catch fail("Allocation overflow");
    const base = malloc(size) orelse fail("Out of memory");
    const address = std.mem.alignForward(usize, @intFromPtr(base) + @sizeOf(Header), alignment);
    const ptr: *anyopaque = @ptrFromInt(address);
    header(ptr).* = .{ .base = base, .length = length };
    _ = live_allocations.fetchAdd(1, .monotonic);
    return ptr;
}

export fn roc_dealloc(ptr: *anyopaque, alignment: usize) void {
    _ = alignment;
    free(header(ptr).base);
    _ = live_allocations.fetchSub(1, .monotonic);
}

export fn roc_realloc(ptr: *anyopaque, length: usize, alignment: usize) ?*anyopaque {
    const replacement = roc_alloc(length, alignment).?;
    const copied = @min(header(ptr).length, length);
    @memcpy(@as([*]u8, @ptrCast(replacement))[0..copied], @as([*]const u8, @ptrCast(ptr))[0..copied]);
    roc_dealloc(ptr, alignment);
    return replacement;
}

export fn roc_dbg(bytes: [*]const u8, length: usize) void {
    std.debug.print("{s}\n", .{bytes[0..length]});
}

export fn roc_crashed(bytes: [*]const u8, length: usize) noreturn {
    fail(bytes[0..length]);
}

export fn roc_expect_failed(bytes: [*]const u8, length: usize) noreturn {
    fail(bytes[0..length]);
}
