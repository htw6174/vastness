package view

import "core:c"
import "core:strings"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:fmt"

import sg "../sokol/gfx"
import fs "vendor:fontstash"
import "../platform"
import "../sim"

ASSET_DIR :: "../../assets/"

pass_action: sg.Pass_Action

State :: struct {
	frame:          u64,
	world:          ^sim.World,
	swapchain:      sg.Swapchain,

	canvas_pv:      Transform,
	camera_pv:      Transform,
	camera:         Camera,

	// debug quad
	debug_bindings: sg.Bindings,
	debug_pipeline: sg.Pipeline,

	// font & text
	font_context:   fs.FontContext,
	font_default:   int,
	fonts:          [4]int,
	font_state:     fs.State,
	font_atlas:     sg.Image,
	text_bindings:  sg.Bindings,
	text_pipeline:  sg.Pipeline,
	text_instances: []Font_Instance,
	// Pair of scratch buffers to hold the top 2 pages of glyphs when composing a text box
	text_instance_scratch: [2][]Font_Instance,
	text_buffer:    sg.Buffer,

	// text buffers
	text_boxes: [10]Text_Box,
	focused_text: int,

	// particles
	particle_bindings: sg.Bindings,
	particle_pipeline: sg.Pipeline,
	particle_instances: [dynamic]Particle_Instance,
	particle_buffer:   sg.Buffer,
}

Shapes :: struct {
	quad_index_buffer: sg.Buffer,
}

Font_Instance :: struct {
	pos_min: [2]f32,
	pos_max: [2]f32,
	uv_min:  [2]f32,
	uv_max:  [2]f32,
	depth:   f32, // TODO: remove; unused
	color:   Color,
}

Text_Uniforms :: struct {
    transform: Transform,
    boundary: Vec4,
    line_height: f32,
}

Text_Box :: struct {
    text: strings.Builder,
    font_state: fs.State,
    color: Color, // TODO: text box creation proc to ensure this defaults to an opaque value
    rect: Rect, // In screen-space pixels. Text will wrap before going over this rect's left or bottom
    // NOTE: for pixel fonts, prefer using native font size and scaling by whole numbers. For other fonts, prefer using a large font size and scaling down
    scale: f32, // font_state.size * scale = text height on screen. Use whole numbers to preserve pixel font rendering
    cursor: Vec2, // Bottom-right of the last character to be drawn
    // TODO: shouldn't a start & count just be a slice? Maybe no, because I need to set the vertex buffer offset later
    instance_start: int,
    instance_count: int,
    uniforms: Text_Uniforms,
}

Particle_Instance :: struct {
    position: Vec3,
}

Particle_Uniforms :: struct {
    pv: Transform,
}

Camera :: struct {
    position: Vec3,
    velocity: Vec3,
    rotation: quaternion128,
    angular_velocity: Vec3,
    fov: f32,
    near_clip: f32,
    far_clip: f32,
}

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Color :: [4]f32
Rect :: [4]f32 // .xy => position of top-left corner, .zw => width, height
Transform :: matrix[4, 4]f32

DEFAULT_FONT_ATLAS_SIZE :: 512
MAX_FONT_INSTANCES :: 1024 * 16
MAX_FONT_PAGE_INSTANCES :: 1024

MAX_PARTICLE_INSTANCES :: 1024 * 8

// TODO: embed in view state
shapes: Shapes

/* Callbacks used by Window */

init :: proc(state: ^State) {
    platform.window_init(_late_init, state)
}

