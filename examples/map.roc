app [main!] { pf: platform "../platform/main.roc" }

import pf.Parallel

main! : () => U8
main! = || {
	offset = 10.U64
	result = Parallel.map!([1.U64, 2, 3], { workers: 2, task: |n| n + offset })
	match result {
		Ok([11, 12, 13]) => 0
		_ => 1
	}
}
