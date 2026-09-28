import pf.Parallel

ParallelChecks :: {}.{
	run! = || {
		for _ in 0..<20 {
			prefix = List.repeat("a captured heap string ", 8).fold("", Str.concat)
			items = List.repeat("input allocated on the calling thread", 64)
			task = |text| {
				message = prefix.concat(text)
				{ message, copies: [message, message], counts: Dict.from_list([(message, 2.U64)]) }
			}
			mapped = Parallel.map!(items, { workers: 4, task })?
			require(mapped == items.map(task))
			require(prefix.count_utf8_bytes() > 100)

			slices = items.drop_first(1).take_first(7)
			mapped_slices = Parallel.map!(slices, { workers: 16, task })?
			require(mapped_slices == slices.map(task))

			closures = Parallel.map!(
				["first", "second"],
				{
					workers: 2,
					task: |suffix| {
						captured = prefix.concat(suffix)
						|ending| captured.concat(ending)
					},
				},
			)?
			messages = closures.map(|f| f("!"))
			require(messages == [prefix.concat("first!"), prefix.concat("second!")])
		}

		ordered = Parallel.map!([3.U64, 1, 2], { workers: 3, task: |n| n * 10 })?
		require(ordered == [30, 10, 20])
		wide = Parallel.map!([1.U128, 2], { workers: 2, task: |n| (n, [n, n]) })?
		require(wide == [(1, [1, 1]), (2, [2, 2])])
		bounded = Parallel.map!([7.U64], { workers: U64.highest, task: |n| n + 1 })?
		require(bounded == [8])
		units = Parallel.map!([1.U64, 2], { workers: 2, task: |_| {} })?
		require(units == [{}, {}])
		empty = Parallel.map!([], { workers: 4, task: |n| n * 10.U64 })?
		require(empty == [])
		zero = Parallel.map!([], { workers: 0, task: |n| n * 10.U64 })
		require(zero.is_err())
		fallible = Parallel.map!(
			[1.U64, 0, 2],
			{
				workers: 3,
				task: |n| if n == 0 {
					Err(Zero)
				} else {
					Ok(10 // n)
				},
			},
		)?
		require(fallible == [Ok(10), Err(Zero), Ok(5)])
		Ok({})
	}
}

require = |condition| if condition {
	{}
} else {
	crash "Parallel result mismatch"
}
