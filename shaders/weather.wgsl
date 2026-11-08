// Liquid precipitation is analytic water. The Minecraft rain and particle
// sprites contribute no shape, colour or opacity. Snow retains its flakes.
fn drop_background(pixel: vec2<f32>) -> vec3<f32> {
    let size=vec2<i32>(textureDimensions(weather_scene_color));
    let pos=clamp(pixel-0.5,vec2<f32>(0.0),vec2<f32>(size-1));
    let lo=vec2<i32>(floor(pos));
    let hi=min(lo+1,size-1);
    let f=fract(pos);
    return mix(mix(textureLoad(weather_scene_color,lo,0).rgb,
        textureLoad(weather_scene_color,vec2<i32>(hi.x,lo.y),0).rgb,f.x),
        mix(textureLoad(weather_scene_color,vec2<i32>(lo.x,hi.y),0).rgb,
        textureLoad(weather_scene_color,hi,0).rgb,f.x),f.y);
}

fn weather(input: WeatherInput) -> vec4<f32> {
    let day=smoothstep(-0.10,0.15,frame.sun_direction.y);
    let sky_access=pow(input.light.y,1.25);
    let sky=palette_linear(SKY_AMBIENT)*mix(0.025,0.65,day)*sky_access;
    let lamp=palette_linear(vec3<f32>(1.0,0.65,0.35))*pow(input.light.x,2.2)*0.7;
    if(input.snow) {
        return vec4<f32>((sky*1.6+lamp)*input.color.rgb,input.color.a*0.85);
    }
    if(frame.eye_in!=0u) {return vec4<f32>(0.0);}
    let kind=weather_kind();
    let uv=weather_uv();
    let progress=clamp(weather_progress(),0.0,1.0);
    var p=uv*2.0-1.0;
    var visibility=1.0;
    if(kind==0u) {
        // Columns supply bounded, roof-clipped geometry and motion only.
        let grid=uv*vec2<f32>(6.0,3.0);
        let cell=floor(grid);
        let seed=env_hash(cell+vec2<f32>(17.3,29.7));
        let center=vec2<f32>(0.23+0.54*seed,0.22+0.56*env_hash(cell+37.1));
        p=(fract(grid)-center)*vec2<f32>(48.0,24.0);
        visibility=select(0.0,1.0,seed<mix(0.38,0.75,clamp(rain_detail*0.5,0.0,1.0)));
    }
    if(kind==2u || kind==3u) {p*=2.0;}
    let r2=dot(p,p);
    let edge=clamp(fwidth(r2),0.018,1.2);
    let radius_px=1.0/max(fwidth(p.x),0.08);
    let projected_radius=clamp(radius_px,0.5,9.0);
    let r=sqrt(r2);
    let ring_width=clamp(fwidth(r)*1.15,0.045,0.20);
    var coverage=(1.0-smoothstep(1.0-edge,1.0+edge,r2))*visibility;
    coverage*=clamp(radius_px*2.0,0.0,1.0);
    if(kind==4u) {
        let outer=1.0-smoothstep(ring_width,ring_width*2.0,abs(r-0.78));
        let inner=(1.0-smoothstep(ring_width,ring_width*1.8,abs(r-0.47)))*0.28;
        coverage=max(outer,inner)*pow(1.0-progress,1.7);
    }
    if(coverage<0.003) {return vec4<f32>(0.0);}

    let view=normalize(-input.position);
    let right=normalize(cross(vec3<f32>(0.0,1.0,0.0),view)+vec3<f32>(1e-6,0.0,0.0));
    let up=normalize(cross(view,right));
    let nz=sqrt(max(1.0-min(r2,0.999),0.001));
    var normal=normalize(right*p.x-up*p.y+view*nz);
    if(kind==4u) {normal=normalize(vec3<f32>(p.x*0.22,1.0,p.y*0.22));}
    let facing=clamp(abs(dot(normal,view)),0.0,1.0);
    let fresnel=0.0204+0.9796*pow(1.0-facing,5.0);
    let reflected=reflect(-view,normal);
    let upper=clamp(reflected.y*0.5+0.5,0.0,1.0);
    var reflection=mix(sky*0.25,sky*1.7,upper)+lamp;
    let half_vector=normalize(frame.light_direction+view);
    let highlight=pow(max(dot(normal,half_vector),0.0),96.0);
    let sun=palette_linear(daylight_color())*day*(1.0-frame.rain*0.82);
    reflection+=sun*highlight*7.0*sky_access;

    let screen=weather_screen();
    let dimensions=vec2<i32>(textureDimensions(weather_scene_depth));
    // Screen-space refraction, with foreground depth rejection.
    let bend=p*projected_radius*0.55*nz;
    var sample_pixel=clamp(screen.xy+bend,vec2<f32>(0.5),vec2<f32>(dimensions)-0.5);
    let sample_depth=textureLoad(weather_scene_depth,vec2<i32>(sample_pixel),0);
    if(sample_depth>screen.z+0.00001) {sample_pixel=screen.xy;}
    let behind=drop_background(sample_pixel);
    let transmission=behind*vec3<f32>(0.985,0.995,1.0);
    // Clear core, curved rim, and a small cap lit by the day/sunset palette.
    var color=mix(transmission,reflection,fresnel*0.80+0.03)
        +sun*highlight*0.75*sky_access;
    var opacity=coverage*weather_opacity()*select(0.62,0.88,kind>=2u);
    if(kind==0u) {
        let distance=length(input.position);
        opacity*=smoothstep(0.5,1.5,distance)*(1.0-smoothstep(18.0,38.0,distance));
    }
    if(kind==4u) {
        // Blend a reflected ripple over the live surface. Sampling opaque
        // ground here would cut a small hole through translucent lake water.
        color=reflection+sun*highlight*0.7;
        opacity*=0.30;
    }
    return vec4<f32>(max(color,vec3<f32>(0.0)),clamp(opacity,0.0,0.92));
}
