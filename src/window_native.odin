#+build !freestanding
package main

import "core:c"
import "core:fmt"
import sa "core:container/small_array"

import sg "sokol/gfx"
import slog "sokol/log"
import "vendor:sdl2"
import "vendor:wgpu"
import "vendor:wgpu/sdl2glue"

WindowState :: struct {
	initialized: bool,
	window:      ^sdl2.Window,
	instance:    wgpu.Instance,
	surface:     wgpu.Surface,
	adapter:     wgpu.Adapter,
	device:      wgpu.Device,
	config:      wgpu.SurfaceConfiguration,
	swapchain:   sg.Swapchain,
}

@(private = "file")
state: WindowState
// TODO: could implement this as a dictionary, allow creating other bindgroups and switching the active one
edit_binds: sa.Small_Array(256, Keybind)
control_binds: sa.Small_Array(256, Keybind)

slog_func := slog.func

// expose input enums to module without requiring SDL import
Keycode :: sdl2.Keycode
Bind_Trigger :: enum u32 {
    HOLD = 0,
    PRESS = u32(sdl2.EventType.KEYUP),
    RELEASE = u32(sdl2.EventType.KEYDOWN),
}

Keybind :: struct {
    keycode: Keycode,
    trigger: Bind_Trigger,
    callback: proc(),
}

window_init :: proc() {
	// Initialize SDL
	assert(sdl2.Init(sdl2.INIT_VIDEO) == 0, sdl2.GetErrorString())

	state.window = sdl2.CreateWindow(
		"Odin Game",
		sdl2.WINDOWPOS_CENTERED,
		sdl2.WINDOWPOS_CENTERED,
		1280,
		720,
		sdl2.WINDOW_SHOWN | sdl2.WINDOW_RESIZABLE,
	)
	assert(state.window != nil, sdl2.GetErrorString())
	sdl2.StopTextInput()

	// WebGPU setup
	state.instance = wgpu.CreateInstance(nil)
	if state.instance == nil {
		panic("WebGPU is not supported")
	}
	state.surface = window_get_surface(state.instance)

	wgpu.InstanceRequestAdapter(
		state.instance,
		&{compatibleSurface = state.surface},
		on_adapter,
		nil,
	)

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: cstring,
		userdata: rawptr,
	) {
		context = ctx
		if status != .Success || adapter == nil {
			fmt.panicf("request adapter failure: [%v] %s", status, message)
		}
		state.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, on_device)
	}

	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: cstring,
		userdata: rawptr,
	) {
		context = ctx
		if status != .Success || device == nil {
			fmt.panicf("request device failure: [%v] %s", status, message)
		}
		state.device = device

		width, height := window_get_render_bounds()

		// TODO: why does this fill with junk on wasm?
		// Not sure what's wrong, but hardcoding the surface color format is fine for now
		capabilities := wgpu.SurfaceGetCapabilities(state.surface, state.adapter)
		// assert(capabilities.formatCount > 0)
		// for i in 0 ..< capabilities.formatCount {
		// 	f := fmt.ctprintf("Format: %v", capabilities.formats[i])
		// 	slog_basic(f)
		// }
		// format := capabilities.formats[0]
		// assert(format != .Undefined)
		state.config = wgpu.SurfaceConfiguration {
			device      = state.device,
			usage       = {.RenderAttachment},
			format      = .BGRA8Unorm,
			width       = width,
			height      = height,
			presentMode = .FifoRelaxed,
			//alphaMode   = .Opaque,
		}
		wgpu.SurfaceConfigure(state.surface, &state.config)

		// Initialize sokol_gfx
		sg.setup(
			sg.Desc {
				environment = {
					defaults = {color_format = .BGRA8, depth_format = .NONE},
					wgpu = {device = device},
				},
				logger = {func = slog_func},
			},
		)
		assert(sg.query_backend() == .WGPU)

		state.swapchain = sg.Swapchain {
			width = i32(width),
			height = i32(height),
			sample_count = 1,
			color_format = .BGRA8,
			//depth_format = .DEPTH_STENCIL,
			wgpu = {render_view = nil, resolve_view = nil, depth_stencil_view = nil},
		}

		view_init()

		state.initialized = true
	}
}