_late_init :: proc(raw_state: rawptr, device: rawptr) {
    state := (^State)(raw_state)
	state.frame = 0

	// Initialize sokol_gfx
	pass_action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {0, 0, 0, 1},
	}

	state.camera = {
	    position = {0, 0, -10},
		rotation = linalg.QUATERNIONF32_IDENTITY,
	    near_clip = 0.1,
		far_clip = 1000,
		fov = 45,
	}

	sg.setup(
		sg.Desc {
			environment = {
				defaults = {color_format = .BGRA8, depth_format = .NONE},
				wgpu = {device = device},
			},
			logger = {func = platform.slog_func},
		},
	)
	assert(sg.query_backend() == .WGPU)

	state.swapchain = sg.Swapchain {
		width = 1280, // TODO: does this need to be the same as the window dimensions at startup?
		height = 720,
		sample_count = 1,
		color_format = .BGRA8,
		//depth_format = .DEPTH_STENCIL,
		wgpu = {render_view = nil, resolve_view = nil, depth_stencil_view = nil},
	}

	// input setup
	register_keybind({.RETURN, .PRESS, input_newline})
	register_keybind({.BACKSPACE, .PRESS, input_backspace})
	register_keybind({.E, .HOLD, camera_forward})
	register_keybind({.D, .HOLD, camera_back})
	register_keybind({.S, .HOLD, camera_left})
	register_keybind({.F, .HOLD, camera_right})

	state_init_shapes()

	// fontstash: init, add defult font
	state_init_font(state)
	state_init_debug(state)
	state_init_particles(state)

	// Construct some sample text boxes
	entry_box := Text_Box {
	    text = strings.builder_make(),
		font_state = {
		    font = state.fonts[0],
			size = 40,
			// Defaults: Left, Baseline
			ah = .LEFT,
			av = .TOP,
		},
		color = {1, 1, 1, 1},
		rect = {5, 5, 400, 192},
		scale = 1,
	}
	strings.write_string(&entry_box.text, "Hellope!\nYou can type into this box.\n>")
	state.text_boxes[0] = entry_box

    matrix_box := Text_Box {
	    text = strings.builder_make(),
		font_state = {
		    font = state.font_default,
			// NOTE: even though size is given as a float, shouldn't use anything smaller than the font's native pixel size
			// NOTE: for pixel fonts, I can use a smaller atlas by rendering them all at native pixel size, then scaling later with transforms
			// Some transform math might also be necessary to ensure pixel font quads are always screen pixel-aligned
			size = 20,
			// Defaults: Left, Baseline
			ah = .LEFT,
			av = .TOP,
		},
		color = {0, 1, 0, 1},
		rect = {500, 5, 1, 600}, // NOTE: width must be >0 for fadeout effect to work
		scale = 2,
	}

	state.text_boxes[2] = matrix_box
}

step :: proc(state: ^State) {
    render_view := platform.frame_begin()
    if render_view == nil {
        return
    } else {
        state.swapchain.wgpu.render_view = render_view
    }
    defer platform.frame_end()

    platform.poll_events(handle_event, state)
    handle_input_state(state)

	sg.begin_pass(sg.Pass{action = pass_action, swapchain = state.swapchain})

	width, height := platform.get_render_bounds()
	canvas_view := linalg.MATRIX4F32_IDENTITY // TODO?
	// NDC in Wgpu are -1, -1 at bottom-left of screen, +1, +1 at top-right
	canvas_perspective := linalg.matrix_ortho3d_f32(0, f32(width), f32(height), 0, -1, 1)
	state.canvas_pv = canvas_view * canvas_perspective
	view := linalg.matrix4_look_at_f32(state.camera.position, 0, {0, 1, 0})
	cam_view := linalg.MATRIX4F32_IDENTITY // TODO
	// NOTE: there is also mat4_perspective_infinite, might make more sense for a space game?
	cam_perspective := linalg.matrix4_perspective_f32(state.camera.fov, f32(width) / f32(height), state.camera.near_clip, state.camera.far_clip, flip_z_axis = true)
	state.camera_pv = cam_view * cam_perspective

	//state.camera.position.z = -2.0 + math.sin_f32(f32(state.frame) / 120.0)
	state.camera.position += state.camera.velocity * 0.0166 // TODO: use deltatime
	//state.camera.rotation = linalg.quaternion_look_at_f32(state.camera.position, 0, {0, 1, 0})
	state.camera.velocity = 0
	state.camera_pv = state.camera_pv *
	    linalg.matrix4_translate_f32(state.camera.position) *
		linalg.matrix4_from_quaternion_f32(state.camera.rotation)

	// Add asteroids to particle buffer
	clear(&state.particle_instances)
	for asteroid in state.world.asteroids {
	    append(&state.particle_instances, Particle_Instance{position_from_body(asteroid)})
	}
	sg.update_buffer(state.particle_buffer, range_from_slice(state.particle_instances[:]))

	draw_particles(state)

	draw_ui(state)

	// update matrix text box
	state.text_boxes[2].rect.x = f32(width) - 40
	if state.frame % 8 == 0 {
		if strings.builder_len(state.text_boxes[2].text) > 1024 do strings.builder_reset(&state.text_boxes[2].text)
	    rand_byte := u8(int('0') + rand.int_max(int('~') - int('0')))
	    strings.write_byte(&state.text_boxes[2].text, rand_byte)
	}

	// draw debug quad over top-right corner
	// sg.apply_pipeline(state.debug_pipeline)
	// sg.apply_bindings(state.debug_bindings)
	// sg.draw(0, 6, 1)

	sg.end_pass()
	sg.commit()
	state.frame += 1
}

