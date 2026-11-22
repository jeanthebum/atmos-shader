fn compute(input: ComputeInput) {
    // Centre-weighted log luminance, excluding extreme point-source radiance.
    var sum=0.0; var weights=0.0;
    for(var y=0;y<4;y=y+1) {
        for(var x=0;x<4;x=x+1) {
            let uv=(vec2<f32>(f32(x),f32(y))+0.5)/4.0;
            let c=textureSampleLevel(previous,linear_sampler,uv,0.0).rgb;
            let l=clamp(dot(c,vec3<f32>(0.2126,0.7152,0.0722)),0.001,10.0);
            let w=exp(-dot(uv-0.5,uv-0.5)*4.0);
            sum+=log(l)*w; weights+=w;
        }
    }
    let metered=clamp(0.24/exp(sum/weights),0.75,1.8);
    let day=smoothstep(-0.08,0.16,frame.sun_direction.y);
    let desired=brightness_gain*mix(night_exposure,1.0,day)*mix(1.0,metered,auto_exposure);
    let old=textureLoad(exposure_value_previous,vec2<i32>(0),0).r;
    let valid=old>0.01 && frame.delta_time>0.0 && frame.delta_time<0.5;
    let response=1.0-exp(-frame.delta_time*select(0.8,1.8,desired<old));
    textureStore(exposure_value,vec2<i32>(0),vec4<f32>(select(desired,mix(old,desired,response),valid)));
}

