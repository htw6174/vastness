struct Instance {
    @location(0) position: vec3<f32>,
    @location(1) color: vec4<f32>,
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
    let dist_ratio = uni.p[2][3] / log(v_pos.z);
    let scale = dist_ratio;
    // TODO: make instance field
    let intensity = 10000.0;
    output.position = c_pos;
    output.tint     = vec4<f32>(inst.color.rgb * scale * intensity, inst.color.a);
    return output;
}
