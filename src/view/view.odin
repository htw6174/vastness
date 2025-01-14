package view

import "core:c"
import "core:strings"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:fmt"

import sg "../sokol/gfx"
import "../platform"
import "../sim"

ASSET_DIR :: "../../assets/"

MAX_RENDER_MIPS :: 7 // Actual mip levels created is limited by screen size
MAX_BLOOM_LEVELS :: MAX_RENDER_MIPS - 1

MAX_PARTICLE_INSTANCES :: 1024 * 8
MAX_POINTS :: 1024 * 16

State :: struct {
	frame:          u64,
	world:          ^sim.World,
	swapchain:      sg.Swapchain,
	surface_format: sg.Pixel_Format,
	width:          c.int,
	height:         c.int,

	canvas_pv:      Transform,
	camera_view:    Transform,
	camera_perspective: Transform,
	camera_pv:      Transform,
	camera:         Camera,

	pass_action:    sg.Pass_Action,

	// debug quad
	debug_bindings: sg.Bindings,
	debug_pipeline: sg.Pipeline,

	// font & text
	chalkboard: Chalkboard_State,

	// points
	point_bindings: sg.Bindings,
	point_pipeline: sg.Pipeline,
	point_instances: [dynamic]Point_Instance, // TODO: change name from instances? not used in an instanced draw, points correspond to verts
	point_buffer: sg.Buffer,

	// particles
	particle_bindings: sg.Bindings,
	particle_pipeline: sg.Pipeline,
	particle_instances: [dynamic]Particle_Instance,
	particle_buffer:   sg.Buffer,

	// solid shapes
	solid_bindings: sg.Bindings,
	solid_pipeline: sg.Pipeline,

	// postprocess
	// shared offscreen and postprocess render targets + pass attachments
	offscreen_format: sg.Pixel_Format,
	offscreen_targets: [2]sg.Image,
	offscreen_source_index: int, // the offscreen target that isn't currently being rendered to
	offscreen_depth: sg.Image,
	offscreen_attachments: [2][MAX_RENDER_MIPS]sg.Attachments, // [image][mipmap]
	offscreen_attachments_depth: sg.Attachments,

	postprocess_bindings: sg.Bindings,

	bloom_enabled: bool,
	bloom_iters: int,
	bloom_action:   sg.Pass_Action,
	bloom_down_pipeline: sg.Pipeline,
	bloom_up_pipeline: sg.Pipeline,
	color_correct_pipeline: sg.Pipeline,

	// visualization settings
	sim_scale: f64 // default should be on the order of 1e-11
}

Shapes :: struct {
    // Verts defined in shader
	quad_index_buffer: sg.Buffer,

	cube_vertex_buffer: sg.Buffer,
	cube_index_buffer: sg.Buffer,
}

Point_Instance :: struct {
    position: Vec3,
    color: Color,
}

Particle_Instance :: struct {
    position: Vec3,
    scale: f32,
    color: Color,
}

Particle_Uniforms :: struct {
    view: Transform,
    perspective: Transform,
}

Solid_Uniforms :: struct {
    pv: Transform,
    m: Transform,
}

Bloom_Uniforms :: struct {
    level: f32, // mip level of render texture to use as input
    strength: f32,
}

