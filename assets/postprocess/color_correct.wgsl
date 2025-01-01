@group(1) @binding(0) var samp: sampler;
@group(1) @binding(1) var text: texture_2d<f32>;

struct Uniforms {
    exposure: f32,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

@fragment
fn main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    let texColor = textureSample(text, samp, uv);
    let color = vec4<f32>(texColor.rgb * uni.exposure, texColor.a);

    return color;
}
