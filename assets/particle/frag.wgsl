
@fragment
fn main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    let color = vec4<f32>(uv, 0, 1);

    return color;
}