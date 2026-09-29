app [main!] { pf: platform "../platform/main.roc" }

import pf.Parallel

main! : List(Str) => Try({}, [Exit(I8)])
main! = |_args| {
	offset = 10.U64
	result = Parallel.map!([1.U64, 2, 3], { workers: 2, task: |n| n + offset })
	match result {
		Ok([11, 12, 13]) => Ok({})
		_ => Err(Exit(1))
	}
}
