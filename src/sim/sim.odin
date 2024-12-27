package sim

import "core:math"
import "core:math/rand"
import "core:math/linalg"

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
    for i in 0..<200 {
        asteroid := Body{ position = {rand.float64_range(-7, 7), rand.float64_range(-4, 4), rand.float64_range(-7, 7)} }// -2.0 + 4.0 * (f64(i) / 20.0)} }
        append(&world.asteroids, asteroid)
    }
}

step :: proc(world: ^World) {
    for &body in world.asteroids {
        p: [4]f64
        p.xyz = body.position.xyz
        p.w = 1
        body.position = (p * linalg.matrix4_rotate_f64(math.PI / 60.0, {0, 1, 0})).xyz
    }

	world.step += 1
}

fini :: proc(world: ^World) {
    delete(world.asteroids)
	free(world)
}
