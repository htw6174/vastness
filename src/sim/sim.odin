package sim

World :: struct {
	step: u64,
}

init :: proc() -> ^World {
	return new(World)
}

step :: proc(world: ^World) {
	world.step += 1
}

fini :: proc(world: ^World) {
	free(world)
}
