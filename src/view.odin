package main

import "core:c"
import "core:strings"
import "core:math"
import "core:math/linalg"
import sg "sokol/gfx"
import fs "vendor:fontstash"

pass_action: sg.Pass_Action

View_State :: struct {
	frame:          u64,
	canvas_pv:      Transform,

	// debug quad
	debug_bindings: sg.Bindings,
	debug_pipeline: sg.Pipeline,

	// font & text
	font_context:   fs.FontContext,
	font_default:   int,
	font_state:     fs.State,
	font_atlas:     sg.Image,
	text_bindings:  sg.Bindings,
	text_pipeline:  sg.Pipeline,
	text_instances: []Font_Instance,
	text_buffer:    sg.Buffer,
	text_transform: Transform,

	// text buffers
	user_input: string
}

Shapes :: struct {
	quad_index_buffer: sg.Buffer,
}

Font_Instance :: struct {
	pos_min: [2]f32,
	pos_max: [2]f32,
	uv_min:  [2]f32,
	uv_max:  [2]f32,
	color:   Color,
}

Text_Box :: struct {
    text: string,
    font_state: fs.State,
    max_rect: Rect,
}

Color :: [4]f32
Rect :: [4]f32
Transform :: matrix[4, 4]f32

DEFAULT_FONT_ATLAS_SIZE :: 512
MAX_FONT_INSTANCES :: 1024

@(private = "file")
state: View_State
shapes: Shapes

/* Callbacks used by Window */

view_init :: proc() {
	state.frame = 0
	pass_action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {.5, .5, .5, 1},
	}

	state.user_input = "Hellope!\n>"

	state_init_shapes()

	// fontstash: init, add defult font
	state_init_font()
	state_init_debug()
}

view_draw :: proc(swapchain: sg.Swapchain) {
	sg.begin_pass(sg.Pass{action = pass_action, swapchain = swapchain})

	width, height := window_get_render_bounds()
	state.canvas_pv = linalg.matrix_ortho3d_f32(0, f32(width), f32(height), 0, -1, 1)

	fc := &state.font_context
	fs.ClearState(fc)

	//fs.SetFont(fc, 0)
	fs.BeginState(fc)
	fs.SetFont(fc, state.font_default)
	// NOTE: even though size is given as a float, shouldn't use anything smaller than the font's base pixel size
	fs.SetSize(fc, 40)
	// Defaults: Left, Baseline
	fs.SetAlignHorizontal(fc, .LEFT)
	fs.SetAlignVertical(fc, .BASELINE)
	// NOTE: in Odin's implementation of fontstash, this only sets the current state's color, which is unused by the library
	// Retrieve color from current state for writing instance data if you want to manage color through the state stack
	//fs.SetColor(fc, Color{0, 0, 255, 255})

	_, _, line_height := fs.VerticalMetrics(fc)
	// write glyph info into buffer
	// FIXME: why don't descenders appear on p and q in the handwritten 17 font?
	message := `Hellope!

	The quick brown fox
	jumped over
	the lazy dog.`
	quad: fs.Quad
	iter := fs.TextIterInit(fc, 0, 0, state.user_input)
	for i := 0; fs.TextIterNext(fc, &iter, &quad); i += 1 {
		state.text_instances[i] = {
			pos_min = {quad.x0, quad.y0},
			pos_max = {quad.x1, quad.y1},
			uv_min  = {quad.s0, quad.t0},
			uv_max  = {quad.s1, quad.t1},
			// FIXME: why does the fragment shader interpret this as (1, 0, 0, 0) after unpacking?
			// Seems that the latter 3 bytes are always 0 in the vertex shader. Why?
			// Changing to a float4 fixes things, but why doesn't a ubyte4 work?
			color   = Color{0, 0, 0, 1},
		}
        // TODO: detect overflow of text area
		if iter.codepoint == '\n' {
		    iter.nextx = 0
			iter.nexty += line_height
		}
	}

	// NOTE: EndState resets the dirty rect after calling the update callback (if it was set). If not using the callback, must check for updates before ending state.
	fs.EndState(fc)

	// TODO: helper for turning a slice/small array into sg.Range
	sg.update_buffer(
		state.text_buffer,
		{ptr = raw_data(state.text_instances), size = size_of(Font_Instance) * MAX_FONT_INSTANCES},
	)

	sg.apply_pipeline(state.text_pipeline)
	sg.apply_bindings(state.text_bindings)

	// NDC in Wgpu are -1, -1 at bottom-left of screen, +1, +1 at top-right
	//state.text_transform = linalg.matrix4_translate_f32({-1, 0.8, 0})
	scale: f32 = 1
	state.text_transform = linalg.matrix4_translate_f32({0, -0.2, 0}) * linalg.matrix4_scale_f32({scale, scale, scale}) * state.canvas_pv
	//state.canvas_pv = linalg.matrix4_scale_f32({scale, scale, scale}) * state.canvas_pv
	sg.apply_uniforms(0, {&state.text_transform, size_of(Transform)})
	sg.draw(0, 6, math.min(len(message), int(state.frame / 4)))

	// draw debug quad over full screen
	sg.apply_pipeline(state.debug_pipeline)
	sg.apply_bindings(state.debug_bindings)
	sg.draw(0, 6, 1)

	sg.end_pass()
	sg.commit()
	state.frame += 1
}

