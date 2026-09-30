app [main!] { pf: platform "../platform/main.roc" }

import pf.Stateful
import pf.Stderr

main! = |_args| {
	client_commands = List.repeat([{ state_index: 0.U64, command: Add(1.U64) }], 1000)
	result = client_commands
		|> Stateful.run!({
			initial_states: [0.U64],
			num_workers: 8,
			handler: |state, command| match command {
				Add(amount) => {
					updated = state + amount
					{ state: updated, reply: updated }
				}
			},
		}) ? StatefulError
	if result.states != [1000] {
		return Err(WrongState(result.states))
	}
	Stderr.line!("Stateful counter passed")
	Ok({})
}
