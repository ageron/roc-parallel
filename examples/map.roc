app [main!] { pf: platform "../platform/main.roc" }

import pf.Parallel
import pf.Stderr

main! : List(Str) => Try({}, [Exit(I8), ParallelError([InvalidWorkerCount])])
main! = |_args| {
	offset = 10.U64
	result = [1.U64, 2, 3] |> Parallel.map!({ workers: 2, task: |n| n + offset }) ? ParallelError
	Stderr.line!(Str.inspect(result))
	Ok({})
}
