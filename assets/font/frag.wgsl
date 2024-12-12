@group(1) @binding(0) var samp: sampler;
@group(1) @binding(1) var text: texture_2d<f32>;

@fragment
fn main(@location(0) uv: vec2<f32>, @location(1) @interpolate(flat) color: u32) -> @location(0) vec4<f32> {
    let texColor = textureSample(text, samp, uv);
    let albedo = vec4<f32>(1, 1, 1, texColor.r);
    let tint = unpack4x8unorm(color);
    return albedo * tint;
    //return vec4<f32>(uv.x, uv.y, 0, 1);
}