struct Instance {
    @location(0) pos_min: vec2<f32>,
    @location(1) pos_max: vec2<f32>,
    @location(2) uv_min:  vec2<f32>,
    @location(3) uv_max:  vec2<f32>,
    @location(4) depth:   f32,
    @location(5) color:   vec4<f32>,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>, // NOTE: if I switch back to packed u32 color, be sure to add @interpolate(flat)
};

struct Uniforms {
    transform: mat4x4<f32>,
    // x: normalized progress along line of last glyph
    // y: position of line break below last glyph
    // z: instance index of first glyph in top page
    // w: usable height of text box (greatest multiple of line_height < box height), used to determine when top page fade should start
    boundary: vec4<f32>,
    line_height: f32,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

// Return 0 when x<0, 1 when x>falloff, lerp in between
fn relu(x: f32, falloff: f32) -> f32 {
    //let x1 = x-1;
    //return max(min(1.0, max(x, -x1*x1+1)/falloff), step(x, 0.0));
    return clamp(x/falloff, 0.0, 1.0);
}

@vertex
fn main(@builtin(vertex_index) vertex: u32, @builtin(instance_index) index: u32, inst: Instance) -> VertexOutput {
    var output: VertexOutput;

    let left   = bool(vertex & 1);
    let bottom = bool((vertex >> 1) & 1);

    let pos    = vec2<f32>(select(inst.pos_max.x, inst.pos_min.x, left), select(inst.pos_max.y, inst.pos_min.y, bottom));
    let uv     = vec2<f32>(select(inst.uv_max.x,  inst.uv_min.x, left),  select(inst.uv_max.y, inst.uv_min.y, bottom));

    //let testColor = pack4x8unorm(vec4<f32>(0, 0, f32(inst.color), 1));

    // modify transparency by glyph position from overwrite boundary:
    // if depth is lower than boundary.z and position is before boundary.xy, glyph should be transparent
    // if lower but glyph is after boundary, gradually fade in
    let dist = pos.y - ((uni.line_height * uni.boundary.x) + uni.boundary.y);
    let falloff_dist = uni.line_height * 1.0;
    let fade_bottom = relu(dist, falloff_dist);
    // Fade top page when boundary approaches bottom of text box
    let fade_top = relu(dist + uni.boundary.w, falloff_dist);
    let a = select(fade_top, fade_bottom, f32(index) < uni.boundary.z);
    //let a = 1.0;

    output.position = uni.transform * vec4<f32>(pos, 0, 1);
    output.uv       = uv;
    output.color    = vec4<f32>(inst.color.rgb, a);
    return output;
}
