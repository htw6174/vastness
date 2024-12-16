struct Instance {
    @location(0) pos_min: vec2<f32>,
    @location(1) pos_max: vec2<f32>,
    @location(2) uv_min:  vec2<f32>,
    @location(3) uv_max:  vec2<f32>,
    @location(4) color:   vec4<f32>,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>, // NOTE: if I switch back to packed u32 color, be sure to add @interpolate(flat)
};

struct Uniforms {
    transform: mat4x4<f32>,
    boundary: f32,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

fn relu(x: f32, falloff: f32) -> f32 {
    let x1 = x-1;
    return max(min(1.0, max(x, -x1*x1+1)/falloff), step(x, 0.0));
}

@vertex
fn main(@builtin(vertex_index) vertex: u32, inst: Instance) -> VertexOutput {
    var output: VertexOutput;

    let left   = bool(vertex & 1);
    let bottom = bool((vertex >> 1) & 1);

    let pos    = vec2<f32>(select(inst.pos_max.x, inst.pos_min.x, left), select(inst.pos_max.y, inst.pos_min.y, bottom));
    let uv     = vec2<f32>(select(inst.uv_max.x,  inst.uv_min.x, left),  select(inst.uv_max.y, inst.uv_min.y, bottom));

    //let testColor = pack4x8unorm(vec4<f32>(0, 0, f32(inst.color), 1));

    // modify transparency by vertical position from overwrite boundary; no effect on anything above boundary, lerp from 0 to 1 over <distance> if below
    let dist = pos.y - uni.boundary;
    let fade = relu(dist, 100.0);

    output.position = uni.transform * vec4<f32>(pos, 0, 1);
    output.uv       = uv;
    output.color    = vec4<f32>(inst.color.rgb, fade);
    return output;
}
