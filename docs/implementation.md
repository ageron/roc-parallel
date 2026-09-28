# Implementation

## Who calls whom?

1. The app calls the platform's Roc `Parallel.map!` wrapper.
2. The wrapper boxes a closure that captures the input list and the task. Given an index, it runs the task and boxes the result.
3. Zig receives a record containing `task`, `item_count`, and `workers`.
4. Workers claim distinct indices and invoke the compiled Roc closure. Each writes to its own output slot.
5. After joining every worker, Zig releases its closure reference and returns the boxed results. Roc unboxes them into the typed result list.

A one-byte marker in each result box keeps its representation nonempty, including when a task returns `{}`. The wrapper hides this detail from callers.

## Source tour

- `Parallel.roc` and `Host.roc`: generic Roc wrapper and native boundary.
- `host.zig`: scheduling and joining worker threads.
- `abi.zig`: the pinned compiler's boxed-closure and list representations.
- `runtime.zig`: thread-safe allocation through libc and allocation accounting.
- `tests/ParallelChecks.roc`: shared captures, sliced lists, returned closures, empty inputs, errors, and result-order checks.

The host owns one reference to the closure and lends it to workers by passing `null` for the boxed-callable ABI's `reuse` argument. This explicitly borrows the closure without transferring ownership. The host keeps it alive until every worker has joined, then releases its reference once. Roc's generated code manages references to captured values. See the pinned compiler's [boxed-callable ownership contract](https://github.com/roc-lang/roc/blob/220fd47/src/builtins/erased_callable.zig).

Reference counts track owned references, not threads. These borrowed calls do not require an extra closure reference per worker. A host that instead hands each worker an owned reference must retain each one before handing it over. Atomic reference counting makes concurrent count updates safe; it cannot compensate for missing ownership references. Results transfer back to Roc for typed cleanup. The example checks that all runtime allocations are released and reports the peak number of overlapping calls.

This demonstrates pure computation over Roc-owned data. It does not establish that arbitrary platform resource handles are safe to share between threads. A crash or allocation/thread-creation failure ends the process; there is no cancellation or recovery protocol.

The ABI is compiler-specific, not a stable public C interface. Builds use LLVM (`--opt=speed`), whose callbacks use linker-resolved runtime symbols. When upgrading, recheck the compiler's `src/builtins/erased_callable.zig`, `list.zig`, `utils.zig`, and `src/layout/field_order.zig`, then rerun the ownership checks.
