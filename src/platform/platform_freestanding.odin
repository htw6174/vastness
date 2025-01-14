package platform

import "base:runtime"
import "core:c"
import "core:fmt"

/* Custom vendor packages made to work with wasm */
import sdl2 "sdl2"
import wgpu "wgpu"

WindowState :: struct {
	initialized: bool,
	initialized_callback: proc(user_data: rawptr, device: rawptr),
	want_quit:   bool,
	window:      ^sdl2.Window,
	instance:    wgpu.Instance,
	surface:     wgpu.Surface,
	adapter:     wgpu.Adapter,
	device:      wgpu.Device,
	config:      wgpu.SurfaceConfiguration,
	surface_changed: bool,
	render_texture: wgpu.SurfaceTexture,
	render_view: wgpu.TextureView,
	resolve_texture: wgpu.Texture, // TODO: currently not using msaa resolve
	resolve_view: wgpu.TextureView,
	depth_stencil_texture: wgpu.Texture,
	depth_stencil_view: wgpu.TextureView,
}

// Required for callbacks from wgpu
ctx: runtime.Context

@(private = "file")
state: WindowState

// expose SDL input stuff to module without requiring SDL import
Event :: sdl2.Event
Event_Type :: sdl2.EventType
Keycode :: sdl2.Keycode
Scancode :: sdl2.Scancode
Bind_Trigger :: enum u32 {
    HOLD = 0,
    PRESS = u32(sdl2.EventType.KEYUP),
    RELEASE = u32(sdl2.EventType.KEYDOWN),
}
scancode_from_keycode :: sdl2.GetScancodeFromKey
start_text_input :: sdl2.StartTextInput
stop_text_input :: sdl2.StopTextInput
is_text_input_active :: sdl2.IsTextInputActive

// timing
get_counter_frequency :: sdl2.GetPerformanceFrequency
get_counter :: sdl2.GetPerformanceCounter

Event_Handler :: proc(event: ^Event, user_data: rawptr)
Get_Keyboard_State :: sdl2.GetKeyboardStateAsSlice

window_init :: proc(initialized_callback: proc(user_data: rawptr, device: rawptr), user_data: rawptr) {
    ctx = context
    state.initialized_callback = initialized_callback

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
	state.surface = get_surface(state.instance)

	wgpu.InstanceRequestAdapter(
		state.instance,
		&{compatibleSurface = state.surface},
		on_adapter,
		user_data,
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
		wgpu.AdapterRequestDevice(adapter, nil, on_device, userdata)
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

		// TODO: why does this fill with junk on wasm?
		// Not sure what's wrong, but hardcoding the surface color format is fine for now
		// capabilities := wgpu.SurfaceGetCapabilities(state.surface, state.adapter)
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
			presentMode = .FifoRelaxed,
			//alphaMode   = .Opaque,
		}
		swapchain_create()

		state.initialized = true
		state.initialized_callback(userdata, device)
	}
}

Frame_State :: struct {
    // if true, render surface is ready and can be presented to. Functionally identical to render_view == nil
    ready: bool,
    // true if size of display surface changed since last frame
    surface_changed: bool,
    render_view: rawptr,
    resolve_view: rawptr,
    depth_stencil_view: rawptr,
}

// return true
frame_begin :: proc() -> Frame_State {
    frame := Frame_State{ready = false}
	if !state.initialized {
		return frame
	}

	// FIXME: browser wgpu reports that the depth texture size is lagging behind the surface texture, causing size mismatches briefly when resizing. Doesn't seem to break anything, but fixing would reduce logspam.
	if state.surface_changed {
        frame.surface_changed = true
	    swapchain_refresh()
		state.surface_changed = false
	}

	state.render_texture = wgpu.SurfaceGetCurrentTexture(state.surface)
	// check texture status, re-configure surface if needed
	switch state.render_texture.status {
	case .Success:
	case .Timeout, .Outdated, .Lost:
		slog_basic("Surface changed, reconfiguring...")
		if state.render_texture.texture != nil {
			wgpu.TextureRelease(state.render_texture.texture)
		}
		swapchain_refresh()
		// TODO: potential bug here where a resize happens on the same frame as another surface change, but the view returns before handling the resize
		// ^ Could also cause a swapchain refresh to happen twice in one frame, wasting work
		return frame
	case .DeviceLost, .OutOfMemory:
		panic("Surface texture device error")
	}
	state.render_view = wgpu.TextureCreateView(state.render_texture.texture)
	frame.ready = true
	frame.render_view = state.render_view
	frame.resolve_view = state.resolve_view
	frame.depth_stencil_view = state.depth_stencil_view
	return frame
}

