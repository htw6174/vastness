package sim

import "core:math/rand"

World :: struct {
	step: u64,

	// entities
	sun: Body, // TODO: list for binary or trinary systems?
	asteroids: [dynamic]Body,
}

Body :: struct {
    position: Position,
}

Position :: [3]f64

init :: proc(world: ^World) {
    world.asteroids = make([dynamic]Body, 0, 1024)

    // TEST a few randomly positioned bodies
    for i in 0..<20 {
        asteroid := Body{ position = {rand.float64_range(-5, 5), rand.float64_range(-3, 3), -2.0 + 4.0 * (f64(i) / 20.0)} }
        append(&world.asteroids, asteroid)
    }
}

step :: proc(world: ^World) {
	world.step += 1
}

fini :: proc(world: ^World) {
    delete(world.asteroids)
	free(world)
}
