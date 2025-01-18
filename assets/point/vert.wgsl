struct Instance {
    @location(0) position: vec3<f32>,
    @location(1) intensity: f32,
    @location(2) color: vec4<f32>,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) tint: vec4<f32>,
};

struct Uniforms {
    v: mat4x4<f32>,
    p: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

@vertex
fn main(@builtin(vertex_index) vertex: u32, inst: Instance) -> VertexOutput {
    var output: VertexOutput;

    let v_pos = vec4<f32>(inst.position, 1);
    let c_pos = uni.p * v_pos;
    let dist_ratio = 1.495979e+11 / v_pos.z; // distance basis of 1 AU
    let scale = dist_ratio;
    output.position = c_pos;
    output.tint     = vec4<f32>(inst.color.rgb * inst.intensity, inst.color.a);
    return output;
}
