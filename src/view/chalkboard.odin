/*
Text boxes which create minimal motion when scrolling or adding new text outside the box boundaries by writing new text over old, and gradually fading out the background.
TODO: almost don't need central view state passed into these methods, just a ref to the chalkboard state. Also close to not needing linalg, would need general general purpose UI transform apply and draw
*/
package view

import "core:strings"
import "core:unicode"
// TODO: make use of common navigation and edit commands, cursors, other concepts from this package
import "core:text/edit"

import "core:c"
import "core:math"
import "core:math/linalg"
import "core:fmt"

import fs "vendor:fontstash"
import sg "../sokol/gfx"

DEFAULT_FONT_ATLAS_SIZE :: 512
MAX_FONT_INSTANCES :: 1024 * 16
MAX_FONT_PAGE_INSTANCES :: 1024

Chalkboard_State :: struct {
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
    instance_start: c.int,
    instance_count: c.int,
    uniforms: Text_Uniforms,
}

chalkboard_init :: proc(cb: ^Chalkboard_State) {
    // NB: fontstash init sets many font context fields but does not check for existing data. Set any overrides only after init
	fs.Init(&cb.font_context, DEFAULT_FONT_ATLAS_SIZE, DEFAULT_FONT_ATLAS_SIZE, .TOPLEFT)
	cb.font_context.userData = cb
	cb.font_context.callbackResize = font_resize_atlas
	cb.font_context.callbackUpdate = font_update_atlas
	cb.font_default = fs.AddFontMem(
		&cb.font_context,
		"Default",
		// TODO: pick some system font with wide character support, like droid*
		#load(ASSET_DIR + "font/Darinia.ttf"),
		false,
	)
	cb.fonts[0] = fs.AddFontMem(
	    &cb.font_context,
		"Yulong",
		#load(ASSET_DIR + "font/Yulong-Regular.ttf"),
		false,
	)
	cb.fonts[1] = fs.AddFontMem(
	    &cb.font_context,
		"Not Jam Mono",
		#load(ASSET_DIR + "font/Not Jam Mono Clean 8.ttf"),
		false,
	)

	test_setup(cb)
}

