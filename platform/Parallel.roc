import Host

Parallel := [].{
	map! : List(a), { workers : U64, task : a -> b } => Try(List(b), [InvalidWorkerCount, ..])
	map! = |items, { workers, task }| {
		if workers == 0 {
			return Err(InvalidWorkerCount)
		}
		work = Box.box(
			|index| {
				item = items.get(index) ?? {
					crash "Invalid worker index"
				}
				Box.box({ value: task(item), marker: 0.U8 })
			},
		)
		Ok(Host.run!({ task: work, item_count: items.len(), workers }).map(|boxed| Box.unbox(boxed).value))
	}
}
