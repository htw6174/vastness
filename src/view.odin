package main

import "core:c"
import "core:math/linalg"
import sg "sokol/gfx"
import fs "vendor:fontstash"

pass_action: sg.Pass_Action

ViewState :: struct {
	frame:          u64,
	font_context:   fs.FontContext,
	font_default:   int,
	font_state:     fs.State,
	font_atlas:     sg.Image,
	text_bindings:  sg.Bindings,
	text_pipeline:  sg.Pipeline,
	text_instances: []Font_Instance,
	text_buffer:    sg.Buffer,
	text_transform: Transform,
}

Font_Instance :: struct {
	pos_min: [2]f32,
	pos_max: [2]f32,
	uv_min:  [2]f32,
	uv_max:  [2]f32,
	color:   Color,
}

Color :: [4]u8
Transform :: matrix[4, 4]f32

DEFAULT_FONT_ATLAS_SIZE :: 512
MAX_FONT_INSTANCES :: 1024

@(private = "file")
state: ViewState

view_init :: proc() {
	state.frame = 0
	pass_action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {.5, .5, .5, 1},
	}

	// fontstash: init, add defult font
	state.font_context = {}
	fs.Init(&state.font_context, DEFAULT_FONT_ATLAS_SIZE, DEFAULT_FONT_ATLAS_SIZE, .BOTTOMLEFT)
	state.font_default = fs.AddFontMem(
		&state.font_context,
		"Default",
		#load("../assets/font/Not Jam Signature 17.ttf"),
		false,
	)

	state.text_transform = linalg.identity_matrix(Transform) // same as = 1

	state.text_instances = make([]Font_Instance, MAX_FONT_INSTANCES)

	font_instance_buffer := sg.alloc_buffer()
	state.text_buffer = font_instance_buffer
	font_index_buffer := sg.alloc_buffer()
	font_const_buffer := sg.alloc_buffer()
	sg.init_buffer(
		font_instance_buffer,
		sg.Buffer_Desc {
			type = .VERTEXBUFFER,
			usage = .DYNAMIC,
			size = size_of(Font_Instance) * MAX_FONT_INSTANCES,
		},
	)
	glyph_verts := []u32{0, 1, 2, 1, 2, 3}
	sg.init_buffer(
		font_index_buffer,
		sg.Buffer_Desc {
			type = .INDEXBUFFER,
			usage = .IMMUTABLE,
			data = sg.Range{raw_data(glyph_verts), size_of(u32) * len(glyph_verts)},
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

	//font_update_atlas()

	state.text_bindings = {
		vertex_buffers = {0 = font_instance_buffer},
		index_buffer = font_index_buffer,
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
					wgsl_group0_binding_n = 2,
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
					4 = {format = .UBYTE4},
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
			primitive_type = .TRIANGLES,
			index_type = .UINT32,
		},
	)
}

view_draw :: proc(swapchain: sg.Swapchain) {
	sg.begin_pass(sg.Pass{action = pass_action, swapchain = swapchain})

	fs.ClearState(&state.font_context)

	//fs.SetFont(&state.font_context, 0)
	fs.BeginState(&state.font_context)
	fs.SetFont(&state.font_context, state.font_default)
	// NOTE: even though size is given as a float, shouldn't use anything smaller than the font's base pixel size
	fs.SetSize(&state.font_context, 34)
	//fs.SetColor(&state.font_context, Color{0, 0, 255, 255})
	// write glyph info into buffer
	message := "Hellope! quilt."
	quad: fs.Quad
	iter := fs.TextIterInit(&state.font_context, -80, 0, message)
	for i := 0; fs.TextIterNext(&state.font_context, &iter, &quad); i += 1 {
		state.text_instances[i] = {
			pos_min = {quad.x0, quad.y0},
			pos_max = {quad.x1, quad.y1},
			uv_min  = {quad.s0, quad.t0},
			uv_max  = {quad.s1, quad.t1},
			color   = Color{255, 255, 255, 255},
		}
	}
	fs.EndState(&state.font_context)

	// TODO: check if dirty / needs resize
	font_update_atlas()

	// TODO: helper for turning a slice/small array into sg.Range
	sg.update_buffer(
		state.text_buffer,
		{ptr = raw_data(state.text_instances), size = size_of(Font_Instance) * MAX_FONT_INSTANCES},
	)

	sg.apply_pipeline(state.text_pipeline)
	sg.apply_bindings(state.text_bindings)

	//scale := f32(state.frame % 64) / 64
	scale: f32 = 0.01
	state.text_transform = linalg.matrix4_scale_f32({scale, scale, scale})
	sg.apply_uniforms(0, {&state.text_transform, size_of(Transform)})
	sg.draw(0, 6, len(message))

	sg.end_pass()
	sg.commit()
	state.frame += 1
}

view_shutdown :: proc() {
	sg.shutdown()
}

// glyphs are only added to the atlas after fs.TextIterNext sees them for the first time. Between filling the text instance buffers and drawing, should check if atlas is dirty and update if so.
font_update_atlas :: proc() {
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
