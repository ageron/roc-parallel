import pf.Stateful

StatefulChecks :: {}.{
	run! = || {
		for num_workers in [1.U64, 2, 8, 64] {
			client_commands = List.repeat([{ state_index: 0.U64, command: 1.U64 }], 1000)
			counted = (client_commands |> Stateful.run!({ initial_states: [0.U64], num_workers, handler: add })) ? PlatformError
			require(counted.states == [1000], "lost counter updates")?
			replies = counted.replies.fold([], List.concat).sort_with(U64.order_relative_to)
			require(replies == ((1.U64..<1001).iter() |> List.from_iter), "reply does not belong to its atomic update")?
		}

		# Clients can address several states; their commands stay in order.
		result = ([[{ state_index: 0, command: 2 }, { state_index: 1, command: 3 }, { state_index: 0, command: 5 }], []] |> Stateful.run!({ initial_states: [0.U64, 100], num_workers: 4, handler: add })) ? PlatformError
		require(result.states == [7, 103] and result.replies == [[2, 103, 7], []], "client order or routing")?
		continued = ([[{ state_index: 1, command: 7 }]] |> Stateful.run!({ initial_states: result.states, num_workers: 1, handler: add })) ? PlatformError
		require(continued.states == [7, 110], "session continuation")?
		empty = ([[], []] |> Stateful.run!({ initial_states: [42.U64], num_workers: 8, handler: add })) ? PlatformError
		require(empty.states == [42] and empty.replies == [[], []], "empty client_commands")?
		none = ([] |> Stateful.run!({ initial_states: [], num_workers: 8, handler: add })) ? PlatformError
		require(none.states == [] and none.replies == [], "empty session")?
		zero = ([] |> Stateful.run!({ initial_states: [0], num_workers: 0, handler: add }))
		require(zero == Err(InvalidWorkerCount), "zero num_workers accepted")?
		bad = ([[{ state_index: 1, command: 1 }]] |> Stateful.run!({ initial_states: [0], num_workers: 2, handler: add }))
		require(bad == Err(InvalidStateIndex(1)), "invalid destination accepted")?

		for _ in 0..<20 {
			# Heap values, shared captures, and replies that alias state must
			# survive crossing threads, subsequent runs, and sliced inputs.
			prefix = List.repeat("captured heap prefix ", 10).fold("", Str.concat)
			original = List.repeat(prefix, 4)
			client_commands = List.repeat([{ state_index: 0.U64, command: "another heap allocated string" }], 32).drop_first(1)
			heap_result = (
				client_commands
					|> Stateful.run!({
						initial_states: original.drop_first(1).take_first(2),
						num_workers: 8,
						handler: |state, text| {
							next = state.concat(text)
							{ state: next, reply: { copies: [next, prefix], lookup: Dict.from_list([(text, next)]) } }
						},
					})
			) ? PlatformError
			require(heap_result.states.get(0) == Ok(prefix.concat(List.repeat("another heap allocated string", 31).fold("", Str.concat))), "heap state")?
			require(original == List.repeat(prefix, 4), "input state mutated")?
			require(heap_result.replies.len() == 31, "heap replies")?
		}
		units = ([[{ state_index: 0, command: {} }]] |> Stateful.run!({ initial_states: [{}], num_workers: 1, handler: |_, _| { state: {}, reply: {} } })) ? PlatformError
		require(units.states == [{}] and units.replies == [[{}]], "zero sized values")?
		wide = ([[{ state_index: 0, command: 2.U128 }]] |> Stateful.run!({ initial_states: [1.U128], num_workers: U64.highest, handler: |state, value| { state: state + value, reply: (state, value) } })) ? PlatformError
		require(wide.states == [3] and wide.replies == [[(1, 2)]], "wide values")?
		closures = (
			[[{ state_index: 0, command: " suffix" }]]
				|> Stateful.run!({
					initial_states: ["a captured state string that is heap allocated"],
					num_workers: 1,
					handler: |state, suffix| {
						{ state, reply: |end| state.concat(suffix).concat(end) }
					},
				})
		) ? PlatformError
		f = closures.replies.first()?.first()?
		require(f("!") == "a captured state string that is heap allocated suffix!", "returned closure")?
		Ok({})
	}
}

add : U64, U64 -> { state : U64, reply : U64 }
add = |state, amount| { state: state + amount, reply: state + amount }

require = |condition, message| if condition {
	Ok({})
} else {
	Err(AssertionFailed(message))
}
