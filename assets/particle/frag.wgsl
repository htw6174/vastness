
@fragment
fn main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    let a = 1.0 - (distance(vec2<f32>(0.5, 0.5), uv) * 2.0);
    let color = vec4<f32>(uv, 0, a);

    return color;
}
