
@fragment
fn main(@location(0) tint: vec4<f32>) -> @location(0) vec4<f32> {
    let color = vec4<f32>(tint.rgb, tint.a);

    return color;
}
