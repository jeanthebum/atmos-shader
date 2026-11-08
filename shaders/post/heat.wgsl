override heat_shimmer: f32 = 0.65;
fn post(input: PostInput) -> vec4<f32> {
    let heat=(arid_weight()+savanna_weight()*0.65)*heat_shimmer*biome_character*(1.0-frame.rain)
        *smoothstep(0.12,0.4,frame.sun_direction.y);
    if(heat<=0.001 || frame.eye_in!=0u || input.depth<=0.0) {return input.color;}
    let p=view_position(input.uv,input.depth);
    let distance=length(p);let ray=p/max(distance,0.001);
    let low_angle=1.0-smoothstep(0.05,0.3,abs(ray.y));
    let far=smoothstep(16.0,100.0,distance);
    let world=frame.camera_position+p;
    let n=env_noise(world.xz*0.12+vec2<f32>(frame.time*0.6,frame.time*-0.35));
    let wave=sin(input.uv.y*frame.resolution.y*0.09+frame.time*3.1+n*5.0);
    let offset=vec2<f32>(sin(n*6.283+frame.time*0.8)*0.45,wave)
        *vec2<f32>(1.0)/frame.resolution*2.3*heat*low_angle*far;
    let uv=clamp(input.uv+offset,vec2<f32>(0.001),vec2<f32>(0.999));
    let other_depth=depth_at(uv);
    if(other_depth<=0.0) {return input.color;}
    let other=length(view_position(uv,other_depth));
    // A foreground plant or cliff must never smear over the distant scene.
    if(abs(other-distance)>max(2.0,distance*0.08)) {return input.color;}
    return textureSampleLevel(previous,linear_sampler,uv,0.0);
}
