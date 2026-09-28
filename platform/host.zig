const std = @import("std");
const abi = @import("abi.zig");
const runtime = @import("runtime.zig");

extern fn roc_main() callconv(.c) u8;

var active_calls = std.atomic.Value(usize).init(0);
var peak_calls = std.atomic.Value(usize).init(0);

const Batch = struct {
    task: *abi.Closure,
    results: []?*anyopaque,
    next: std.atomic.Value(usize) = .init(0),
    ready: std.atomic.Value(usize) = .init(0),
    worker_count: usize,

    fn run(batch: *Batch) void {
        // Start together, including in small test cases.
        _ = batch.ready.fetchAdd(1, .acq_rel);
        while (batch.ready.load(.acquire) != batch.worker_count) std.Thread.yield() catch {};
        while (true) {
            const index = batch.next.fetchAdd(1, .monotonic);
            if (index >= batch.results.len) return;
            // Borrow the shared closure; each index owns a distinct result slot.
            const active = active_calls.fetchAdd(1, .monotonic) + 1;
            _ = peak_calls.fetchMax(active, .monotonic);
            batch.results[index] = abi.invoke(batch.task, index);
            _ = active_calls.fetchSub(1, .monotonic);
        }
    }
};

export fn parallel_run(request: abi.Request) abi.BoxList {
    const task = request.task;
    const count = request.item_count;
    defer abi.release(task);
    if (count == 0) return .{ .ptr = null, .len = 0, .capacity = 0 };
    if (request.workers == 0) runtime.fail("Invalid worker count");
    const output = abi.allocateResults(count);
    const worker_count = @min(request.workers, count, 64);
    var batch = Batch{ .task = task, .results = output.ptr.?[0..count], .worker_count = worker_count };
    var threads: [64]std.Thread = undefined;
    for (threads[0..worker_count]) |*thread| {
        thread.* = std.Thread.spawn(.{}, Batch.run, .{&batch}) catch runtime.fail("Cannot start worker");
    }
    for (threads[0..worker_count]) |thread| thread.join();
    return output;
}

export fn main() c_int {
    const status = roc_main();
    if (runtime.live_allocations.load(.acquire) != 0) runtime.fail("Roc allocations were not all released");
    if (status == 0) std.debug.print("Parallel example passed; peak concurrent calls: {d}; all Roc allocations released.\n", .{peak_calls.load(.acquire)});
    return status;
}

comptime {
    _ = runtime;
}
