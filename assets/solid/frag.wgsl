
@fragment
fn main(@location(0) uv: vec2<f32>, @location(1) color: vec3<f32>) -> @location(0) vec4<f32> {
    let col = vec4<f32>(color, 1);

    return col;
}
