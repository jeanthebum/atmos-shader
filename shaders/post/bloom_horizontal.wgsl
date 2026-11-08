fn post(input: PostInput) -> vec4<f32> {
    if(bloom_strength<=0.0) {return vec4<f32>(0.0);}
    let px = 1.0 / vec2<f32>(textureDimensions(previous));
    var color = vec3<f32>(0.0); var total = 0.0;
    for (var i = -4; i <= 4; i = i + 1) {
        let weight = exp(-f32(i * i) / 8.0);
        for(var y=-1;y<=1;y=y+1) {
            let c=textureSampleLevel(previous,linear_sampler,input.uv+vec2<f32>(f32(i)*8.0*px.x,f32(y)*px.y),0.0).rgb;
            let l=dot(c,vec3<f32>(0.2126,0.7152,0.0722));
            let knee=clamp(l-1.5,0.0,1.0);
            let contribution=max(l-2.0,knee*knee/2.0)/max(l,0.00001);
            color+=c*contribution*weight;
            total+=weight;
        }
    }
    return vec4<f32>(color / total, 1.0);
}