Color_Correct_Uniforms :: struct {
    exposure: f32,
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

// TODO: embed in view state
shapes: Shapes

init :: proc(state: ^State) {
    state.frame = 0
    platform.window_init(_late_init, state)

	state.camera = {
	    position = {0, 0, -100},
	    near_clip = 0.1,
		far_clip = 1000,
		fov = math.PI / 4.0,
	}
	state.camera.rotation = linalg.quaternion_angle_axis_f32(-math.PI / 6.0, {1, 0, 0}) * linalg.quaternion_look_at_f32(state.camera.position, 0, {0, 1, 0})

	state.sim_scale = 1e-10
	state.bloom_enabled = true
	state.bloom_iters = 4

	// input setup
	register_keybind({.RETURN, .PRESS, input_newline})
	register_keybind({.BACKSPACE, .PRESS, input_backspace})
	register_keybind({.E, .HOLD, move_forward})
	register_keybind({.D, .HOLD, move_back})
	register_keybind({.S, .HOLD, move_left})
	register_keybind({.F, .HOLD, move_right})
	register_keybind({.T, .HOLD, move_up})
	register_keybind({.G, .HOLD, move_down})
	register_keybind({.Q, .HOLD, pitch_up})
	register_keybind({.A, .HOLD, pitch_down})
	register_keybind({.W, .HOLD, yaw_left})
	register_keybind({.R, .HOLD, yaw_right})
	register_keybind({.C, .HOLD, roll_left})
	register_keybind({.V, .HOLD, roll_right})
	register_keybind({.Z, .HOLD, zoom_in})
	register_keybind({.X, .HOLD, zoom_out})
	register_keybind({.B, .PRESS, toggle_bloom})
	register_keybind({.SPACE, .PRESS, sim_toggle_play})
	register_keybind({.LEFTBRACKET, .PRESS, sim_decrease_speed})
	register_keybind({.RIGHTBRACKET, .PRESS, sim_increase_speed})
	register_keybind({.MINUS, .PRESS, sim_decrease_freq})
	register_keybind({.EQUALS, .PRESS, sim_increase_freq})
	register_keybind({.COMMA, .PRESS, bloom_decrease_iters})
	register_keybind({.PERIOD, .PRESS, bloom_increase_iters})

	// module setup
	chalkboard_init(&state.chalkboard)
}

_late_init :: proc(raw_state: rawptr, device: rawptr) {
    state: ^State = (^State)(raw_state)
    log("Graphics device initialized!")

	// Initialize sokol_gfx
	state.pass_action = {
    	colors = {
            0 = {
          		load_action = .CLEAR,
          		clear_value = {0, 0, 0, 0},
           	}
        }
	}
	uw, uh := platform.get_render_bounds()
	state.width = c.int(uw)
	state.height = c.int(uh)
	// TODO: ensure device supports format, use one of BGRA8 or RGBA8
	state.surface_format = .BGRA8
	// Will use HDR color, so must use a float format
	state.offscreen_format = .RGBA16F

	sg.setup(
		sg.Desc {
			environment = {
				defaults = {color_format = state.surface_format, depth_format = .DEPTH},
				wgpu = {device = device},
			},
			logger = {func = platform.slog_func},
		},
	)
	assert(sg.query_backend() == .WGPU)

	state.swapchain = sg.Swapchain {
		width = state.width,
		height = state.height,
		// Some default values from sokol environment, only need to assign if different
		//sample_count = 1,
		//color_format = .BGRA8,
		//depth_format = .DEPTH_STENCIL,
		wgpu = {render_view = nil, resolve_view = nil, depth_stencil_view = nil},
	}

	state_init_shapes()
	chalkboard_init_graphics(&state.chalkboard)

	state_init_offscreen(state)
	state_init_debug(state)
	state_init_points(state)
	state_init_particles(state)
	state_init_solids(state)
	state_init_postprocess(state)
}

step :: proc(state: ^State, dt: f32) {
    frame := platform.frame_begin()
    if !frame.ready {
        return
    }
    defer platform.frame_end()

    state.swapchain.wgpu.render_view = frame.render_view
    state.swapchain.wgpu.resolve_view = frame.resolve_view
    state.swapchain.wgpu.depth_stencil_view = frame.depth_stencil_view

    platform.poll_events(handle_event, state)
    handle_input_state(state)

	width, height := platform.get_render_bounds()
	state.width = c.int(width)
	state.height = c.int(height)
	if frame.surface_changed {
		offscreen_refresh(state)
	}

	canvas_view := linalg.MATRIX4F32_IDENTITY // TODO?
	// NDC in Wgpu are -1, -1 at bottom-left of screen, +1, +1 at top-right
	canvas_perspective := linalg.matrix_ortho3d_f32(0, f32(width), f32(height), 0, -1, 1)
	state.canvas_pv = canvas_perspective * canvas_view

	move_speed: f32 = 40.0
	rotate_speed: f32 = 1.0
	//state.camera.position.z = -2.0 + math.sin_f32(f32(state.frame) / 120.0)
	state.camera.position += state.camera.velocity * move_speed * dt
	//state.camera.rotation = linalg.quaternion_look_at_f32(state.camera.position, 0, {0, 1, 0})
	state.camera.velocity = 0
	// Make quaternion from each angle-axis rotation
	rotate_delta := state.camera.angular_velocity * rotate_speed * dt
	q_pitch := linalg.quaternion_angle_axis_f32(rotate_delta.x, {1, 0, 0})
	q_yaw := linalg.quaternion_angle_axis_f32(rotate_delta.y, {0, 1, 0})
	q_roll := linalg.quaternion_angle_axis_f32(rotate_delta.z, {0, 0, 1})
	// Make rotation matrix from combined quaternions (multiply them all together)
	state.camera.rotation = q_roll * q_yaw * q_pitch * state.camera.rotation
	state.camera.angular_velocity = 0

	state.camera_view =
	    linalg.matrix4_translate_f32(-state.camera.position) *
		linalg.matrix4_from_quaternion_f32(state.camera.rotation)

	//cam_view := linalg.matrix4_look_at_f32(state.camera.position, 0, {0, 1, 0})
	// TODO: document handedness, clip space z range and reverse z; add options for each config
	state.camera_perspective = linalg.matrix4_infinite_perspective_f32(state.camera.fov, f32(width) / f32(height), state.camera.near_clip, flip_z_axis = false)
	// NOTE: Any reason not to use an infinite far clip?
	//state.camera_perspective = linalg.matrix4_perspective_f32(state.camera.fov, f32(width) / f32(height), state.camera.near_clip, state.camera.far_clip, flip_z_axis = false)
	state.camera_pv = state.camera_perspective * state.camera_view

	// Offscreen pass, anything drawn here will have post-processing applied later
	sg.begin_pass(sg.Pass{
	    action = state.pass_action,
		attachments = state.offscreen_attachments_depth,
	})

	// Add asteroids to point buffer
	// TODO: use real body size as radius
	// - Scale radius by sim_scale: if under some threshold, render as a point; else render as a particle.
	radius_scale_bias := 1.0e3
	clear(&state.point_instances)
	clear(&state.particle_instances)
	for body, i in state.world.bodies {
	    tint := linalg.vector4_hsl_to_rgb_f32(body.hue, 1, 0.5)
		r_apparant := state.sim_scale * radius_scale_bias * body.radius
		if i <= state.world.massive_bodies { // particle
		    append(&state.particle_instances, Particle_Instance{position_from_body(body, state.sim_scale), f32(r_apparant), tint})
		} else { // point
		    //tint.rgb *= f32(r_apparant)
	        append(&state.point_instances, Point_Instance{position_from_body(body, state.sim_scale), tint})
		}
	}
	if len(state.point_instances) > 0 {
	    sg.update_buffer(state.point_buffer, range_from_slice(state.point_instances[:]))
	}
	if len(state.particle_instances) > 0 {
	    sg.update_buffer(state.particle_buffer, range_from_slice(state.particle_instances[:]))
	}

	draw_points(state)

	sg.end_pass()
	state.offscreen_source_index = 0

	if state.bloom_enabled {
	    postprocess_bloom(state)
	}

	// Default pass
	sg.begin_pass(sg.Pass{action = state.pass_action, swapchain = state.swapchain})

	// draw final output of post-processing stack
	draw_postprocess(state)
	draw_particles(state)

	// draw reference cube at world origin
	// TODO: any good way to combine 3D with postprocessing from offscreen pass with "plain"/debug 3D in final pass?
	// Solution might involve stencil buffer
	// sg.apply_pipeline(state.solid_pipeline)
	// sg.apply_bindings(state.solid_bindings)
	// cube_uniforms := Solid_Uniforms{pv = state.camera_pv, m = 1}
	// sg.apply_uniforms(0, range_from_type(&cube_uniforms))
	// sg.draw(0, 36, 1)

	strings.builder_reset(&state.chalkboard.text_boxes[1].text)
	write_clockstring_from_seconds(&state.chalkboard.text_boxes[1].text, state.world.time)
	strings.write_rune(&state.chalkboard.text_boxes[1].text, '\n')
	fmt.sbprintf(&state.chalkboard.text_boxes[1].text, "running %.0f steps/second; %d sim seconds/step", 1.0 / state.world.step_frequency_inv, state.world.time_step)

	// draw 2D UI over everything else
	draw_ui(state)

	// update matrix text box
	// state.text_boxes[2].rect.x = f32(width) - 40
	// if state.frame % 8 == 0 {
	// 	if strings.builder_len(state.text_boxes[2].text) > 1024 do strings.builder_reset(&state.text_boxes[2].text)
	//     rand_byte := u8(int('0') + rand.int_max(int('~') - int('0')))
	//     strings.write_byte(&state.text_boxes[2].text, rand_byte)
	// }

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

/* Non-graphics setup (can be done before device is aquired) */

/* Graphics Setup */

// TODO: store default meshes in view state
state_init_shapes :: proc() {
	quad_indicies := []u32{0, 1, 2, 1, 2, 3}
	shapes.quad_index_buffer = sg.make_buffer(sg.Buffer_Desc{
		type = .INDEXBUFFER,
		usage = .IMMUTABLE,
		data = range_from_slice(quad_indicies),
	})

	cube_verts := []f32{
	    -1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0,  1.0,
         1.0, -1.0,  1.0,
         1.0,  1.0,  1.0,
        -1.0,  1.0,  1.0,

        -1.0, -1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0,  1.0,
        -1.0, -1.0,  1.0,

        1.0, -1.0, -1.0,
        1.0,  1.0, -1.0,
        1.0,  1.0,  1.0,
        1.0, -1.0,  1.0,

        -1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0,  1.0,
         1.0, -1.0, -1.0,

        -1.0,  1.0, -1.0,
        -1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0, -1.0,
	}
	shapes.cube_vertex_buffer = sg.make_buffer(sg.Buffer_Desc{
	    type = .VERTEXBUFFER,
		usage = .IMMUTABLE,
		data = range_from_slice(cube_verts),
	})

	cube_indicies := []u32{
	    0, 1, 2,  0, 2, 3,
        6, 5, 4,  7, 6, 4,
        8, 9, 10,  8, 10, 11,
        14, 13, 12,  15, 14, 12,
        16, 17, 18,  16, 18, 19,
        22, 21, 20,  23, 22, 20
    }
	shapes.cube_index_buffer = sg.make_buffer(sg.Buffer_Desc{
	    type = .INDEXBUFFER,
		usage = .IMMUTABLE,
		data = range_from_slice(cube_indicies),
	})
}

offscreen_create :: proc(state: ^State) {
    image_desc := sg.Image_Desc{
        render_target = true,
		width = state.width,
		height = state.height,
		num_mipmaps = MAX_RENDER_MIPS,
		pixel_format = state.offscreen_format,
   	}

    state.offscreen_targets[0] = sg.make_image(image_desc)
	state.offscreen_targets[1] = sg.make_image(image_desc)
	image_desc.num_mipmaps = 0
	image_desc.pixel_format = .DEPTH
	state.offscreen_depth = sg.make_image(image_desc)

	for i in 0..<MAX_RENDER_MIPS {
       	state.offscreen_attachments[0][i] = sg.make_attachments({
       	    colors = {0 = {
     			image = state.offscreen_targets[0],
     			mip_level = i32(i),
      		}}
       	})
       	state.offscreen_attachments[1][i] = sg.make_attachments({
       	    colors = {0 = {
     			image = state.offscreen_targets[1],
     			mip_level = i32(i),
      		}}
       	})
   	}

    state.offscreen_attachments_depth = sg.make_attachments({
   	    colors = {0 = {
            image = state.offscreen_targets[0],
        }},
        depth_stencil = {image = state.offscreen_depth},
    })
}

offscreen_release :: proc(state: ^State) {
    sg.destroy_image(state.offscreen_targets[0])
    sg.destroy_image(state.offscreen_targets[1])
    sg.destroy_image(state.offscreen_depth)

    for i in 0..<MAX_RENDER_MIPS {
        sg.destroy_attachments(state.offscreen_attachments[0][i])
        sg.destroy_attachments(state.offscreen_attachments[1][i])
    }
    sg.destroy_attachments(state.offscreen_attachments_depth)
}

offscreen_refresh :: proc(state: ^State) {
    offscreen_release(state)
    offscreen_create(state)
}

// TODO: proc to dispose and re-init offscreen resources when surface changes
state_init_offscreen :: proc(state: ^State) {
    offscreen_create(state)
}

state_init_solids :: proc(state: ^State) {
    state.solid_bindings = {
        vertex_buffers = {0 = shapes.cube_vertex_buffer},
        index_buffer = shapes.cube_index_buffer,
    }

    solid_shader := sg.make_shader(sg.Shader_Desc{
        vertex_func = {source = #load(ASSET_DIR + "solid/vert.wgsl", cstring)},
        fragment_func = {source = #load(ASSET_DIR + "solid/frag.wgsl", cstring)},
        uniform_blocks = {
            0 = {
                stage = .VERTEX,
                size = size_of(Solid_Uniforms),
                wgsl_group0_binding_n = 0,
                layout = .NATIVE,
            }
        }
    })

    state.solid_pipeline = sg.make_pipeline(sg.Pipeline_Desc {
        shader = solid_shader,
        layout = {
            buffers = {0 = {step_func = .PER_VERTEX}},
            attrs = {0 = {format = .FLOAT3}},
        },
        colors = {}, // can leave as default, no transparency
        index_type = .UINT32,
        depth = {
            write_enabled = true,
            compare = .LESS_EQUAL,
        }
    })
}

state_init_points :: proc(state: ^State) {
    state.point_instances = make([dynamic]Point_Instance, 0, MAX_POINTS)

    point_instance_buffer := sg.make_buffer({
        type = .VERTEXBUFFER,
        usage = .DYNAMIC,
        size = size_of(Point_Instance) * MAX_POINTS,
    })
    state.point_buffer = point_instance_buffer
    state.point_bindings = {
        vertex_buffers = {0 = point_instance_buffer},
    }

    point_shader := sg.make_shader({
        vertex_func = {source = #load(ASSET_DIR + "point/vert.wgsl", cstring)},
        fragment_func = {source = #load(ASSET_DIR + "point/frag.wgsl", cstring)},
        uniform_blocks = {
            0 = {
                stage = .VERTEX,
                size = size_of(Particle_Uniforms), // TODO: do points need their own uniform struct?
                wgsl_group0_binding_n = 0,
                layout = .NATIVE,
            }
        }
    })

    state.point_pipeline = sg.make_pipeline({
        shader = point_shader,
        layout = {
            attrs = {
                0 = {format = .FLOAT3},
                1 = {format = .FLOAT4},
            }
        },
        colors = {
            0 = {
                pixel_format = state.offscreen_format,
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE,
    					src_factor_alpha = .ONE,
    					dst_factor_alpha = .ZERO,
                }
            }
        },
        primitive_type = .POINTS,
        depth = {
            write_enabled = false,
            compare = .LESS_EQUAL,
        },
    })
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
                1 = {format = .FLOAT},
                2 = {format = .FLOAT4},
            }
        },
        colors = {
            0 = {
                pixel_format = state.surface_format,
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE,
					src_factor_alpha = .ONE,
					dst_factor_alpha = .ZERO,
                }
            }
        },
        index_type = .UINT32,
        depth = {
            write_enabled = false,
            compare = .LESS_EQUAL,
        },
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
		images = {0 = state.chalkboard.font_atlas},
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

state_init_postprocess :: proc(state: ^State) {
   pp_sampler := sg.make_sampler(
		sg.Sampler_Desc {
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			mipmap_filter = .NEAREST,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
			wrap_w = .CLAMP_TO_EDGE,
			min_lod = 0,
			max_lod = 32,
			max_anisotropy = 1,
		},
	)
	state.postprocess_bindings = {
		index_buffer = shapes.quad_index_buffer,
		images = {0 = {}}, // Must bind image later based on post-process stack
		samplers = {0 = pp_sampler},
	}

	// Bloom setup
	state.bloom_action = {
	    colors = {
			0 = {
			    load_action = .LOAD,
			}
		}
	}
	bloom_down_shader := sg.make_shader(sg.Shader_Desc{
	    vertex_func = {source = #load(ASSET_DIR + "postprocess/vert.wgsl", cstring)},
		fragment_func = {source = #load(ASSET_DIR + "postprocess/bloom_down.wgsl", cstring)},
		uniform_blocks = {
			0 = {
				stage = .FRAGMENT,
				size = size_of(Bloom_Uniforms),
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
	})
	state.bloom_down_pipeline = sg.make_pipeline(sg.Pipeline_Desc{
	    shader = bloom_down_shader,
		colors = {0 = {pixel_format = state.offscreen_format}},
		depth = {
		    pixel_format = .NONE,
			write_enabled = false,
		},
		primitive_type = .TRIANGLES, // same as default
		index_type = .UINT32,
	})
	bloom_up_shader := sg.make_shader(sg.Shader_Desc{
	    vertex_func = {source = #load(ASSET_DIR + "postprocess/vert.wgsl", cstring)},
		fragment_func = {source = #load(ASSET_DIR + "postprocess/bloom_up.wgsl", cstring)},
		uniform_blocks = {
			0 = {
				stage = .FRAGMENT,
				size = size_of(Bloom_Uniforms),
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
		image_sampler_pairs = {
		    0 = {stage = .FRAGMENT, image_slot = 0, sampler_slot = 0},
		},
	})
	state.bloom_up_pipeline = sg.make_pipeline(sg.Pipeline_Desc{
	    shader = bloom_up_shader,
		colors = {0 = {pixel_format = state.offscreen_format}},
		depth = {
		    pixel_format = .NONE,
			write_enabled = false,
		},
		primitive_type = .TRIANGLES, // same as default
		index_type = .UINT32,
	})

	// color correction setup
	// For now, only used in final pass so no need to setup an action or render attachment
	color_correct_shader := sg.make_shader(
		sg.Shader_Desc {
			vertex_func = {source = #load(ASSET_DIR + "postprocess/vert.wgsl", cstring)},
			fragment_func = {source = #load(ASSET_DIR + "postprocess/color_correct.wgsl", cstring)},
			uniform_blocks = {
				0 = {
					stage = .FRAGMENT,
					size = size_of(Color_Correct_Uniforms),
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
	state.color_correct_pipeline = sg.make_pipeline(
		sg.Pipeline_Desc {
			shader = color_correct_shader,
			primitive_type = .TRIANGLES, // same as default
			index_type = .UINT32,
		},
	)
}

draw_ui :: proc(state: ^State) {
    draw_chalkboards(state)
}

draw_points :: proc(state: ^State) {
    sg.apply_pipeline(state.point_pipeline)
    sg.apply_bindings(state.point_bindings)
    uniforms := Particle_Uniforms{view = state.camera_view, perspective = state.camera_perspective}
    sg.apply_uniforms(0, range_from_type(&uniforms))
    sg.draw(0, len(state.point_instances), 1)
}

draw_particles :: proc(state: ^State) {
    sg.apply_pipeline(state.particle_pipeline)
    sg.apply_bindings(state.particle_bindings)
    uniforms := Particle_Uniforms{view = state.camera_view, perspective = state.camera_perspective}
    sg.apply_uniforms(0, range_from_type(&uniforms))
    sg.draw(0, 6, len(state.particle_instances))
}

postprocess_bloom :: proc(state: ^State) {
    bindings := state.postprocess_bindings
	uniforms := Bloom_Uniforms{strength = 1.0}

    source := state.offscreen_source_index
    dest := 1 - source

    // DOWNSCALE
    for i in 0..<state.bloom_iters {
        sg.begin_pass(sg.Pass{
    	    action = state.bloom_action,
    		attachments = state.offscreen_attachments[dest][i + 1],
    	})
        sg.apply_pipeline(state.bloom_down_pipeline)
        bindings.images[0] = state.offscreen_targets[source]
        sg.apply_bindings(bindings)
        uniforms.level = f32(i)
        sg.apply_uniforms(0, range_from_type(&uniforms))
        sg.draw(0, 6, 1)
        sg.end_pass()
        dest = source
        source = 1 - dest
    }

    // UPSCALE
    for i := state.bloom_iters; i > 0; i -= 1 {
        sg.begin_pass(sg.Pass{
    	    action = state.bloom_action,
    		attachments = state.offscreen_attachments[dest][i - 1],
    	})
        sg.apply_pipeline(state.bloom_up_pipeline)
        bindings.images[0] = state.offscreen_targets[source]
        sg.apply_bindings(bindings)
        uniforms.level = f32(i)
        sg.apply_uniforms(0, range_from_type(&uniforms))
        sg.draw(0, 6, 1)
        sg.end_pass()
        dest = source
        source = 1 - dest
    }

    state.offscreen_source_index = source
}

draw_postprocess :: proc(state: ^State) {
    sg.apply_pipeline(state.color_correct_pipeline)
    state.postprocess_bindings.images[0] = state.offscreen_targets[state.offscreen_source_index]
    sg.apply_bindings(state.postprocess_bindings)
    uniforms := Color_Correct_Uniforms{exposure = 1.0}//math.sin(f32(state.frame) / 60.0) * 0.5 + 0.5}
    sg.apply_uniforms(0, range_from_type(&uniforms))
    sg.draw(0, 6, 1)
}


/* Action callbacks */

move_forward :: proc(state: ^State) {
    state.camera.velocity.z = 1
}

move_back :: proc(state: ^State) {
    state.camera.velocity.z = -1
}

move_left :: proc(state: ^State) {
    state.camera.velocity.x = -1
}

move_right :: proc(state: ^State) {
    state.camera.velocity.x = 1
}

move_up :: proc(state: ^State) {
    state.camera.velocity.y = 1
}

move_down :: proc(state: ^State) {
    state.camera.velocity.y = -1
}

yaw_left :: proc(state: ^State) {
    state.camera.angular_velocity.y = -1
}

yaw_right :: proc(state: ^State) {
    state.camera.angular_velocity.y = 1
}

pitch_up :: proc(state: ^State) {
    state.camera.angular_velocity.x = -1
}

pitch_down :: proc(state: ^State) {
    state.camera.angular_velocity.x = 1
}

roll_left :: proc(state: ^State) {
    state.camera.angular_velocity.z = -1
}

roll_right :: proc(state: ^State) {
    state.camera.angular_velocity.z = 1
}

zoom_in :: proc(state: ^State) {
    log_scale := math.log10_f64(state.sim_scale)
    log_scale -= 0.01
    state.sim_scale = math.pow_f64(10.0, log_scale)
}

zoom_out :: proc(state: ^State) {
    log_scale := math.log10_f64(state.sim_scale)
    log_scale += 0.01
    state.sim_scale = math.pow_f64(10.0, log_scale)
}

toggle_bloom :: proc(state: ^State) {
    state.bloom_enabled = !state.bloom_enabled
}

bloom_increase_iters :: proc(state: ^State) {
    state.bloom_iters = math.min(state.bloom_iters + 1, MAX_BLOOM_LEVELS)
}

bloom_decrease_iters :: proc(state: ^State) {
    state.bloom_iters = math.max(state.bloom_iters - 1, 0)
}

sim_toggle_play :: proc(state: ^State) {
    state.world.is_running = !state.world.is_running
}

sim_increase_speed :: proc(state: ^State) {
    // No specific upper limit, but sim becomes very unstable at time steps >~1mil
    // TODO: is there a more general way to clamp within range of type?
    state.world.time_step = math.min(state.world.time_step * 2, 1 << 62)
}

sim_decrease_speed :: proc(state: ^State) {
    // Time resolution bottoms out at 1 second
    state.world.time_step = math.max(state.world.time_step / 2, 1)
}

sim_increase_freq :: proc(state: ^State) {
    // never more than 480 steps per second: prevent main thread locking at insane frequencies
    state.world.step_frequency_inv = math.max(state.world.step_frequency_inv / 2, 1.0/480.0)
}

sim_decrease_freq :: proc(state: ^State) {
    // never less than one step per second
    state.world.step_frequency_inv = math.min(state.world.step_frequency_inv * 2, 1)
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
position_from_body :: proc(body: sim.Body, vis_scale: f64) -> Vec3 {
    scaled := body.position * vis_scale
    return Vec3{f32(scaled.x), f32(scaled.y), f32(scaled.z)}
}