chalkboard_init_graphics :: proc(cb: ^Chalkboard_State) {
	cb.text_instances = make([]Font_Instance, MAX_FONT_INSTANCES)
	cb.text_instance_scratch[0] = make([]Font_Instance, MAX_FONT_PAGE_INSTANCES)
	cb.text_instance_scratch[1] = make([]Font_Instance, MAX_FONT_PAGE_INSTANCES)

	cb.text_buffer = sg.make_buffer(
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

	cb.font_atlas = sg.make_image(
		sg.Image_Desc {
		    // Must use minimum size in case device is ready before fonts load
			width        = c.int(math.max(cb.font_context.width, DEFAULT_FONT_ATLAS_SIZE)),
			height       = c.int(math.max(cb.font_context.height, DEFAULT_FONT_ATLAS_SIZE)),
			usage        = .DYNAMIC,
			pixel_format = .R8, // NOTE: unsigned normal is the default if no postfix on pixel format in sokol_gfx
		},
	)

	cb.text_bindings = {
		vertex_buffers = {0 = cb.text_buffer},
		index_buffer = shapes.quad_index_buffer,
		images = {0 = cb.font_atlas},
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

	cb.text_pipeline = sg.make_pipeline(
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

// Everything not required but included for sample chalkboards
test_setup :: proc(cb: ^Chalkboard_State) {
	// Construct some sample text boxes
	entry_box := Text_Box {
	    text = strings.builder_make(),
		font_state = {
		    font = cb.fonts[0],
			size = 40,
			// Defaults: Left, Baseline
			ah = .LEFT,
			av = .TOP,
		},
		color = {1, 1, 1, 1},
		rect = {8, 120, 400, 460},
		scale = 1,
	}
	strings.write_string(&entry_box.text, "E/S/D/F/T/G: Move\nClick+drag or\nQ/A/W/R/C/V: Rotate\nZ/X: Change scale\nB: toggle blur\nSpace: play/pause\n[/]: Change sim timescale\n-/=: Change sim steps per second\nPress ` to make this\ntext box active.")
	cb.text_boxes[0] = entry_box

	stats_box := Text_Box {
	    text = strings.builder_make(),
		font_state = {
		    font = cb.fonts[1],
			size = 8,
			// Defaults: Left, Baseline
			ah = .LEFT,
			av = .TOP,
		},
		color = {1, 1, 1, 1},
		rect = {8, 8, 1000, 400},
		scale = 2,
	}

	cb.text_boxes[1] = stats_box

	/*
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
		*/
}

// TODO: can almost eliminate need for outer view state here
draw_chalkboards :: proc(state: ^State) {
    cb := &state.chalkboard
	fc := &cb.font_context
	fs.BeginState(fc)
	defer fs.EndState(fc)

	box_instances := cb.text_instances
    for &text_box in cb.text_boxes {
        box_instances = draw_text_box(state, &text_box, box_instances)
    }

    sg.apply_pipeline(cb.text_pipeline)
    for &text_box in cb.text_boxes {
    	cb.text_bindings.vertex_buffer_offsets[0] = text_box.instance_start
    	sg.apply_bindings(cb.text_bindings)

    	text_box.uniforms.transform =
    	    state.canvas_pv *
    		linalg.matrix4_translate_f32({text_box.rect.x, text_box.rect.y, 0}) *
    		linalg.matrix4_scale_f32(text_box.scale)
    	sg.apply_uniforms(0, range_from_type(&text_box.uniforms))
    	sg.draw(0, 6, text_box.instance_count)
    }
}

draw_text_box :: proc(state: ^State, text_box: ^Text_Box, instance_buffer: []Font_Instance) -> []Font_Instance {
    if strings.builder_len(text_box.text) == 0 do return instance_buffer[:]
    cb := &state.chalkboard
    fc := &cb.font_context
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
	glyph_max := min(len(cb.text_instances), int(state.frame))
	scratch_index := 0
	curr_length, prev_length := 0, 0 // Number of instances drawn on each page
	for i := 0; i < glyph_max && fs.TextIterNext(fc, &iter, &quad); i += 1 {
	    if !unicode.is_white_space(iter.codepoint) {
			cb.text_instance_scratch[scratch_index][curr_length] = {
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
	text_box.instance_count = c.int(prev_length + curr_length)

	// Copy scratch buffers into main instance buffer
	// Must copy prior scratch buffer first, and last used second
	// TODO: bounds checking
	scratch_prev := cb.text_instance_scratch[1 - scratch_index]
	scratch_curr := cb.text_instance_scratch[scratch_index]
	copy_slice(instance_buffer, scratch_prev[:prev_length])
	copy_slice(instance_buffer[prev_length:], scratch_curr[:curr_length])

	fs.PopState(fc)

	// TODO: only update instances that were written to this frame
   	text_box.instance_start = sg.append_buffer(
  		cb.text_buffer,
  		range_from_slice(instance_buffer[:text_box.instance_count]),
   	)

	return instance_buffer[text_box.instance_count:]
}

font_resize_atlas :: proc(data: rawptr, w, h: int) {
    cb := (^Chalkboard_State)(data)
    log("Resizing font atlas")
    logf("Old size: %d, %d", cb.font_context.width, cb.font_context.height)
    logf("New size: %d, %d", w, h)
    sg.destroy_image(cb.font_atlas)
   	cb.font_atlas = sg.make_image({
		width        = c.int(w),
		height       = c.int(h),
		usage        = .DYNAMIC,
		pixel_format = .R8,
	})
	cb.text_bindings.images[0] = cb.font_atlas
	// TODO: ensure that fontstash will call font_update_atlas after a resize; if not call manually
}

// Must ignore the raw texture data passed as last param because the length has been discarded by a raw_data call, just use the context instead
font_update_atlas :: proc(data: rawptr, dirtyRect: [4]f32, _: rawptr) {
    cb := (^Chalkboard_State)(data)
    if cb.font_atlas.id == 0 do return // TODO: might cause text set during init to not be drawn until another atlas update happens
	sg.update_image(
		cb.font_atlas,
		{
		    // feature request: why can't I use subimage[0][0] on the lhs here?
			subimage = { // [cubemap face][mip level]sg.Range
				0 = {
					0 = range_from_slice(cb.font_context.textureData)
				},
			},
		},
	)
}

/* Action callbacks */

// NOTE: raw_text is in a cstring format, i.e. 0-terminated and potentially with junk data after the terminator
input_text :: proc(state: ^State, raw_text: []u8) {
    text := string(cstring(raw_data(raw_text)))
    strings.write_string(&state.chalkboard.text_boxes[state.chalkboard.focused_text].text, text)
    //assert(strings.write_bytes(&state.user_console.text, raw_text) == len(raw_text))
}

input_newline :: proc(state: ^State) {
    strings.write_rune(&state.chalkboard.text_boxes[state.chalkboard.focused_text].text, '\n')
}

input_backspace :: proc(state: ^State) {
    //state.user_console.text = state.user_console.text[:math.max(0, len(state.user_console.text) - 1)]
    strings.pop_rune(&state.chalkboard.text_boxes[state.chalkboard.focused_text].text)
}

input_delete :: proc(state: ^State) {

}
