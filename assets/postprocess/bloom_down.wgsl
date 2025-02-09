@group(1) @binding(0) var samp: sampler;
@group(1) @binding(1) var text: texture_2d<f32>;

struct Uniforms {
    level: f32,
    strength: f32,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

fn sample(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(text, samp, uv, uni.level).rgb;
}

fn kernel(uv: vec2<f32>) -> vec3<f32> {
    let d = vec2<f32>(1, 1) / vec2<f32>(textureDimensions(text, i32(uni.level)));
    let s = sample(uv + d) + sample(uv + vec2f(-d.x, d.y)) + sample(uv + vec2f(d.x , -d.y)) + sample(uv - d);
    return s * 0.25;
}

@fragment
fn main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    let texColor = kernel(uv);
    let color = vec4<f32>(texColor, 1);

    return color;
}
