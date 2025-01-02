
@fragment
fn main(@location(0) uv: vec2<f32>, @location(1) tint: vec4<f32>) -> @location(0) vec4<f32> {
    let a = max(0.0, 1.0 - (distance(vec2<f32>(0.5, 0.5), uv) * 2.0));
    if (a < 0.9) {
        discard;
    }
    let color = vec4<f32>(tint.rgb, tint.a * a);

    return color;
}
