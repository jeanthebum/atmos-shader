fn sky(input: SkyInput) -> vec4<f32> {
    if(frame.dimension!=0) {return input.color;}
    let ray=normalize(input.direction);
    let day=smoothstep(-0.10,0.15,frame.sun_direction.y);
    let height=max(ray.y,0.0);
    let mu=clamp(dot(ray,frame.sun_direction),-1.0,1.0);
    let horizon=pow(1.0-height,4.0);
    let rayleigh=0.75*(1.0+mu*mu);
    let g=0.88;
    let mie=(1.0-g*g)/pow(max(1.0+g*g-2.0*g*mu,0.001),1.5);
    let sunset=(1.0-smoothstep(-0.02,0.20,frame.sun_direction.y))*day;
    // Confine pale aerial scattering to the low horizon, keeping the open sky rich.
    var summer=palette_radiance(mix(SKY_HORIZON,SKY_ZENITH,1.0-exp(-height*16.0)));
    summer*=0.97+rayleigh*0.03;
    summer+=palette_linear(daylight_color())*min(mie*0.003,0.45);
    summer+=vec3<f32>(0.24,0.065,0.015)*sunset*horizon*pow(max(mu,0.0),4.0);
    var color=mix(input.color.rgb,summer,day*(1.0-frame.rain));
    color+=vec3<f32>(0.004,0.009,0.019)*(0.7+0.3*horizon)*(1.0-day)*(1.0-frame.rain*0.75);
    // Approximately the real Sun's angular radius, with a soft pixel-scale edge.
    let disk=smoothstep(0.999986,0.999991,mu)*day*(1.0-frame.rain);
    color+=palette_linear(SUN_IVORY)*60.0*disk;
    // Scene radiance stays unclipped until tonemap.wgsl.
    return vec4<f32>(color,input.color.a);
}
