package main

import "base:runtime"
import "core:mem"

import "sim"

ctx: runtime.Context

tempAllocatorData: [mem.Megabyte * 4]byte
tempAllocatorArena: mem.Arena

mainMemoryData: [mem.Megabyte * 16]byte
mainMemoryArena: mem.Arena

world: ^sim.World

when ODIN_OS != .Freestanding {
	main :: proc() {
		start()
		window_loop()
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

	world = sim.init()
	window_init()
}

@(export, link_name = "step")
step :: proc "contextless" () {
	context = ctx
	free_all(context.temp_allocator)

	window_draw()
	sim.step(world)
}

@(export, link_name = "stop")
stop :: proc "contextless" () {
	context = ctx

	window_shutdown()
	sim.fini(world)
}

slog_basic :: proc(message: cstring, line: u32 = #line, file: cstring = #file) {
	slog_func("main", 3, 0, message, line, file, nil)
}