fini :: proc(state: ^State) {
	sg.shutdown()
	platform.shutdown()
}

/* Graphics Setup */

// TODO: store default meshes in view state
state_init_shapes :: proc() {
	shapes.quad_index_buffer = sg.alloc_buffer()
	quad_indicies := []u32{0, 1, 2, 1, 2, 3}
	sg.init_buffer(
		shapes.quad_index_buffer,
		sg.Buffer_Desc {
			type = .INDEXBUFFER,
			usage = .IMMUTABLE,
			data = sg.Range{raw_data(quad_indicies), size_of(u32) * len(quad_indicies)},
		},
	)
}

state_init_particles :: proc(state: ^State) {
    state.particle_instances = make([dynamic]Particle_Instance, 0, MAX_PARTICLE_INSTANCES)

    particle_instance_buffer := sg.make_buffer({
        type = .VERTEXBUFFER,
        usage = .DYNAMIC,
        size = size_of(Particle_Instance) * MAX_PARTICLE_INSTANCES,
    })
    state.particle_buffer = particle_instance_buffer
    state.particle_bindings = {
        vertex_buffers = {0 = particle_instance_buffer},
        index_buffer = shapes.quad_index_buffer,
    }

    particle_shader := sg.make_shader({
        vertex_func = {source = #load(ASSET_DIR + "particle/vert.wgsl", cstring)},
        fragment_func = {source = #load(ASSET_DIR + "particle/frag.wgsl", cstring)},
        uniform_blocks = {
            0 = {
                stage = .VERTEX,
                size = size_of(Particle_Uniforms),
                wgsl_group0_binding_n = 0,
                layout = .NATIVE,
            }
        }
    })

    state.particle_pipeline = sg.make_pipeline({
        shader = particle_shader,
        layout = {
            buffers = {0 = {step_func = .PER_INSTANCE}},
            attrs = {
                0 = {format = .FLOAT3},
            }
        },
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
					src_factor_alpha = .SRC_ALPHA,
					dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                }
            }
        },
        index_type = .UINT32,
    })
}

