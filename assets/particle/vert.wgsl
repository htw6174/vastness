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

    let uv = vec2<f32>(select(1.0, 0.0, left), select(1.0, 0.0, bottom));
    // Because this skips the aspect ratio correction provided by the projection matrix, must manually apply the correction
    let corner = vec3<f32>(uv - 0.5, 0);

    // Transform instance position to ndc space
    let pos = uni.pv * vec4<f32>(inst.position, 1);
    // scale quad corner offset by transformed position .w
    output.position = pos + vec4<f32>(corner * pos.w, 0);
    output.uv       = uv;
    return output;
}
