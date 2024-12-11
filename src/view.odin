package main

import sg "sokol/gfx"

pass_action: sg.Pass_Action

view_init :: proc() {
	pass_action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {1, 0, 0, 1},
	}
}

view_draw :: proc(swapchain: sg.Swapchain) {
	g := pass_action.colors[0].clear_value.g + 0.01
	pass_action.colors[0].clear_value.g = g > 1 ? 0 : g
	sg.begin_pass(sg.Pass{action = pass_action, swapchain = swapchain})
	sg.end_pass()
	sg.commit()
}

view_shutdown :: proc() {
	sg.shutdown()
}
