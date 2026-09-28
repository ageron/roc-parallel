app [main!] { pf: platform "../platform/main.roc" }

import ParallelChecks

main! : () => U8
main! = || {
	ParallelChecks.run!() ?? {
		crash "Parallel checks failed"
	}
	0
}
