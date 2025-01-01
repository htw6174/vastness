package main

import "base:runtime"
import "core:mem"

import "platform"
import "sim"
import "view"

ctx: runtime.Context

tempAllocatorData: [mem.Megabyte * 4]byte
tempAllocatorArena: mem.Arena

mainMemoryData: [mem.Megabyte * 16]byte
mainMemoryArena: mem.Arena

view_state: ^view.State
world: ^sim.World

when ODIN_OS != .Freestanding {
	main :: proc() {
		start()
		counter_freq := platform.get_counter_frequency()
		time_now := platform.get_counter()
		time_last := time_now
		acc: f64 = 0
		for !platform.should_quit() {
			time_now := platform.get_counter()
			dt := f64(time_now - time_last) / f64(counter_freq)
			acc += dt
			if acc > 1 {
				//fmt.printfln("last frame: %.3fms", dt * 1000)
				acc -= 1
			}
			step()
			time_last = time_now
		}
		stop()
	}
}

@(export, link_name = "start")
start :: proc "c" () {
	ctx = runtime.default_context()
	context = ctx

	// Initialize the allocators used in this application.
	mem.arena_init(&mainMemoryArena, mainMemoryData[:])
	mem.arena_init(&tempAllocatorArena, tempAllocatorData[:])
	ctx.allocator = mem.arena_allocator(&mainMemoryArena)
	ctx.temp_allocator = mem.arena_allocator(&tempAllocatorArena)

	context = ctx

	// Test the allocator works
	x := new(i64)
	assert(x != nil)
	free(x)

	world = new(sim.World)
	sim.init(world)

	view_state = new(view.State)
	view_state.world = world
	view.init(view_state)
}

@(export, link_name = "step")
step :: proc "contextless" () {
	context = ctx
	free_all(context.temp_allocator)

	//sim.step(world)
	view.step(view_state)
}

@(export, link_name = "stop")
stop :: proc "contextless" () {
	context = ctx

	sim.fini(world)
	view.fini(view_state)
}
