override performance_profile: u32 = 3u;
override mapped_shadows: bool = true;
override bloom_strength: f32 = 0.3;
// Atmos Shader's original biome/weather model. The renderer supplies spatially
// blended biome families, not registry IDs or hard boundaries at chunk edges.
override biome_atmosphere: bool = true;
override biome_character: f32 = 1.25;
override jungle_moisture: f32 = 1.0;
// Consumed by the native local condensation emitter as well as this manifest.
override canopy_drips: f32 = 1.0;
override biome_light_tint: bool = true;
override biome_mist: f32 = 1.0;
override swamp_water: f32 = 1.0;
override snow_brightness: f32 = 1.0;
override weather_response: f32 = 1.0;
override rain_detail: f32 = 1.0;
override puddle_strength: f32 = 0.7;

fn environment_active() -> f32 {
    return select(0.0,1.0,biome_atmosphere && frame.dimension==0);
}
fn jungle_weight() -> f32 {return frame.biome_jungle*environment_active();}
fn swamp_weight() -> f32 {return frame.biome_swamp*environment_active();}
fn taiga_weight() -> f32 {return frame.biome_taiga*environment_active();}
fn forest_weight() -> f32 {return frame.biome_other.x*environment_active();}
fn arid_weight() -> f32 {return frame.biome_other.y*environment_active();}
fn frost_weight() -> f32 {return frame.biome_other.z*environment_active();}
fn cherry_weight() -> f32 {return frame.biome_other.w*environment_active();}
fn plains_weight() -> f32 {return frame.biome_landscape.x*environment_active();}
fn temperate_weight() -> f32 {return frame.biome_landscape.y*environment_active();}
fn coast_weight() -> f32 {return frame.biome_landscape.z*environment_active();}
fn savanna_weight() -> f32 {return frame.biome_landscape.w*environment_active();}
fn humid_wetness() -> f32 {return clamp((jungle_weight()*0.78+swamp_weight()*0.3)*jungle_moisture,0.0,1.0);}
fn storm_amount() -> f32 {return clamp((frame.rain*0.72+frame.thunder*0.48)*weather_response,0.0,1.0);}
fn local_rain() -> f32 {
    return frame.rain*select(0.0,1.0,frame.precipitation==1u && frame.dimension==0);
}
fn env_hash(p: vec2<f32>) -> f32 {
    var q=fract(vec3<f32>(p.x,p.y,p.x)*0.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
fn env_noise(p: vec2<f32>) -> f32 {
    let cell=floor(p);let f=fract(p);let u=f*f*(3.0-2.0*f);
    return mix(mix(env_hash(cell),env_hash(cell+vec2<f32>(1.0,0.0)),u.x),
        mix(env_hash(cell+vec2<f32>(0.0,1.0)),env_hash(cell+1.0),u.x),u.y);
}
fn biome_sun_tint() -> vec3<f32> {
    if(!biome_light_tint) {return vec3<f32>(1.0);}
    return vec3<f32>(1.0)+biome_character*(
        jungle_weight()*vec3<f32>(0.045,0.015,-0.065)
        +swamp_weight()*vec3<f32>(-0.085,0.025,-0.095)
        +arid_weight()*vec3<f32>(0.045,0.005,-0.055)
        +savanna_weight()*vec3<f32>(0.055,0.012,-0.065)
        +cherry_weight()*vec3<f32>(0.075,-0.025,0.035));
}
fn biome_ambient_tint() -> vec3<f32> {
    if(!biome_light_tint) {return vec3<f32>(1.0);}
    return vec3<f32>(1.0)+biome_character*(
        jungle_weight()*vec3<f32>(-0.10,0.13,-0.08)
        +swamp_weight()*vec3<f32>(-0.17,0.10,-0.23)
        +taiga_weight()*vec3<f32>(-0.12,0.025,0.11)
        +forest_weight()*vec3<f32>(-0.09,0.10,-0.035)
        +temperate_weight()*vec3<f32>(-0.035,0.05,-0.025)
        +frost_weight()*vec3<f32>(0.04,0.07,0.16)
        +coast_weight()*vec3<f32>(-0.035,0.045,0.10)
        +cherry_weight()*vec3<f32>(0.32,-0.045,0.095));
}
fn biome_light_level() -> f32 {
    let day=smoothstep(-0.08,0.16,frame.sun_direction.y);
    return 1.0+biome_character*day*(
        -swamp_weight()*0.22-forest_weight()*0.18-taiga_weight()*0.07
        -jungle_weight()*0.035+frost_weight()*0.26*snow_brightness
        +plains_weight()*0.035+coast_weight()*0.03);
}
fn biome_foliage_palette(lit: f32) -> vec3<f32> {
    var c=mix(LEAF_SHADE,LEAF_SUN,lit);
    if(!biome_light_tint) {return c;}
    c=mix(c,mix(vec3<f32>(0.055,0.29,0.17),vec3<f32>(0.39,0.70,0.12),lit),clamp(jungle_weight()*biome_character,0.0,1.0));
    c=mix(c,mix(vec3<f32>(0.10,0.26,0.25),vec3<f32>(0.30,0.48,0.29),lit),clamp(taiga_weight()*biome_character,0.0,1.0));
    c=mix(c,mix(vec3<f32>(0.07,0.25,0.12),vec3<f32>(0.42,0.61,0.21),lit),clamp(forest_weight()*biome_character,0.0,1.0));
    c=mix(c,mix(vec3<f32>(0.16,0.22,0.08),vec3<f32>(0.42,0.46,0.19),lit),clamp(swamp_weight()*biome_character,0.0,1.0));
    c=mix(c,mix(vec3<f32>(0.31,0.31,0.12),vec3<f32>(0.69,0.63,0.28),lit),clamp(savanna_weight()*biome_character,0.0,1.0));
    return c;
}
fn biome_water_absorption(clear: vec3<f32>) -> vec3<f32> {
    let tropical=clamp(jungle_weight()*jungle_moisture*0.65,0.0,1.0);
    let fresh=mix(clear,vec3<f32>(0.28,0.085,0.14),tropical);
    return mix(fresh,vec3<f32>(0.85,0.55,1.0),clamp(swamp_weight()*swamp_water,0.0,1.0));
}
fn biome_water_body(clear: vec3<f32>) -> vec3<f32> {
    var c=mix(clear,vec3<f32>(0.045,0.24,0.15),clamp(jungle_weight()*jungle_moisture,0.0,1.0));
    c=mix(c,vec3<f32>(0.018,0.19,0.30),coast_weight());
    return mix(c,vec3<f32>(0.21,0.25,0.105),clamp(swamp_weight()*swamp_water,0.0,1.0));
}

// Expanding rings are world anchored and die smoothly before the next impact.
// Adjacent cells are included so rings do not stop at an invisible tile border.
fn rainfall_slope(p: vec2<f32>, footprint: f32) -> vec2<f32> {
    let strength=local_rain()*rain_detail;
    if(strength<=0.001) {return vec2<f32>(0.0);}
    let grid=p/1.8;let cell=floor(grid);var slope=vec2<f32>(0.0);
    for(var y=-1;y<=1;y=y+1) {
        for(var x=-1;x<=1;x=x+1) {
            let tile=cell+vec2<f32>(f32(x),f32(y));
            let seed=env_hash(tile);
            let center=tile+vec2<f32>(seed,env_hash(tile+71.3));
            let delta=(grid-center)*1.8;let d=length(delta);
            let age=fract(frame.time*0.83+seed*13.7);
            let radius=age*0.82;
            let ring=d-radius;
            let envelope=exp(-ring*ring*160.0)*sin(age*3.141593)*(1.0-age);
            slope+=delta/max(d,0.01)*cos(ring*34.0)*envelope;
        }
    }
    return slope*strength*0.065*exp(-footprint*footprint*180.0);
}

// Eight samples of a moving, height-layered medium. Broad air establishes
// distance; small coherent vapor banks move through the foreground without
// fogging the first few metres or turning the zenith into a green ceiling.
fn biome_air(position: vec3<f32>, sky: bool) -> vec4<f32> {
    let humid=jungle_weight()*jungle_moisture;let swamp=swamp_weight();
    let woodland=taiga_weight()*0.8+forest_weight()*1.25+temperate_weight()*0.28;
    let dry=arid_weight()*0.7+savanna_weight();let marine=coast_weight();
    let weather=storm_amount();
    let morning=1.0-smoothstep(0.12,0.6,frame.sun_direction.y);
    let density=((humid*0.0060+swamp*0.0072+woodland*0.0042)*(1.0+morning*0.35)
        +dry*0.0010+marine*0.0008+cherry_weight()*0.0010)*biome_mist*biome_character
        +weather*0.0022;
    if(density<=0.0 || frame.dimension!=0 || frame.eye_in!=0u) {return vec4<f32>(0.0,0.0,0.0,1.0);}
    let distance=min(length(position),frame.render_distance);
    let ray=position/max(length(position),0.001);
    let open_air=smoothstep(0.03,0.38,frame.eye_light_smooth.y);
    var optical=0.0;
    for(var i=0;i<8;i=i+1) {
        let t=distance*(f32(i)+0.5)/8.0;
        let p=frame.camera_position+ray*t;
        let drift=vec2<f32>(frame.time*0.22,frame.time*-0.13);
        let broad=env_noise(p.xz*0.022+drift*0.022+p.y*0.006);
        let fine=env_noise(p.xz*0.085-drift*0.04+p.y*0.027);
        let bank=smoothstep(0.34,0.74,broad*0.72+fine*0.28);
        let layer=pow(0.5+0.5*sin(p.y*0.36+bank*2.7+frame.time*0.07),4.0);
        let wisps=0.60+bank*0.85+layer*bank*(humid*1.5+swamp*1.1+woodland*0.7);
        let vertical=exp(-max(p.y-max(frame.camera_position.y+2.0,68.0),0.0)*0.055);
        let near_clear=smoothstep(2.0,12.0,t);
        optical+=density*distance/8.0*wisps*vertical*open_air*near_clear;
    }
    optical*=select(1.0,1.0-smoothstep(0.03,0.24,ray.y),sky);
    let day=smoothstep(-0.08,0.16,frame.sun_direction.y);
    var tint=vec3<f32>(0.43,0.52,0.55);
    tint=mix(tint,vec3<f32>(0.46,0.57,0.40),clamp(humid*0.9,0.0,1.0));
    tint=mix(tint,vec3<f32>(0.25,0.33,0.20),swamp);
    tint=mix(tint,vec3<f32>(0.29,0.40,0.44),taiga_weight());
    tint=mix(tint,vec3<f32>(0.24,0.34,0.27),forest_weight());
    tint=mix(tint,vec3<f32>(0.66,0.57,0.40),clamp(dry,0.0,1.0));
    tint=mix(tint,vec3<f32>(0.55,0.69,0.77),marine);
    tint=mix(tint,vec3<f32>(0.65,0.53,0.59),cherry_weight()*0.7);
    tint=mix(tint,vec3<f32>(0.34,0.38,0.43),weather*0.7);
    let forward=pow(max(dot(ray,frame.sun_direction),0.0),6.0);
    let light=palette_linear(tint)*mix(0.055,1.15,day)
        +palette_linear(daylight_color())*forward*day*(1.0-weather)*0.19;
    return vec4<f32>(light,exp(-min(optical,2.7)));
}
