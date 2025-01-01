struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn main(@builtin(vertex_index) vertex: u32) -> VertexOutput {
    var output: VertexOutput;

    let left   = bool(vertex & 1);
    let bottom = bool((vertex >> 1) & 1);

    let pos    = vec2<f32>(select(1.0, -1.0, left), select(1.0, -1.0, bottom));
    let uv     = vec2<f32>(pos.x, -pos.y) * 0.5 + 0.5;

    output.position = vec4<f32>(pos, 0, 1);
    output.uv       = uv;
    return output;
}
