app [main!] { pf: platform "../platform/main.roc" }

import ParallelChecks

main! : List(Str) => Try({}, [Exit(I8), CheckFailed(Str)])
main! = |_args| {
	ParallelChecks.run!() ? |error| CheckFailed(Str.inspect(error))
	Ok({})
}
