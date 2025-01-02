package sim

import "core:math"
import "core:math/rand"
import "core:math/linalg"

BIG_G :: 6.6743e-11 // the gravitational constant

World :: struct {
	step: u64,
	time_step: Seconds, // simulation time delta per step
	is_running: bool,

	// entities
	sun: Body, // TODO: list for binary or trinary systems?
	asteroids: [dynamic]Body,
}

Body :: struct {
    position: Position,
    velocity: Velocity,
    mass: Kilograms,
    radius: f32,
    hue: f32,
}

/* Unit definitions */

// Time
Seconds :: f64

// Distance
Meters :: f64
Position :: [3]Meters

// Velocity
MetersPerSecond :: f64
Velocity :: [3]MetersPerSecond

// Acceleration
Acceleration :: [3]f64

// Mass
Kilograms :: f64

init :: proc(world: ^World) {
    world.time_step = 43200
    world.is_running = true

    world.sun = Body {
        mass = 1.989e30,
        radius = 2,
        hue = 0.2,
    }

    world.asteroids = make([dynamic]Body, 0, 1024)
    // TEST a few randomly positioned bodies
    // orbit radius
    earth_r := 149.596e9
    mars_r := 227.923e9
    // velocity along orbit direction
    earth_v := 29.78e3
    mars_v := 24.07e3
    for i in 0..<200 {
        interp := rand.float64() // random orbit distance between earth and mars
        r := math.lerp(earth_r, mars_r, interp)
        v := math.lerp(earth_v, mars_v, interp)
        theta := rand.float64() * math.TAU // random progression along orbit
        asteroid := Body{
            position = {math.sin(theta) * r, rand.float64_range(-20000, 20000), math.cos(theta) * r},
            velocity = {math.cos(theta) * v, 0, -math.sin(theta) * v},
            radius = rand.float32_range(0.5, 2),
            hue = rand.float32(),
        }
        append(&world.asteroids, asteroid)
    }
}

step :: proc(world: ^World) {
    if world.is_running == false do return
    // calculate velocity from acceleration due to gravity
    for &body in world.asteroids {
        accel: Acceleration = 0
        // TEST: for now only consider sun in acceleration
        r := body.position - world.sun.position
        r_mag := linalg.length(r)
        //dist := linalg.distance(world.sun, body) // Square this later, so can use square distance instead
        a := -BIG_G * world.sun.mass / (r_mag * r_mag) // same as dot(r, r), but we need the length anyway
        accel += a * (r / r_mag)

        body.velocity += accel * world.time_step
    }

    // apply velocity
    for &body in world.asteroids {
        body.position += body.velocity * world.time_step
        // p: [4]f64
        // p.xyz = body.position.xyz
        // p.w = 1
        // body.position = (p * linalg.matrix4_rotate_f64(math.PI / 360.0, {0, 1, 0})).xyz
    }

	world.step += 1
}

fini :: proc(world: ^World) {
    delete(world.asteroids)
	free(world)
}
