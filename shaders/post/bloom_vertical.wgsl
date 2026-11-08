fn post(input: PostInput) -> vec4<f32> {
    if(bloom_strength<=0.0) {return vec4<f32>(0.0);}
    let px = 1.0 / vec2<f32>(textureDimensions(bloom_x));
    var color = vec3<f32>(0.0); var total = 0.0;
    for (var i = -4; i <= 4; i = i + 1) {
        let weight = exp(-f32(i * i) / 8.0);
        color += textureSampleLevel(bloom_x, linear_sampler, input.uv + vec2<f32>(0.0, f32(i) * 2.0 * px.y), 0.0).rgb * weight;
        total += weight;
    }
    return vec4<f32>(color / total, 1.0);
}
