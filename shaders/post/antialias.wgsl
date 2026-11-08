override edge_smoothing: f32 = 0.65;
fn aa_luma(c: vec3<f32>) -> f32 { return log2(1.0+dot(c,vec3<f32>(0.2126,0.7152,0.0722))); }
fn post(input: PostInput) -> vec4<f32> {
    let px = 1.0 / vec2<f32>(textureDimensions(previous));
    let c = input.color.rgb;
    let nw = textureSampleLevel(previous,linear_sampler,input.uv+px*vec2<f32>(-1.0,-1.0),0.0).rgb;
    let ne = textureSampleLevel(previous,linear_sampler,input.uv+px*vec2<f32>(1.0,-1.0),0.0).rgb;
    let sw = textureSampleLevel(previous,linear_sampler,input.uv+px*vec2<f32>(-1.0,1.0),0.0).rgb;
    let se = textureSampleLevel(previous,linear_sampler,input.uv+px*vec2<f32>(1.0,1.0),0.0).rgb;
    let lnw=aa_luma(nw);let lne=aa_luma(ne);let lsw=aa_luma(sw);let lse=aa_luma(se);let lc=aa_luma(c);
    let hi=max(lc,max(max(lnw,lne),max(lsw,lse)));let lo=min(lc,min(min(lnw,lne),min(lsw,lse)));
    if (hi-lo < max(0.035,hi*0.10) || edge_smoothing<=0.0) { return input.color; }
    let gradient=vec2<f32>(lne+lse-lnw-lsw,lsw+lse-lnw-lne);
    let tangent=vec2<f32>(-gradient.y,gradient.x)/max(length(gradient),0.0001);
    let a=textureSampleLevel(previous,linear_sampler,input.uv+tangent*px*0.5,0.0).rgb;
    let b=textureSampleLevel(previous,linear_sampler,input.uv-tangent*px*0.5,0.0).rgb;
    let d=textureSampleLevel(previous,linear_sampler,input.uv+tangent*px*1.5,0.0).rgb;
    let e=textureSampleLevel(previous,linear_sampler,input.uv-tangent*px*1.5,0.0).rgb;
    let narrow=(a+b)*0.5;let wide=(a+b+d+e)*0.25;
    let lw=aa_luma(wide);let filtered=select(wide,narrow,lw<lo||lw>hi);
    return vec4<f32>(mix(c,filtered,edge_smoothing),input.color.a);
}
