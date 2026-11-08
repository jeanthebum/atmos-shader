override saturation: f32 = 1.05;
override contrast: f32 = 1.05;
override camera_filter: bool = true;
override filter_strength: f32 = 0.45;

fn tonemap(input: TonemapInput) -> vec3<f32> {
    let exposure=textureSampleLevel(previous,linear_sampler,input.uv,0.0).a;
    let x=max(input.color*select(brightness_gain,exposure,exposure>0.0),vec3<f32>(0.0));
    // A single display transform after lighting, water, atmosphere and bloom.
    let mapped=clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),vec3<f32>(0.0),vec3<f32>(1.0));
    var display=to_display(mapped);
    let l=dot(display,vec3<f32>(0.2126,0.7152,0.0722));
    display=mix(vec3<f32>(l),display,saturation);
    if(camera_filter && filter_strength>0.0) {
        // Restrained photographic split toning, without blur, grain, or a
        // vignette hiding the frame. Zero strength is the original transform.
        let shadows=1.0-smoothstep(0.08,0.52,l);
        let highlights=smoothstep(0.45,0.95,l);
        let balance=vec3<f32>(1.0)+shadows*vec3<f32>(-0.035,0.006,0.038)
            +highlights*vec3<f32>(0.028,0.007,-0.035);
        let film=display*balance+vec3<f32>(0.004,0.006,0.008)*shadows;
        // Lush foliage retains its hue with slightly less neon at high chroma.
        let green=smoothstep(1.2,1.8,display.g/max(max(display.r,display.b),0.03));
        display=mix(display,mix(film,vec3<f32>(l),green*0.045),filter_strength);
    }
    display=clamp((display-vec3<f32>(0.5))*contrast+vec3<f32>(0.5),vec3<f32>(0.0),vec3<f32>(1.0));
    // Horizon performs the final display encoding after this stage.
    return palette_linear(display);
}