view_shutdown :: proc() {
	sg.shutdown()
}

/* Graphics Setup */

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

state_init_debug :: proc() {
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
				vertex_func = {source = #load("../assets/debug/vert.wgsl", cstring)},
				fragment_func = {source = #load("../assets/debug/frag.wgsl", cstring)},
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

state_init_font :: proc() {
	state.font_context = {
        callbackResize = font_resize_atlas,
        callbackUpdate = font_update_atlas,
	}
	fs.Init(&state.font_context, DEFAULT_FONT_ATLAS_SIZE, DEFAULT_FONT_ATLAS_SIZE, .TOPLEFT)
	state.font_default = fs.AddFontMem(
		&state.font_context,
		"Default",
		#load("../assets/font/Darinia.ttf"),
		false,
	)

	state.text_transform = linalg.identity_matrix(Transform) // in Odin, can also do mat4x4 = 1

	state.text_instances = make([]Font_Instance, MAX_FONT_INSTANCES)

	font_instance_buffer := sg.alloc_buffer()
	state.text_buffer = font_instance_buffer
	font_const_buffer := sg.alloc_buffer()
	sg.init_buffer(
		font_instance_buffer,
		sg.Buffer_Desc {
			type = .VERTEXBUFFER,
			usage = .DYNAMIC,
			size = size_of(Font_Instance) * MAX_FONT_INSTANCES,
		},
	)
	sg.init_buffer(
		font_const_buffer,
		sg.Buffer_Desc{type = .DEFAULT, usage = .DYNAMIC, size = size_of(Transform)},
	)

	font_sampler := sg.make_sampler(
		sg.Sampler_Desc {
			min_filter = .NEAREST,
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
		vertex_buffers = {0 = font_instance_buffer},
		index_buffer = shapes.quad_index_buffer,
		images = {0 = state.font_atlas},
		samplers = {0 = font_sampler},
	}

	text_shader := sg.make_shader(
		sg.Shader_Desc {
			vertex_func = {source = #load("../assets/font/vert.wgsl", cstring)},
			fragment_func = {source = #load("../assets/font/frag.wgsl", cstring)},
			uniform_blocks = {
				0 = {
					stage = .VERTEX,
					size = size_of(Transform),
					wgsl_group0_binding_n = 0,
					layout = .NATIVE,
				},
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
					4 = {format = .FLOAT4},
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

font_resize_atlas :: proc(data: rawptr, w, h: int) {
    // TODO
}

// Must ignore the raw texture data passed as last param because the length has been discarded by a raw_data call, just use the context instead
font_update_atlas :: proc(data: rawptr, dirtyRect: [4]f32, _: rawptr) {
	sg.update_image(
		state.font_atlas,
		{
			subimage = {
				0 = { 	// cubemap face
					0 = { 	// mip level
						ptr  = raw_data(state.font_context.textureData),
						size = len(state.font_context.textureData),
					},
				},
			},
		},
	)
}


/* Event Handling */

handle_text_input :: proc(raw_text: []u8) {
    text := string(cstring(raw_data(raw_text)))
    state.user_input = strings.concatenate({state.user_input, text})
}

handle_command_key :: proc() {
    // TODO:
    // backspace
    // enter
    // left/right
    // delete
}
