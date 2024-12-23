package sim

World :: struct {
	step: u64,

	// entities
	sun: Body, // TODO: list for binary or trinary systems?
	asteroids: []Body,
}

Body :: struct {
    position: Position,
}

Position :: [3]f64

init :: proc() -> ^World {
    world := new(World)
    world.asteroids = make([]Body, 1024)
	return world
}

step :: proc(world: ^World) {
	world.step += 1
}

fini :: proc(world: ^World) {
    delete(world.asteroids)
	free(world)
}
