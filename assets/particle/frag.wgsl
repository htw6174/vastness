
@fragment
fn main(@location(0) uv: vec2<f32>, @location(1) tint: vec4<f32>) -> @location(0) vec4<f32> {
    let r = distance(vec2<f32>(0.5, 0.5), uv);
    if (r > 0.5) {
        discard;
    }
    // small fade to transparent border
    // TODO: could improve by making this border a constant pixel size
    let a = 1.0 - smoothstep(0.45, 0.5, r);
    let color = vec4<f32>(tint.rgb, tint.a * a);

    return color;
}