window_loop :: proc() {
	counter_freq := sdl2.GetPerformanceFrequency()
	time_now := sdl2.GetPerformanceCounter()
	time_last := time_now
	acc: f64 = 0
	for !sdl2.QuitRequested() {
		time_now := sdl2.GetPerformanceCounter()
		dt := f64(time_now - time_last) / f64(counter_freq)
		acc += dt
		if acc > 1 {
			//fmt.printfln("last frame: %.3fms", dt * 1000)
			acc -= 1
		}
		step()
		time_last = time_now
	}
}

window_draw :: proc() {
	if !state.initialized {
		return
	}

	// event handling
	// TODO: SDL_StartTextInput is enabled by default on desktop, but disabled by default on mobile. Should add a hotkey and touchable area to begin console input and call SDL_StartTextInput, then end text input after de-selecting the console (or when on-screen keyboard is collapsed?)
	sdl2.PumpEvents()
	event: sdl2.Event
	binds: []Keybind
	if sdl2.IsTextInputActive() {
	    binds = sa.slice(&edit_binds)
	} else {
	    binds = sa.slice(&control_binds)
	}
	for sdl2.PollEvent(&event) {
		#partial switch event.type {
		case .WINDOWEVENT:
		    if event.window.event == .SIZE_CHANGED {
				// NOTE: window pixel width and height in e.window.data1 & data2
				configure_surface()
			}
		case .KEYDOWN:
			#partial switch event.key.keysym.sym {
			case .ESCAPE:
			// TODO: request exit (only on desktop!)
			case .BACKQUOTE:
			    if sdl2.IsTextInputActive() {
					sdl2.StopTextInput()
				} else {
				    sdl2.StartTextInput()
				}
			}
			for bind in binds {
 			    if event.key.keysym.sym == bind.keycode { //&& event.type == sdl2.EventType(bind.trigger) {
   					bind.callback()
				}
 			}
		// NOTE: only captures visible glyphs and non-newline whitespace
		case .TEXTINPUT:
			//s := string(cstring(raw_data(event.text.text[:])))
			input_text(event.text.text[:])
		}
	}

	// check keyboard state for held bindings
	keyboard_state := sdl2.GetKeyboardStateAsSlice()
	for bind in binds {
	    if bind.trigger == .HOLD {
			if keyboard_state[int(sdl2.GetScancodeFromKey(bind.keycode))] > 0 {
			    bind.callback()
			}
		}
	}

	render_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
	// check texture status, re-configure surface if needed
	switch render_texture.status {
	case .Success:
	case .Timeout, .Outdated, .Lost:
		slog_basic("Surface changed, reconfiguring...")
		if render_texture.texture != nil {
			wgpu.TextureRelease(render_texture.texture)
		}
		configure_surface()
		return
	case .DeviceLost, .OutOfMemory:
		panic("Surface texture device error")
	}
	defer wgpu.TextureRelease(render_texture.texture)
	render_view := wgpu.TextureCreateView(render_texture.texture)
	defer wgpu.TextureViewRelease(render_view)
	state.swapchain.wgpu.render_view = render_view
	// TODO: create and use depth buffer texture
	//state.swapchain.wgpu.depth_stencil_view =

	view_draw(state.swapchain)

	wgpu.SurfacePresent(state.surface)
}

window_shutdown :: proc() {
	view_shutdown()
	sdl2.Quit()
}

@(private = "file")
configure_surface :: proc() {
	state.config.width, state.config.height = window_get_render_bounds()
	state.swapchain.width = i32(state.config.width)
	state.swapchain.height = i32(state.config.height)
	wgpu.SurfaceConfigure(state.surface, &state.config)
}

window_get_render_bounds :: proc() -> (width, height: u32) {
	iw, ih: c.int
	sdl2.GetWindowSize(state.window, &iw, &ih)
	//ddpi, hdpi, vdpi: f32
	//sdl2.GetDisplayDPI(sdl2.GetWindowDisplayIndex(state.window), &ddpi, &hdpi, &fdpi)
	return u32(iw), u32(ih)
}

window_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return sdl2glue.GetSurface(instance, state.window)
}

window_register_edit_bind :: proc(keybind: Keybind) {
    sa.append(&edit_binds, keybind)
}

window_register_control_bind :: proc(keybind: Keybind) {
    sa.append(&control_binds, keybind)
}
