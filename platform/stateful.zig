const std = @import("std");
const abi = @import("abi.zig");
const runtime = @import("runtime.zig");

var active_calls = std.atomic.Value(usize).init(0);
pub var peak_calls = std.atomic.Value(usize).init(0);

// Roc structural layout: U64 fields first, then pointer-like fields, each
// alphabetically. Boxed state/reply payloads remain entirely opaque to Zig.
pub const Request = extern struct {
    state_count: u64,
    workers: u64,
    destinations: abi.List(u64),
    initial: *abi.Closure,
    offsets: abi.List(u64),
    step: *abi.Closure,
};
pub const Result = extern struct { replies: abi.BoxList, states: abi.BoxList };
const StepArgs = extern struct { index: u64, state: ?*anyopaque };
const StepResult = extern struct { reply: ?*anyopaque, state: ?*anyopaque };

// Tickets serialize the whole transition in arrival order. Different states
// have separate queues. Handlers must terminate and must not wait for another
// message; they are pure functions and cannot reenter the host.
const Queue = struct {
    next: std.atomic.Value(usize) = .init(0),
    serving: std.atomic.Value(usize) = .init(0),

    fn lock(queue: *Queue) void {
        const ticket = queue.next.fetchAdd(1, .monotonic);
        while (queue.serving.load(.acquire) != ticket) std.Thread.yield() catch {};
    }

    fn unlock(queue: *Queue) void {
        _ = queue.serving.fetchAdd(1, .release);
    }
};

const Batch = struct {
    request: Request,
    result: Result,
    queues: []Queue,
    next_client: std.atomic.Value(usize) = .init(0),
    ready: std.atomic.Value(usize) = .init(0),
    worker_count: usize,

    fn run(batch: *Batch) void {
        _ = batch.ready.fetchAdd(1, .acq_rel);
        while (batch.ready.load(.acquire) != batch.worker_count) std.Thread.yield() catch {};
        const offsets = batch.request.offsets.slice();
        while (true) {
            const client = batch.next_client.fetchAdd(1, .monotonic);
            if (client >= offsets.len - 1) return;
            for (offsets[client]..offsets[client + 1]) |index| {
                const worker = batch.request.destinations.slice()[index];
                const queue = &batch.queues[worker];
                queue.lock();
                // Transfer the old boxed state's owned reference into Roc.
                // It returns ownership of its replacement and one reply.
                const args = StepArgs{ .index = index, .state = batch.result.states.slice()[worker] };
                const active = active_calls.fetchAdd(1, .monotonic) + 1;
                _ = peak_calls.fetchMax(active, .monotonic);
                const result = abi.invokeWith(StepResult, batch.request.step, &args);
                _ = active_calls.fetchSub(1, .monotonic);
                batch.result.states.slice()[worker] = result.state;
                batch.result.replies.slice()[index] = result.reply;
                queue.unlock();
            }
        }
    }
};

pub fn run(request: Request) Result {
    defer abi.release(request.initial);
    defer abi.release(request.step);
    defer abi.releasePlain(u64, request.destinations);
    defer abi.releasePlain(u64, request.offsets);
    // The Roc wrapper validates indices before entering the host.
    if (request.workers == 0 or request.offsets.len == 0) runtime.fail("Invalid stateful request");
    const result = Result{
        .states = abi.allocateResults(request.state_count),
        .replies = abi.allocateResults(request.destinations.len),
    };
    for (result.states.slice(), 0..) |*state, index| state.* = abi.invoke(request.initial, index);
    if (request.destinations.len == 0) return result;

    const queues = std.heap.c_allocator.alloc(Queue, request.state_count) catch runtime.fail("Cannot allocate state queues");
    defer std.heap.c_allocator.free(queues);
    for (queues) |*queue| queue.* = .{};
    const worker_count = @min(request.workers, request.offsets.len - 1, 64);
    var batch = Batch{ .request = request, .result = result, .queues = queues, .worker_count = worker_count };
    var threads: [64]std.Thread = undefined;
    for (threads[0..worker_count]) |*thread| {
        thread.* = std.Thread.spawn(.{}, Batch.run, .{&batch}) catch runtime.fail("Cannot start stateful worker");
    }
    for (threads[0..worker_count]) |thread| thread.join();
    return result;
}

// Exercise the actual scheduler with a deterministic rendezvous inside the
// handler: a global lock would deadlock here (the outer test runner times out).
test "different states execute concurrently and each state is serialized" {
    const Context = struct {
        entered: std.atomic.Value(usize) = .init(0),
        active: [2]std.atomic.Value(usize) = .{ .init(0), .init(0) },
        violated: std.atomic.Value(bool) = .init(false),

        fn call(_: ?*anyopaque, output: ?*anyopaque, input: ?*const anyopaque, captures: ?*anyopaque, _: ?*anyopaque, _: *?*const anyopaque) callconv(.c) void {
            const ctx = @as(**@This(), @ptrCast(@alignCast(captures.?))).*;
            const args: *const StepArgs = @ptrCast(@alignCast(input.?));
            const state: *[2]usize = @ptrCast(@alignCast(args.state.?));
            const id = state[0];
            if (ctx.active[id].fetchAdd(1, .acq_rel) != 0) ctx.violated.store(true, .release);
            if (state[1] == 0) {
                _ = ctx.entered.fetchAdd(1, .acq_rel);
                while (ctx.entered.load(.acquire) < 2) std.Thread.yield() catch {};
            }
            state[1] += 1;
            _ = ctx.active[id].fetchSub(1, .acq_rel);
            const result: *StepResult = @ptrCast(@alignCast(output.?));
            result.* = .{ .state = args.state, .reply = null };
        }
    };
    var context = Context{};
    const Callable = extern struct { header: abi.Closure, context: *Context align(16) };
    var callable = Callable{ .header = .{ .call = Context.call, .drop = null }, .context = &context };
    var a = [2]usize{ 0, 0 };
    var b = [2]usize{ 1, 0 };
    var states = [_]?*anyopaque{ &a, &b };
    var destinations = [_]u64{0} ** 2000;
    // The first two clients reach separate accounts, rendezvous, then all four
    // clients contend on both accounts. Each client has 500 commands.
    for (&destinations, 0..) |*destination, index| destination.* = (index + index / 500) % 2;
    var offsets = [_]u64{ 0, 500, 1000, 1500, 2000 };
    var replies = [_]?*anyopaque{null} ** 2000;
    var queues = [_]Queue{ .{}, .{} };
    var batch = Batch{
        .request = .{
            .state_count = 2,
            .workers = 4,
            .initial = undefined,
            .step = &callable.header,
            .destinations = .{ .ptr = &destinations, .len = destinations.len, .capacity = 0 },
            .offsets = .{ .ptr = &offsets, .len = offsets.len, .capacity = 0 },
        },
        .result = .{
            .states = .{ .ptr = &states, .len = states.len, .capacity = 0 },
            .replies = .{ .ptr = &replies, .len = replies.len, .capacity = 0 },
        },
        .queues = &queues,
        .worker_count = 4,
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Batch.run, .{&batch});
    for (threads) |thread| thread.join();
    try std.testing.expect(!context.violated.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1000), a[1]);
    try std.testing.expectEqual(@as(usize, 1000), b[1]);
}
