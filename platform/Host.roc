Host := [].{
	run! : { task : Box(U64 -> Box({ value : a, marker : U8 })), item_count : U64, workers : U64 } => List(Box({ value : a, marker : U8 }))
	stateful! : {
		state_count : U64,
		workers : U64,
		destinations : List(U64),
		offsets : List(U64),
		initial : Box(U64 -> Box({ value : state, marker : U8 })),
		step : Box({ index : U64, state : Box({ value : state, marker : U8 }) } -> { state : Box({ value : state, marker : U8 }), reply : Box({ value : reply, marker : U8 }) }),
	} => { states : List(Box({ value : state, marker : U8 })), replies : List(Box({ value : reply, marker : U8 })) }
	stderr! : List(U8) => {}
}
