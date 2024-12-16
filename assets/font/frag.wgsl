@group(1) @binding(0) var samp: sampler;
@group(1) @binding(1) var text: texture_2d<f32>;

@fragment
fn main(@location(0) uv: vec2<f32>, @location(1) color: vec4<f32>) -> @location(0) vec4<f32> {
    let texColor = textureSample(text, samp, uv);
    let albedo = vec4<f32>(1, 1, 1, texColor.r);
    let tint = color; //vec4<f32>(unpack4x8unorm(color).rgb, 1);

    // DEBUG
    //let background = vec4<f32>(uv.x, uv.y, 0, 1);
    //return mix(background, albedo, texColor.r);

    return albedo * tint;
}
