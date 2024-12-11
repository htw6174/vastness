package main

import sg "sokol/gfx"
/* Custom vendor packages made to work with wasm */
import sdl2 "sdl2"
import wgpu "wgpu"


window_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return wgpu.InstanceCreateSurface(
		instance,
		&wgpu.SurfaceDescriptor {
			nextInChain = &wgpu.SurfaceDescriptorFromCanvasHTMLSelector {
				sType = .SurfaceDescriptorFromCanvasHTMLSelector,
				selector = "#canvas",
			},
		},
	)
}

foreign _ {
	slog_func :: proc "c" (tag: cstring, log_level: u32, log_item_id: u32, message: cstring, line: u32, filename: cstring, usr_data: rawptr) ---
}
