# roc-parallel

A small Roc platform that runs pure closures on native Zig worker threads.

```roc
results = Parallel.map!([1.U64, 2, 3], {
    workers: 2,
    task: |number| number * 10,
})?
```

Tasks can capture values and return strings, lists, dictionaries, records, closures, or `Try` values. Results keep their input order. `map!` waits for every task; an `Err` returned by a task stays in its result slot. Requesting zero workers returns `Err(InvalidWorkerCount)`.

## Use a release

Copy a `.tar.zst` URL from this repository's GitHub releases into your app header:

```roc
app [main!] { pf: platform "<release bundle URL>" }

import pf.Parallel
import pf.Stderr

main! : List(Str) => Try({}, [Exit(I8), ParallelError([InvalidWorkerCount])])
main! = |_args| {
    result = Parallel.map!([1.U64, 2, 3], { workers: 2, task: |n| n * 10 }) ? ParallelError
    Stderr.line!(Str.inspect(result))
    Ok({})
}
```

Run with `roc app.roc`, or use `roc --opt=speed app.roc` for an optimized LLVM build. Releases include prebuilt hosts for x64 and ARM64 macOS, Linux (static musl), and Windows (MinGW/UCRT). You do not need Zig or Python to use a release.

The dev backend passed the example and full ownership/concurrency checks on Apple Silicon macOS with Roc nightly `2026-09-28-9927ba8`. With the older `2026-09-12-220fd47` nightly, the dev-backend example segfaults; use `--opt=speed` with that compiler. Dev-backend support has not yet been verified on the other targets.

Roc's native ABI is evolving. Release notes record the compiler used for testing; compatibility with every nightly is not guaranteed. CI resolves the latest nightly once per run and tests the same compiler across operating systems. An optional workflow input lets maintainers test a particular nightly. There is no compiler-version rejection in the build scripts.

## Arguments and program results

Apps provide `main! : List(Str) => Try(_a, [Exit(I8), ..])`. Arguments contain only user-supplied arguments; the executable name is omitted. Windows arguments are read from the Unicode command line. Arguments that cannot be represented as valid UTF-8 are rejected with a message and exit status 2.

`Ok(value)` releases the value and exits successfully. `Err(Exit(code))` exits with the requested signed 8-bit code, without printing an error. Other errors are printed to stderr using `Str.inspect` and exit with status 1. On Unix, negative exit codes wrap to the low eight bits (`Exit(-1)` becomes 255); use nonnegative codes for portable conventions.

Import `pf.Stderr` and call `Stderr.line!(message)` for best-effort diagnostic output. For example, a test app can collect the errors returned by its test functions, print all failures and a summary, then return `Err(Exit(1))`. Ordinary runtime crashes still exit with status 2.

Host allocation checks run on every normal return. Set `ROC_PARALLEL_DIAGNOSTICS=1` to also print allocation and peak-concurrency diagnostics; ordinary successful programs are silent.

## Build and test

Install Roc, Zig 0.16.0, and Python 3, then run from this repository:

```sh
python3 scripts/build.py
python3 scripts/test.py
```

On Windows, use `python` if that is your Python 3 command. Building the host updates the target's link inputs in `platform/main.roc`. Generated libraries stay under the ignored `platform/targets/` directory.

To prepare a release bundle on macOS (Apple cross-builds may need an Apple SDK):

```sh
python3 scripts/build.py --all
python3 scripts/bundle.py
python3 scripts/test.py --bundle dist/<hash>.tar.zst
```

The bundle test serves the archive locally and compiles the examples through its URL, exercising the same package-loading path as a published release. It checks captures, returned closures, sliced lists, empty inputs, errors, ordering, wide and zero-sized values, command-line arguments, returned errors, and exit codes. The host checks that all Roc allocations are released at process exit.

Use `build.py --target x64mingw` for a single cross-build, then `test.py --target x64mingw --build-only --output-dir dist/windows` to produce test executables without running them.

## CI and releases

CI uses the LLVM backend (`--opt=speed`). The workflow builds all six targets on macOS and tests the archive on Apple Silicon macOS, Intel macOS, x64 Linux, ARM64 Linux, and x64 Windows. ARM64 Windows is cross-built but not executed. Pull requests, pushes to `main`, and a weekly schedule run the same checks.

To publish, run the **Build, test, and release** workflow from `main` with a new version such as `0.1.0`. Publication waits for every bundle test to pass and creates a GitHub release at the tested commit. Leaving the version empty runs checks without publishing. The release includes the content-addressed archive and a copyable platform URL. Use that exact URL in consuming apps, including Exercism’s `parallel-example.roc`: a fresh CI build can produce a different archive hash from a local build. No GitHub repository or release is created by local scripts.

## How it works

Each call starts up to `min(workers, items.len(), 64)` threads and joins them before returning. There is no persistent thread pool or cancellation. Allocation or thread-creation failures terminate the process.

Compiled Roc functions can run on multiple OS threads without a separate runtime instance per worker. The host must preserve ownership counts; Roc uses atomic reference counts for values that can reach the host. See [the implementation and ownership contract](docs/implementation.md) for a walkthrough of the small host and its ABI assumptions.

The host is intended for pure computation over Roc-owned data. Platform resource handles need their own thread-safety guarantees.

## License

MIT; see [LICENSE](LICENSE). Bundles also contain [the licenses for Zig and the bundled C runtimes](licenses/README.md).
