struct Instance {
    @location(0) position: vec3<f32>,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

struct Uniforms {
    pv: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

@vertex
fn main(@builtin(vertex_index) vertex: u32, inst: Instance) -> VertexOutput {
    var output: VertexOutput;

    let left   = bool(vertex & 1);
    let bottom = bool((vertex >> 1) & 1);

    let uv    = vec2<f32>(select(1.0, 0.0, left), select(1.0, 0.0, bottom));
    let pos   = vec3<f32>(uv - 0.5, 0) + inst.position;

    output.position = uni.pv * vec4<f32>(pos, 1);
    output.uv       = uv;
    return output;
}
