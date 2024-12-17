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

	// text buffers
	user_console: Text_Box,
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
    boundary: Vec3,
}

Text_Box :: struct {
    text: strings.Builder,
    font_state: fs.State,
    rect: Rect, // In screen-space pixels. Text will wrap before going over this rect's left or bottom
    scale: f32, // Use whole numbers to preserve pixel font rendering
    cursor: Vec2, // Bottom-right of the last character to be drawn
    first_visible_instance: int,
    visible_instance_count: int,
    uniforms: Text_Uniforms,
}

Vec2 :: [2]f32
Vec3 :: [3]f32
Color :: [4]f32
Rect :: [4]f32 // .xy => position of top-left corner, .zw => width, height
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

	state_init_shapes()

	// fontstash: init, add defult font
	state_init_font()
	state_init_debug()

	state.user_console = {
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
		rect = {5, 5, 300, 200},
		scale = 2,
	}
	strings.write_string(&state.user_console.text, "Hellope!\n>")

	placeholder := `Odin is a general-purpose programming language with distinct typing built for high performance, modern systems and data-oriented programming.
Odin is the C alternative for the Joy of Programming.
Odin has been designed for readability, scalability, and orthogonality of concepts. Simplicity is complicated to get right, clear is better than clever.
Odin allows for the highest performance through low-level control over the memory layout, memory management and custom allocators and so much more.
Odin is designed from the bottom up for the modern computer, with built-in support for SOA data types, array programming, and other features.
We go into programming because we love to solve problems. Why shouldn't our tools bring us joy whilst doing it? Enjoy programming again, with Odin!`
    strings.write_string(&state.user_console.text, placeholder)
}

view_draw :: proc(swapchain: sg.Swapchain) {
	sg.begin_pass(sg.Pass{action = pass_action, swapchain = swapchain})

	width, height := window_get_render_bounds()
	// NDC in Wgpu are -1, -1 at bottom-left of screen, +1, +1 at top-right
	state.canvas_pv = linalg.matrix_ortho3d_f32(0, f32(width), f32(height), 0, -1, 1)

	fc := &state.font_context
	fs.BeginState(fc)
	defer fs.EndState(fc)

	draw_text_box(fc, &state.user_console)

	// draw debug quad over top-right corner
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
		sg.Buffer_Desc{type = .DEFAULT, usage = .DYNAMIC, size = size_of(Text_Uniforms)},
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

draw_text_box :: proc(fc: ^fs.FontContext, text_box: ^Text_Box) {
    fs.PushState(fc)
    fs.__getState(fc)^ = text_box.font_state

	ascender, descender, line_height := fs.VerticalMetrics(fc)
	x_end: f32 = 0
	y_bottom := line_height
	// prev_page_start will be index of the first drawn instance
	curr_page_start, prev_page_start, last_instance: int = 0, 0, 0
	// write glyph info into buffer
	quad: fs.Quad
	iter := fs.TextIterInit(fc, 0, 0, strings.to_string(text_box.text))
	glyph_max := min(len(state.text_instances), int(state.frame))
	for i := 0; i < glyph_max && fs.TextIterNext(fc, &iter, &quad); i += 1 {
		state.text_instances[i] = {
			pos_min = {quad.x0, quad.y0},
			pos_max = {quad.x1, quad.y1},
			uv_min  = {quad.s0, quad.t0},
			uv_max  = {quad.s1, quad.t1},
			depth = f32(i),
			// FIXME: why does the fragment shader interpret this as (1, 0, 0, 0) after unpacking?
			// Seems that the latter 3 bytes are always 0 in the vertex shader. Why?
			// Changing to a float4 fixes things, but why doesn't a ubyte4 work?
			color   = Color{0, 0, 0, 1},
		}
		// Horizontal wrap on newline characters
		if iter.codepoint == '\n' {
		    iter.nextx = 0
			iter.nexty += line_height
			y_bottom += line_height
		}
		// Horizontal wrap on text box overflow
        // DESIRED BEHAVIOR: never draw a glyph with any part outside rect bounds. On horizontal overflow, move to next line. On vertical overflow, move to top-left (initial) position
	    // For now, just check nextx
		if iter.nextx > text_box.rect.z {
		    iter.nextx = 0
			iter.nexty += line_height
			y_bottom += line_height
		}
		// Vertical wrap on text box overflow
		if iter.nexty > text_box.rect.w {
		    // Can't just set nexty to 0; IterInit adds to the initial y based on state properties. Need to re-initialize iterator, or replicate TextIterInit's behavior
		    iter = fs.TextIterInit(fc, 0, 0, strings.to_string(text_box.text)[i+1:])
			y_bottom = line_height
			prev_page_start = curr_page_start
			curr_page_start = i + 1
		}
		// TODO: place at end of final character
		x_end = iter.nextx
		last_instance = i + 1
	}
	// Shader instance index always starts at 0, so boundary must be relative to first instance drawn
	text_box.uniforms.boundary = {x_end / text_box.rect.z, y_bottom, f32(curr_page_start - prev_page_start)}
	text_box.first_visible_instance = prev_page_start
	text_box.visible_instance_count = last_instance - prev_page_start

	fs.PopState(fc)

	// TODO: helper for turning a slice/small array into sg.Range
	sg.update_buffer(
		state.text_buffer,
		range_from_slice(state.text_instances[text_box.first_visible_instance:]),
	)

	sg.apply_pipeline(state.text_pipeline)
	sg.apply_bindings(state.text_bindings)

	text_box.uniforms.transform =
	    state.canvas_pv *
		linalg.matrix4_translate_f32({text_box.rect.x, text_box.rect.y, 0}) *
		linalg.matrix4_scale_f32(text_box.scale)
	sg.apply_uniforms(0, range_from_type(&text_box.uniforms))
	sg.draw(0, 6, text_box.visible_instance_count)
}

font_resize_atlas :: proc(data: rawptr, w, h: int) {
    // TODO
    unimplemented("Gotta resize that font atlas!")
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

// NOTE: raw_text is in a cstring format, i.e. 0-terminated and potentially with junk data after the terminator
input_text :: proc(raw_text: []u8) {
    text := string(cstring(raw_data(raw_text)))
    strings.write_string(&state.user_console.text, text)
    //assert(strings.write_bytes(&state.user_console.text, raw_text) == len(raw_text))
}

input_newline :: proc() {
    strings.write_rune(&state.user_console.text, '\n')
}

input_backspace :: proc() {
    //state.user_console.text = state.user_console.text[:math.max(0, len(state.user_console.text) - 1)]
    strings.pop_rune(&state.user_console.text)
}

input_delete :: proc() {

}

range_from_type :: proc(t: ^$T) -> sg.Range {
    return sg.Range{t, size_of(T)}
}

range_from_slice :: proc(s: []$T) -> sg.Range {
    return sg.Range{raw_data(s), len(s) * size_of(T)}
}
