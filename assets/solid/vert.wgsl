struct Vertex {
    @location(0) position: vec3<f32>,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec3<f32>,
};

struct Uniforms {
    pv: mat4x4<f32>,
    m: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

@vertex
fn main(vert: Vertex) -> VertexOutput {
    var output: VertexOutput;

    let uv = vec2<f32>(abs(vert.position.xy));
    let color = vert.position * 0.5 + 0.5;

    let pos = vec4<f32>(vert.position, 1);
    output.position = uni.pv * pos;
    output.uv       = uv;
    output.color    = color;
    return output;
}
