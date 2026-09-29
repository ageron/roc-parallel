import Host

Stderr := [].{
	line! : Str => {}
	line! = |message| Host.stderr!(message.concat("\n").to_utf8())
}