state_init_debug :: proc(state: ^State) {
	debug_sampler := sg.make_sampler(
		sg.Sampler_Desc {
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			mipmap_filter = .LINEAR,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
			wrap_w = .CLAMP_TO_EDGE,
			min_lod = 0,
			max_lod = 32,
			max_anisotropy = 1,
		},
	)

	state.debug_bindings = {
		index_buffer = shapes.quad_index_buffer,
		images = {0 = state.font_atlas},
		samplers = {0 = debug_sampler},
	}

	debug_shader := sg.make_shader(
			sg.Shader_Desc {
				vertex_func = {source = #load(ASSET_DIR + "debug/vert.wgsl", cstring)},
				fragment_func = {source = #load(ASSET_DIR + "debug/frag.wgsl", cstring)},
				uniform_blocks = {
					// 0 = {
					// 	stage = .VERTEX,
					// 	size = size_of(Transform),
					// 	wgsl_group0_binding_n = 0,
					// 	layout = .NATIVE,
					// },
				},
				images = {
					0 = {
						stage = .FRAGMENT,
						image_type = ._2D,
						sample_type = .FLOAT,
						wgsl_group1_binding_n = 1,
					},
				},
				samplers = {
					0 = {stage = .FRAGMENT, sampler_type = .FILTERING, wgsl_group1_binding_n = 0},
				},
				image_sampler_pairs = {0 = {stage = .FRAGMENT, image_slot = 0, sampler_slot = 0}},
			},
		)

		state.debug_pipeline = sg.make_pipeline(
			sg.Pipeline_Desc {
				shader = debug_shader,
				colors = {
					0 = {
						blend = {
							enabled = true,
							src_factor_rgb = .SRC_ALPHA,
							dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
							src_factor_alpha = .SRC_ALPHA,
							dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
						},
					},
				},
				primitive_type = .TRIANGLES, // same as default
				index_type = .UINT32,
			},
		)
}

state_init_font :: proc(state: ^State) {
	// NB: fontstash init sets many font context fields but does not check for existing data. Set any overrides only after init
	fs.Init(&state.font_context, DEFAULT_FONT_ATLAS_SIZE, DEFAULT_FONT_ATLAS_SIZE, .TOPLEFT)
	state.font_context.userData = state
	state.font_context.callbackResize = font_resize_atlas
	state.font_context.callbackUpdate = font_update_atlas
	state.font_default = fs.AddFontMem(
		&state.font_context,
		"Default",
		// TODO: pick some system font with wide character support, like droid*
		#load(ASSET_DIR + "font/Darinia.ttf"),
		false,
	)
	state.fonts[0] = fs.AddFontMem(
	    &state.font_context,
		"Yulong",
		#load(ASSET_DIR + "font/Yulong-Regular.ttf"),
		false,
	)

	state.text_instances = make([]Font_Instance, MAX_FONT_INSTANCES)
	state.text_instance_scratch[0] = make([]Font_Instance, MAX_FONT_PAGE_INSTANCES)
	state.text_instance_scratch[1] = make([]Font_Instance, MAX_FONT_PAGE_INSTANCES)

	state.text_buffer = sg.make_buffer(
		sg.Buffer_Desc {
			type = .VERTEXBUFFER,
			usage = .DYNAMIC,
			size = size_of(Font_Instance) * MAX_FONT_INSTANCES,
		},
	)

	font_sampler := sg.make_sampler(
		sg.Sampler_Desc {
			min_filter = .LINEAR,
			mag_filter = .NEAREST,
			mipmap_filter = .NEAREST,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
			wrap_w = .CLAMP_TO_EDGE,
			min_lod = 0,
			max_lod = 32,
			max_anisotropy = 1,
		},
	)

	state.font_atlas = sg.make_image(
		sg.Image_Desc {
			width        = c.int(state.font_context.width),
			height       = c.int(state.font_context.height),
			usage        = .DYNAMIC,
			pixel_format = .R8, // NOTE: unsigned normal is the default if no postfix on pixel format in sokol_gfx
		},
	)

	state.text_bindings = {
		vertex_buffers = {0 = state.text_buffer},
		index_buffer = shapes.quad_index_buffer,
		images = {0 = state.font_atlas},
		samplers = {0 = font_sampler},
	}

	text_shader := sg.make_shader(
		sg.Shader_Desc {
			vertex_func = {source = #load(ASSET_DIR + "font/vert.wgsl", cstring)},
			fragment_func = {source = #load(ASSET_DIR + "font/frag.wgsl", cstring)},
			uniform_blocks = {
				0 = {
					stage = .VERTEX,
					size = size_of(Text_Uniforms),
					wgsl_group0_binding_n = 0,
					layout = .NATIVE,
				}
			},
			images = {
				0 = {
					stage = .FRAGMENT,
					image_type = ._2D,
					sample_type = .FLOAT,
					wgsl_group1_binding_n = 1,
				},
			},
			samplers = {
				0 = {stage = .FRAGMENT, sampler_type = .FILTERING, wgsl_group1_binding_n = 0},
			},
			image_sampler_pairs = {0 = {stage = .FRAGMENT, image_slot = 0, sampler_slot = 0}},
		},
	)

	state.text_pipeline = sg.make_pipeline(
		sg.Pipeline_Desc {
			shader = text_shader,
			layout = {
				buffers = {0 = {step_func = .PER_INSTANCE}},
				attrs = {
					0 = {format = .FLOAT2},
					1 = {format = .FLOAT2},
					2 = {format = .FLOAT2},
					3 = {format = .FLOAT2},
					4 = {format = .FLOAT},
					5 = {format = .FLOAT4},
				},
			},
			colors = {
				0 = {
					blend = {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
						src_factor_alpha = .SRC_ALPHA,
						dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
					},
				},
			},
			primitive_type = .TRIANGLES, // same as default
			index_type = .UINT32,
		},
	)
}

draw_ui :: proc(state: ^State) {

	fc := &state.font_context
	fs.BeginState(fc)
	defer fs.EndState(fc)

	sg.apply_pipeline(state.text_pipeline)
	box_instances := state.text_instances
    for &box in state.text_boxes {
        box_instances = draw_text_box(state, fc, &box, box_instances)
    }
}

draw_text_box :: proc(state: ^State, fc: ^fs.FontContext, text_box: ^Text_Box, instance_buffer: []Font_Instance) -> []Font_Instance {
    if strings.builder_len(text_box.text) == 0 do return instance_buffer[:]
    fs.PushState(fc)
    fs.__getState(fc)^ = text_box.font_state

	ascender, descender, line_height := fs.VerticalMetrics(fc)
	x_end: f32 = 0 // Just past end of current line
	y_bottom := line_height // Just below last line on current page
	rect := text_box.rect / text_box.scale // Effective area available to place glyphs
	// write glyph info into buffer
	quad: fs.Quad
	iter := fs.TextIterInit(fc, 0, 0, strings.to_string(text_box.text))
	// TODO: more flexible way to roll out glyphs over multiple frames
	glyph_max := min(len(state.text_instances), int(state.frame))
	scratch_index := 0
	curr_length, prev_length := 0, 0 // Number of instances drawn on each page
	for i := 0; i < glyph_max && fs.TextIterNext(fc, &iter, &quad); i += 1 {
		state.text_instance_scratch[scratch_index][curr_length] = {
			pos_min = {quad.x0, quad.y0},
			pos_max = {quad.x1, quad.y1},
			uv_min  = {quad.s0, quad.t0},
			uv_max  = {quad.s1, quad.t1},
			// FIXME: why does the fragment shader interpret this as (1, 0, 0, 0) after unpacking?
			// Seems that the latter 3 bytes are always 0 in the vertex shader. Why?
			// Changing to a float4 fixes things, but why doesn't a ubyte4 work?
			color   = text_box.color,
		}
		curr_length += 1
		// Horizontal wrap on newline characters
		// FIXME: skip creating an instance for newline (and other whitespace?) characters, to avoid the font's 'missing' glyph appearing
		if iter.codepoint == '\n' {
		    iter.nextx = 0
			iter.nexty += line_height
			y_bottom += line_height
		}
		// Horizontal wrap on text box overflow
        // DESIRED BEHAVIOR: never draw a glyph with any part outside rect bounds. On horizontal overflow, move to next line. On vertical overflow, move to top-left (initial) position
	    // For now, just check nextx
		if iter.nextx > rect.z {
		    iter.nextx = 0
			iter.nexty += line_height
			y_bottom += line_height
		}
		// Vertical wrap on text box overflow
		if iter.nexty > rect.w {
		    // Swap which scratch buffer we're using
			prev_length = curr_length
			curr_length = 0
			scratch_index = 1 - scratch_index
		    // Can't just set nexty to 0; IterInit adds to the initial y based on state properties. Need to re-initialize iterator with remaining text
		    iter = fs.TextIterInit(fc, 0, 0, strings.to_string(text_box.text)[i+1:])
			y_bottom = line_height
		}
		// TODO: place at end of final character
		x_end = iter.nextx
	}
	// Shader instance index always starts at 0, so boundary must be relative to first instance drawn
	text_box.uniforms.boundary = {x_end / rect.z, y_bottom, f32(prev_length), rect.w - (math.remainder(rect.w, line_height))}
	text_box.uniforms.line_height = line_height
	text_box.instance_count = prev_length + curr_length

	// Copy scratch buffers into main instance buffer
	// Must copy prior scratch buffer first, and last used second
	// TODO: bounds checking
	scratch_prev := state.text_instance_scratch[1 - scratch_index]
	scratch_curr := state.text_instance_scratch[scratch_index]
	copy_slice(instance_buffer, scratch_prev[:prev_length])
	copy_slice(instance_buffer[prev_length:], scratch_curr[:curr_length])


	fs.PopState(fc)

	// TODO: only update instances that were written to this frame
	offset := sg.append_buffer(
		state.text_buffer,
		range_from_slice(instance_buffer[:text_box.instance_count]),
	)

	state.text_bindings.vertex_buffer_offsets[0] = offset
	sg.apply_bindings(state.text_bindings)

	text_box.uniforms.transform =
	    state.canvas_pv *
		linalg.matrix4_translate_f32({text_box.rect.x, text_box.rect.y, 0}) *
		linalg.matrix4_scale_f32(text_box.scale)
	sg.apply_uniforms(0, range_from_type(&text_box.uniforms))
	sg.draw(0, 6, text_box.instance_count)

	return instance_buffer[text_box.instance_count:]
}

draw_particles :: proc(state: ^State) {
    sg.apply_pipeline(state.particle_pipeline)
    sg.apply_bindings(state.particle_bindings)
    uniforms := Particle_Uniforms{pv = state.camera_pv}
    sg.apply_uniforms(0, range_from_type(&uniforms))
    sg.draw(0, 6, len(state.particle_instances))
}

font_resize_atlas :: proc(data: rawptr, w, h: int) {
    state := (^State)(data)
    // TODO
    unimplemented("Gotta resize that font atlas!")
}

// Must ignore the raw texture data passed as last param because the length has been discarded by a raw_data call, just use the context instead
font_update_atlas :: proc(data: rawptr, dirtyRect: [4]f32, _: rawptr) {
    state := (^State)(data)
	sg.update_image(
		state.font_atlas,
		{
			subimage = { // [cubemap face][mip level]sg.Range
				0 = {
					0 = range_from_slice(state.font_context.textureData)
				},
			},
		},
	)
}


/* Event Handling */

camera_forward :: proc(state: ^State) {
    state.camera.velocity.y = 1
}

camera_back :: proc(state: ^State) {
    state.camera.velocity.y = -1
}

camera_left :: proc(state: ^State) {
    state.camera.velocity.x = -1
}

camera_right :: proc(state: ^State) {
    state.camera.velocity.x = 1
}

// NOTE: raw_text is in a cstring format, i.e. 0-terminated and potentially with junk data after the terminator
input_text :: proc(state: ^State, raw_text: []u8) {
    text := string(cstring(raw_data(raw_text)))
    strings.write_string(&state.text_boxes[state.focused_text].text, text)
    //assert(strings.write_bytes(&state.user_console.text, raw_text) == len(raw_text))
}

input_newline :: proc(state: ^State) {
    strings.write_rune(&state.text_boxes[state.focused_text].text, '\n')
}

input_backspace :: proc(state: ^State) {
    //state.user_console.text = state.user_console.text[:math.max(0, len(state.user_console.text) - 1)]
    strings.pop_rune(&state.text_boxes[state.focused_text].text)
}

input_delete :: proc(state: ^State) {

}

/* Sokol utilities */

range_from_type :: proc(t: ^$T) -> sg.Range {
    return sg.Range{t, size_of(T)}
}

range_from_slice :: proc(s: []$T) -> sg.Range {
    return sg.Range{raw_data(s), len(s) * size_of(T)}
}

/* World visualization utilities */

// TODO: later this will probably be converting from orbit parameters to position
position_from_body :: proc(body: sim.Body) -> Vec3 {
    return Vec3{f32(body.position.x), f32(body.position.y), f32(body.position.z)}
}
