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

counter_freq: u64
counter_last: u64

when ODIN_OS != .Freestanding {
	main :: proc() {
		start()
		for !platform.should_quit() {
			step()
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

	counter_freq = platform.get_counter_frequency()
	counter_last = platform.get_counter()

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

	counter_now := platform.get_counter()
	counter_delta := counter_now - counter_last
	counter_last = counter_now
	dt := f32(counter_delta) / f32(counter_freq)

	sim.step(world, dt)
	view.step(view_state, dt)
}

@(export, link_name = "stop")
stop :: proc "contextless" () {
	context = ctx

	sim.fini(world)
	view.fini(view_state)
}
