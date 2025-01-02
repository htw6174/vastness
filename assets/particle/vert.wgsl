struct Instance {
    @location(0) position: vec3<f32>,
    @location(1) scale: f32,
    @location(2) color: vec4<f32>,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) tint: vec4<f32>,
};

struct Uniforms {
    v: mat4x4<f32>,
    p: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

@vertex
fn main(@builtin(vertex_index) vertex: u32, inst: Instance) -> VertexOutput {
    var output: VertexOutput;

    let left   = bool(vertex & 1);
    let bottom = bool((vertex >> 1) & 1);

    let uv = vec2<f32>(select(1.0, 0.0, left), select(1.0, 0.0, bottom));

    // instance position to view space
    let v_pos = uni.v * vec4<f32>(inst.position, 1);
    // 1x1 * scale quad in view space
    let corner = vec3<f32>((uv - 0.5) * inst.scale, 0) + v_pos.xyz;

    let pos = uni.p * vec4<f32>(corner, 1);
    output.position = pos;
    output.uv       = uv;
    output.tint    = inst.color;
    return output;
}
