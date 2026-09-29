app [main!] { pf: platform "../platform/main.roc" }

import pf.Stderr

main! : List(Str) => Try(List(Str), [Exit(I8), Problem(Str), UnexpectedArguments(List(Str))])
main! = |args| {
	match args {
		["args", .. as values] => {
			Stderr.line!(Str.inspect(values))
			Ok(values)
		}
		["exit-zero"] => Err(Exit(0))
		["exit-positive"] => Err(Exit(7))
		["exit-negative"] => Err(Exit(-1))
		["error"] => Err(Problem(List.repeat("error details ", 8).fold("", Str.concat)))
		["stderr"] => {
			message = List.repeat("a long message ", 8).fold("", Str.concat)
			Stderr.line!(message)
			Stderr.line!(message)
			Ok([message, message])
		}
		[] => Ok(List.repeat("heap-allocated return value for the host to discard", 8))
		_ => Err(UnexpectedArguments(args))
	}
}
