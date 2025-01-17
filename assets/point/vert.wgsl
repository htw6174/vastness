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

    // Calculate aparant size with perspective by finding distance after perspective transform from a point 1 unit away in view space
    //let v_pos = uni.v * vec4<f32>(inst.position, 1);
    let v_pos = vec4<f32>(inst.position, 1);
    let p1 = v_pos + vec4<f32>(1, 0, 0, 0);
    let c_pos = uni.p * v_pos;
    let c1 = uni.p * p1;
    // divide w: homogeneous to device coordinates
    //let scale = (c1.x / c1.w) - (c_pos.x / c_pos.w);
    let dist_ratio = uni.p[2][3] / v_pos.z;
    let scale = dist_ratio;
    output.position = c_pos;
    output.tint     = vec4<f32>(inst.color.rgb * scale * 10000.0, inst.color.a);
    return output;
}
