import Host

## Concurrent clients sending commands to independently owned states.
Stateful := [].{

	## Each client is a sequential list of messages. Different clients may overlap.
	## `state_index` indexes `initial_states`. The handler's read/validate/update is atomic for
	## that state, including when it returns an error as its reply.
	## Replies retain client/message order; ordering between clients is unspecified.
	## This call joins every client. Pass the returned states to a later run to
	## continue a session. Invalid inputs run no commands.
	run! : List(List({ state_index : U64, command : command })), { initial_states : List(state), num_workers : U64, handler : state, command -> { state : state, reply : reply } } => Try({ states : List(state), replies : List(List(reply)) }, [InvalidWorkerCount, InvalidStateIndex(U64)])
	run! = |client_commands, { initial_states, num_workers, handler }| {
		if num_workers == 0 {
			return Err(InvalidWorkerCount)
		}
		messages = client_commands.fold([], |all, client| all.concat(client))
		for message in messages {
			if message.state_index >= initial_states.len() {
				return Err(InvalidStateIndex(message.state_index))
			}
		}
		offsets = client_commands.fold([0.U64], |starts, client| starts.append((starts.last() ?? 0) + client.len()))
		initial = Box.box(
			|index| Box.box({
				value: initial_states.get(index) ?? {
					crash "Invalid state index"
				},
				marker: 0.U8,
			}),
		)
		step = Box.box(
			|{ index, state }| {
				message = messages.get(index) ?? {
					crash "Invalid command index"
				}
				result = handler(Box.unbox(state).value, message.command)
				{ state: Box.box({ value: result.state, marker: 0.U8 }), reply: Box.box({ value: result.reply, marker: 0.U8 }) }
			},
		)
		result = Host.stateful!({ state_count: initial_states.len(), workers: num_workers, destinations: messages.map(|message| message.state_index), offsets, initial, step })
		replies = result.replies.map(|boxed| Box.unbox(boxed).value)
		Ok({
			states: result.states.map(|boxed| Box.unbox(boxed).value),
			replies: (0..<client_commands.len()).iter().map(
				|index| {
					start = offsets.get(index) ?? 0
					end = offsets.get(index + 1) ?? start
					replies.drop_first(start).take_first(end - start)
				},
			)
				|> List.from_iter,
		})
	}
}
