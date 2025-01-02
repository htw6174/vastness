@group(1) @binding(0) var samp: sampler;
@group(1) @binding(1) var text: texture_2d<f32>;

struct Uniforms {
    level: f32,
    strength: f32,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

@fragment
fn main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    // TODO: multi-sample and blend
    let texColor = textureSampleLevel(text, samp, uv, uni.level);
    //let texColor = textureSample(text, samp, uv);
    let color = vec4<f32>(texColor.rgb, texColor.a);

    return color;
}
