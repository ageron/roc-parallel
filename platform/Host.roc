Host := [].{
	run! : { task : Box(U64 -> Box({ value : a, marker : U8 })), item_count : U64, workers : U64 } => List(Box({ value : a, marker : U8 }))
	stderr! : List(U8) => {}
}