poll_events :: proc(event_callback: Event_Handler, user_data: rawptr) {
	sdl2.PumpEvents()
	event: sdl2.Event
	for sdl2.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
		    state.want_quit = true
		case .WINDOWEVENT:
		    if event.window.event == .SIZE_CHANGED {
				// NOTE: window pixel width and height available in e.window.data1 & data2
				state.surface_changed = true
			}
		case .KEYDOWN:
			#partial switch event.key.keysym.sym {
			case .ESCAPE:
			    state.want_quit = true
			// TODO: request exit (only on desktop!)
			case .BACKQUOTE:
			    if sdl2.IsTextInputActive() {
					sdl2.StopTextInput()
				} else {
				    sdl2.StartTextInput()
				}
			}
		}
		event_callback(&event, user_data)
	}
}

frame_end :: proc() {
    // NB: do *not* wgpu.SurfacePresent in this target
    wgpu.TextureViewRelease(state.render_view)
    wgpu.TextureRelease(state.render_texture.texture)
}

shutdown :: proc() {
	sdl2.Quit()
}

should_quit :: proc() -> bool {
    return state.want_quit
}

@(private)
get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
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

@(private)
swapchain_create :: proc() {
    state.config.width, state.config.height = get_render_bounds()
    wgpu.SurfaceConfigure(state.surface, &state.config)

	depth_scencil_descriptor := wgpu.TextureDescriptor{
	    usage = {.RenderAttachment},
		dimension = ._3D, // FIXME: this should be ._2D, but seems like the emscripten dimension enum is one off from wgpu-native
		size = {
		    width = state.config.width,
			height = state.config.height,
			depthOrArrayLayers = 1,
		},
		format = .Depth32Float,
		mipLevelCount = 1,
		sampleCount = 1, // TODO: how to determine? Must match other render textures?
	}
	state.depth_stencil_texture = wgpu.DeviceCreateTexture(state.device, &depth_scencil_descriptor)
	state.depth_stencil_view = wgpu.TextureCreateView(state.depth_stencil_texture)
}

@(private)
swapchain_release :: proc() {
    if state.resolve_view != nil do wgpu.TextureViewRelease(state.resolve_view)
    if state.resolve_texture != nil do wgpu.TextureRelease(state.resolve_texture)
    if state.depth_stencil_view != nil do wgpu.TextureViewRelease(state.depth_stencil_view)
    if state.depth_stencil_texture != nil do wgpu.TextureRelease(state.depth_stencil_texture)
}

@(private)
swapchain_refresh :: proc() {
    swapchain_release()
    swapchain_create()
}

get_render_bounds :: proc() -> (width, height: u32) {
	dw, dh: f64
	get_canvas_size(&dw, &dh)
	return u32(dw), u32(dh)
}

foreign _ {
	slog_func :: proc "c" (tag: cstring, log_level: u32, log_item_id: u32, message: cstring, line: u32, filename: cstring, usr_data: rawptr) ---
	get_canvas_size :: proc "c" (width, height: ^f64) ---
	emscripten_log :: proc "c" (flags: c.int, format: cstring, #c_vararg args: ..any)
}

log :: proc(message: string) {
    emscripten_log(0, cstring(message))
}

logf :: proc(format: string, args: ..any) {
    emscripten_log(0, cstring(format), ..args)
}

slog_basic :: proc(message: cstring, line: u32 = #line, file: cstring = #file) {
	slog_func("main", 3, 0, message, line, file, nil)
}

// Required for importing stb_truetype, because the freestanding lib is built with Odin's vendor libc
@(require, linkage = "strong", link_name = "__odin_libc_assert_fail")
__odin_libc_assert_fail :: proc "c" (func: cstring, file: cstring, line: i32, expr: cstring) -> ! {
	context = ctx
	loc := runtime.Source_Code_Location {
		file_path = string(file),
		line      = line,
		column    = 0,
		procedure = string(func),
	}
	context.assertion_failure_proc("runtime assertion", string(expr), loc)
}
