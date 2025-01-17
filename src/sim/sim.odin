package sim

import "core:math"
import "core:math/rand"
import "core:math/linalg"

BIG_G :: 6.6743e-11 // the gravitational constant

MAX_BODIES :: 1024 * 16

World :: struct {
	step: u64,
	time: Seconds,
	time_step: Seconds, // simulation time delta per step
	is_running: bool,

	step_frequency_inv: f32, // 1/(number of steps per second); a step will happen when the dt accumulator is >step_frequency_inv
	dt_accumulator: f32,

	// entities
	bodies: [dynamic]Body,
	massive_bodies: int, // slice boundary, only first [massive_bodies] bodies contribute to gravitational acceleration
}

Body :: struct {
    position: Position,
    velocity: Velocity,
    mass: Kilograms,
    radius: Meters,
    hue: f32,
}

Orbital_Stats :: struct {
    orbit_radius: f64,
    orbit_velocity: f64,
}

/* Unit definitions */

// Time
Seconds :: i64

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
    world.step_frequency_inv = 1.0/60.0
    world.dt_accumulator = 0
    world.time_step = 43200
    world.is_running = false

    world.bodies = make([dynamic]Body, 0, MAX_BODIES)

    // sun + planets in massive body indicies
    {
        // sun
        append(&world.bodies, Body{
            mass = 1.989e30,
            radius = 139.3e6,
            hue = 0.2,
        })
        mercury := body_from_orbit(57.909e9, 47.36e3, 0)
        mercury.mass = 0.33011e24
        mercury.radius = 2.429e6
        mercury.hue = 0.8
        append(&world.bodies, mercury)
        venus := body_from_orbit(108.209e9, 35.02e3, 0)
        venus.mass = 4.8675e24
        venus.radius = 6.051e6
        venus.hue = 0.9
        append(&world.bodies, venus)
        earth := body_from_orbit(149.596e9, 29.78e3, 0)
        earth.mass = 5.9724e24
        earth.radius = 6.371e6
        earth.hue = 0.5
        append(&world.bodies, earth)
        mars := body_from_orbit(227.923e9, 24.07e3, 0)
        mars.mass = 0.64171e24
        mars.radius = 3.389e6
        mars.hue = 0
        append(&world.bodies, mars)
        ceres := body_from_orbit(414.0e9, 17.9e3, 0)
        ceres.mass = 9.3839e20
        ceres.radius = 939400.0 / 2.0
        ceres.hue = 0.3
        append(&world.bodies, ceres)
        jupiter := body_from_orbit(778.570e9, 13.0e3, 0)
        jupiter.mass = 1898.19e24
        jupiter.radius = 69.911e6
        jupiter.hue = 0.1
        append(&world.bodies, jupiter)
        saturn := body_from_orbit(1433.529e9, 9.68e3, 0)
        saturn.mass = 568.34e24
        saturn.radius = 58.232e6
        saturn.hue = 0.15
        append(&world.bodies, saturn)
        uranus := body_from_orbit(2872.463e9, 6.80e3, 0)
        uranus.mass = 86.813e24
        uranus.radius = 25.362e6
        uranus.hue = 0.6
        append(&world.bodies, uranus)
        neptune := body_from_orbit(4495.060e9, 5.43e3, 0)
        neptune.mass = 102.413e24
        neptune.radius = 24.622e6
        neptune.hue = 0.4
        append(&world.bodies, neptune)

        world.massive_bodies = len(world.bodies)
    }

    inner_r, outer_r := 227.923e9, 778.570e9
    inner_v, outer_v := 29.78e3, 13.0e3
    min_d, max_d := 10.0, 1000.0 // size of asteroids
    max_elevation := 100000.0
    for i in 0..<4096 {
        r := rand.float64()
        r = r*r // square to get uniform density within circle
        v := math.lerp(inner_v, outer_v, r) // small radius => high velocity
        r = math.lerp(inner_r, outer_r, r)
        theta := rand.float64() * math.TAU // random progression along orbit
        asteroid := body_from_orbit(r, v, theta)
        asteroid.position.z = rand.float64_range(-max_elevation, max_elevation)
        asteroid.radius = rand.float64_range(min_d, max_d)
        asteroid.hue = rand.float32()
        append(&world.bodies, asteroid)
    }
}

step :: proc(world: ^World, dt: f32) {
    if world.is_running == false do return
    world.dt_accumulator += dt
    for world.dt_accumulator > world.step_frequency_inv {
        sim_step(world)
        world.dt_accumulator -= world.step_frequency_inv
    }
}

@(private)
sim_step :: proc(world: ^World) {
    f_step := f64(world.time_step)
    // calculate velocity from acceleration due to gravity
    for &body in world.bodies {
        accel: Acceleration = 0

        massive_bodies := world.bodies[:world.massive_bodies]
        for mass in massive_bodies {
            r := body.position - mass.position
            r_mag := linalg.length(r)
            if (r_mag < mass.radius) { // either the same body or about to make a singularity. Either way, don't want to factor into acceleration
                continue
            }
            //dist := linalg.distance(world.sun, body) // Square this later, so can use square distance instead
            a := -BIG_G * mass.mass / (r_mag * r_mag) // demoninator is same as dot(r, r)
            accel += a * (r / r_mag)
        }

        body.velocity += accel * f_step
    }

    // apply velocity
    for &body in world.bodies {
        body.position += body.velocity * f_step
    }

	world.step += 1
	world.time += world.time_step
}

fini :: proc(world: ^World) {
    delete(world.bodies)
	free(world)
}

body_from_orbit :: proc(radius, velocity, theta: f64) -> Body {
    return Body{
        position = {math.cos(theta) * radius, math.sin(theta) * radius, 0},
        velocity = {-math.sin(theta) * velocity, math.cos(theta) * velocity, 0},
    }
}
