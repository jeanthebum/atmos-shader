override water_reflections: bool = true;
override water_clarity: f32 = 0.8;
override water_cloud_reflections: bool = true;
override water_ripples: f32 = 0.6;

// API 0.2: all scene samples and outputs are scene-linear radiance. Only literal
// colour swatches pass through palette_linear; tone mapping happens after bloom.
// Shared helpers: palette_linear(sRGB), daylight_color() (sRGB), noise3,
// cloud_mass. Shared constants: SKY_HORIZON, SKY_ZENITH (sRGB).
// sunlight_strength is the material module's linear irradiance multiplier.

fn water_scene_color(uv: vec2<f32>) -> vec3<f32> {
    let dims=vec2<i32>(textureDimensions(opaque_color));
    let grid=uv*vec2<f32>(dims)-0.5;
    let p=vec2<i32>(floor(grid));
    let f=fract(grid);
    let lo=vec2<i32>(0);let hi=dims-1;
    let a=textureLoad(opaque_color,clamp(p,lo,hi),0).rgb;
    let b=textureLoad(opaque_color,clamp(p+vec2<i32>(1,0),lo,hi),0).rgb;
    let c=textureLoad(opaque_color,clamp(p+vec2<i32>(0,1),lo,hi),0).rgb;
    let d=textureLoad(opaque_color,clamp(p+vec2<i32>(1,1),lo,hi),0).rgb;
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}

// Requires the experimental engine's material binding 5: reflection_depth.
// Gather colour and reversed depth together. RGB contains only reflected terrain,
// premultiplied by its coverage; alpha is uncovered sky. Replacing sky after this
// gather preserves leaf holes and silhouettes without blending terrain away.
fn water_mirror_sample(uv: vec2<f32>) -> vec4<f32> {
    let dims=vec2<i32>(textureDimensions(reflection_depth));
    let grid=uv*vec2<f32>(dims)-0.5;
    let p=vec2<i32>(floor(grid));
    let f=fract(grid);
    var terrain=vec3<f32>(0.0);
    var sky_coverage=0.0;
    for(var y=0;y<2;y=y+1) {
        for(var x=0;x<2;x=x+1) {
            let q=clamp(p+vec2<i32>(x,y),vec2<i32>(0),dims-1);
            let w=select(1.0-f.x,f.x,x==1)*select(1.0-f.y,f.y,y==1);
            let is_sky=textureLoad(reflection_depth,q,0)<=0.0;
            let texel=textureLoad(reflection,q,0).rgb;
            terrain+=texel*w*select(1.0,0.0,is_sky);
            sky_coverage+=w*select(0.0,1.0,is_sky);
        }
    }
    return vec4<f32>(terrain,sky_coverage);
}

fn water_sky(ray: vec3<f32>) -> vec3<f32> {
    let day=smoothstep(-0.10,0.15,frame.sun_direction.y);
    let height=max(ray.y,0.0);
    let mu=clamp(dot(ray,frame.sun_direction),-1.0,1.0);
    let rayleigh=0.75*(1.0+mu*mu);
    let g=0.88;
    let mie=(1.0-g*g)/pow(max(1.0+g*g-2.0*g*mu,0.001),1.5);
    let sunset=(1.0-smoothstep(-0.02,0.20,frame.sun_direction.y))*day;
    var summer=palette_radiance(mix(SKY_HORIZON,SKY_ZENITH,1.0-exp(-height*16.0)));
    summer*=0.97+rayleigh*0.03;
    summer+=palette_linear(daylight_color())*min(mie*0.003,0.45);
    summer+=vec3<f32>(0.24,0.065,0.015)*sunset*pow(1.0-height,4.0)*pow(max(mu,0.0),4.0);
    let night=vec3<f32>(0.004,0.009,0.019)*(0.7+0.3*pow(1.0-height,4.0))*(1.0-day)*(1.0-frame.rain*0.75);
    return mix(frame.sky_color,summer,day*(1.0-frame.rain))+night;
}

fn water_cloud_phase(mu: f32, g: f32) -> f32 {
    return (1.0-g*g)/pow(max(1.0+g*g-2.0*g*mu,0.001),1.5);
}

fn water_gradient(p: vec3<f32>) -> vec2<f32> {
    let center=noise3(p);
    let dx=noise3(p+vec3<f32>(0.14,0.0,0.0));
    let dz=noise3(p+vec3<f32>(0.0,0.0,0.14));
    return vec2<f32>(dx-center,dz-center)/0.14;
}

fn reflected_clouds(origin: vec3<f32>, ray: vec3<f32>, sky: vec3<f32>) -> vec3<f32> {
    if (ray.y <= 0.025 || cloud_coverage<=0.0) { return sky; }
    let start=max((185.0-origin.y)/ray.y,0.0);
    let end=min((340.0-origin.y)/ray.y,3000.0);
    if (end<=start) { return sky; }
    let steps=clamp(i32(ceil((end-start)/5.0)),48,160);
    let stride=(end-start)/f32(steps);
    let day=smoothstep(-0.08,0.18,frame.sun_direction.y);
    let sun=frame.light_direction;
    let mu=clamp(dot(ray,sun),-1.0,1.0);
    let phase=0.55+0.45*min(water_cloud_phase(mu,0.72)*0.80+water_cloud_phase(mu,-0.25)*0.20,5.0);
    let sun_color=mix(vec3<f32>(0.012,0.020,0.040),palette_linear(daylight_color()),day);
    // Same density, extinction, phase and palette as the visible sky. The
    // lighting march is shorter and cached across four view samples for water.
    let air_color=mix(vec3<f32>(0.005,0.009,0.022),
        mix(palette_radiance(mix(SKY_HORIZON,SKY_ZENITH,1.0-exp(-max(ray.y,0.0)*16.0))),
            palette_linear(vec3<f32>(0.38,0.42,0.48)),storm_amount()),day);
    var transmission=1.0;var light=vec3<f32>(0.0);
    var energy=vec3<f32>(0.0);var lit=false;
    var distance=start+stride*0.5;
    for(var i=0;i<steps;i=i+1) {
        if(distance>=end) {break;}
        let p=origin+ray*distance;
        let density=cloud_mass(p,true);
        if(density<0.002) {distance+=stride*1.5;lit=false;continue;}
        if(!lit || (i%4==0 && transmission>0.02)) {
            let optical=(cloud_mass(p+sun*3.0,true)*6.0
                +cloud_mass(p+sun*14.0,false)*16.0
                +cloud_mass(p+sun*38.0,false)*32.0)*0.18;
            let multiple=exp(-optical*0.35)*0.32+exp(-optical*0.10)*0.10;
            let powder=1.0-exp(-density*3.0);
            let powder_view=mix(0.55+powder*0.80,1.0,smoothstep(0.0,0.7,mu));
            let height=clamp((p.y-185.0)/155.0,0.0,1.0);
            let sky_access=0.35+0.65*exp(-cloud_mass(p+vec3<f32>(0.0,14.0,0.0),false)*1.1);
            let ambient=sky_access*mix(vec3<f32>(0.20,0.25,0.35),vec3<f32>(0.30,0.40,0.60),height)*mix(0.035,1.0,day);
            let storm=storm_amount();
            energy=ambient*(1.0-storm*0.40)+sun_color*(exp(-optical)*phase*1.35+multiple)*powder_view*(1.0-frame.rain*0.6)*(1.0-storm*0.45);
            lit=true;
        }
        let color=mix(energy,air_color,(1.0-exp(-distance*0.00055))*0.65);
        let alpha=(1.0-exp(-density*stride*0.18))*(1.0-smoothstep(1200.0,3000.0,distance));
        light+=transmission*alpha*color;
        transmission*=1.0-alpha;
        if(transmission<0.0002) {break;}
        distance+=stride;
    }
    return light+sky*transmission;
}

// The same world-space cloud field used in the sky, integrated toward the sun.
// This is a short lighting march; reflected cloud silhouettes use their own
// longer view march. Sunlight above the layer needs no cloud attenuation.
fn water_sun_transmission(origin: vec3<f32>) -> f32 {
    if (cloud_coverage<=0.0 || frame.sun_direction.y<=0.02 || origin.y>=340.0) { return 1.0; }
    let start=max((185.0-origin.y)/frame.sun_direction.y,0.0);
    let end=(340.0-origin.y)/frame.sun_direction.y;
    let stride=(end-start)/10.0;
    var optical_depth=0.0;
    for(var i=0;i<10;i=i+1) {
        let p=origin+frame.sun_direction*(start+(f32(i)+0.5)*stride);
        optical_depth+=cloud_mass(p,false)*stride*0.18;
    }
    return exp(-optical_depth);
}

fn water_position(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let p=frame.projection_inverse*vec4<f32>(uv.x*2.0-1.0,1.0-uv.y*2.0,depth,1.0);
    return (frame.view_inverse*vec4<f32>(p.xyz/max(abs(p.w),0.00001),0.0)).xyz;
}

// A short screen-space search for the seabed reflected by the underside.
// Unseen geometry falls back to deep-water light; it cannot be reconstructed
// from the current picture. The interface never samples the vanilla blue tile.
fn water_internal_reflection(origin: vec3<f32>, ray: vec3<f32>) -> vec3<f32> {
    let day=smoothstep(-0.1,0.18,frame.sun_direction.y);
    let fallback=palette_linear(vec3<f32>(0.035,0.22,0.28))*mix(0.04,1.0,day)*max(frame.eye_light_smooth.y,0.15);
    let size=vec2<i32>(textureDimensions(opaque_depth));
    var distance=0.3;
    for(var i=0;i<24;i=i+1) {
        let p=origin+ray*distance;
        let clip=frame.projection*frame.view*vec4<f32>(p,1.0);
        if(clip.w<=0.0) {break;}
        let uv=vec2<f32>(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5);
        if(any(uv<=vec2<f32>(0.001)) || any(uv>=vec2<f32>(0.999))) {break;}
        let pixel=clamp(vec2<i32>(uv*vec2<f32>(size)),vec2<i32>(0),size-1);
        let depth=textureLoad(opaque_depth,pixel,0);
        if(depth>0.0 && clip.z/clip.w<=depth) {
            let hit=water_position(uv,depth);
            if(hit.y<origin.y+0.1 && length(hit-p)<max(0.6,distance*0.10)) {
                let transmission=exp(-vec3<f32>(0.14,0.045,0.027)*distance);
                return water_scene_color(uv)*transmission+fallback*(vec3<f32>(1.0)-transmission);
            }
        }
        distance=distance*1.22+0.25;
    }
    return fallback;
}

fn underwater_surface(input: MaterialInput, normal: vec3<f32>, view: vec3<f32>) -> Surface {
    let eta=1.333;
    let cosine=clamp(dot(normal,view),0.0,1.0);
    let sin_squared=eta*eta*(1.0-cosine*cosine);
    let reflected=water_internal_reflection(input.position,reflect(-view,normal));
    // Beyond the critical angle, the underside is a mirror of the water below.
    if(sin_squared>=1.0) { return Surface(vec4<f32>(reflected,1.0)); }
    let transmitted_cosine=sqrt(max(1.0-sin_squared,0.0));
    let rs=(eta*cosine-transmitted_cosine)/max(eta*cosine+transmitted_cosine,0.0001);
    let rp=(cosine-eta*transmitted_cosine)/max(cosine+eta*transmitted_cosine,0.0001);
    let fresnel=clamp((rs*rs+rp*rp)*0.5,0.0,1.0);
    let ray=refract(-view,normal,eta);
    let world=input.position+frame.camera_position;
    let mu=clamp(dot(ray,frame.sun_direction),-1.0,1.0);
    let disk=smoothstep(0.999986,0.999991,mu)*smoothstep(-0.1,0.15,frame.sun_direction.y)*(1.0-frame.rain);
    let sky=water_sky(ray)+palette_linear(SUN_IVORY)*60.0*disk;
    var transmitted=sky;
    // Approximate the refracted view with the current opaque scene. Confirm an
    // above-water hit so foreground seabed cannot leak into Snell's window.
    let projected=frame.projection*frame.view*vec4<f32>(input.position+ray*32.0,1.0);
    var terrain=false;
    if(projected.w>0.0) {
        let uv=vec2<f32>(projected.x/projected.w*0.5+0.5,0.5-projected.y/projected.w*0.5);
        if(all(uv>vec2<f32>(0.001)) && all(uv<vec2<f32>(0.999))) {
            let size=vec2<i32>(textureDimensions(opaque_depth));
            let depth=textureLoad(opaque_depth,clamp(vec2<i32>(uv*vec2<f32>(size)),vec2<i32>(0),size-1),0);
            if(depth>0.0 && water_position(uv,depth).y>=input.position.y-0.08) {
                transmitted=water_scene_color(uv);
                terrain=true;
            }
        }
    }
    if(!terrain && water_cloud_reflections) {transmitted=reflected_clouds(world,ray,sky);}
    // The post pass applies extinction along the interface-to-eye segment.
    return Surface(vec4<f32>(mix(transmitted,reflected,fresnel),1.0));
}

// Analytic slopes of six oblique waves, specified by wavelength and peak
// slope. Dispersion uses gravity-wave angular speed sqrt(g*k). The small domain
// modulation breaks the repeated bands without a moving square noise lattice.
fn water_waves(p: vec2<f32>, seconds: f32) -> vec3<f32> {
    let directions=array<vec2<f32>,6>(vec2<f32>(0.94,0.342),vec2<f32>(0.62,0.785),
        vec2<f32>(0.995,-0.100),vec2<f32>(0.809,0.588),
        vec2<f32>(0.276,0.961),vec2<f32>(0.970,-0.243));
    let lengths=array<f32,6>(5.7,3.1,1.42,0.63,0.28,0.12);
    let amplitudes=array<f32,6>(0.032,0.045,0.041,0.032,0.022,0.014);
    let pixel_x=dpdx(p);let pixel_y=dpdy(p);
    var slope=vec2<f32>(0.0);var variance=0.0;
    for(var i=0;i<6;i=i+1) {
        let direction=directions[i];
        let k=6.283185/lengths[i];
        let phase=dot(p,direction)*k-sqrt(9.81*k)*seconds+f32(i)*2.39996;
        let dx=dot(pixel_x,direction)*k;let dy=dot(pixel_y,direction)*k;
        let attenuation=exp(-(dx*dx+dy*dy)/24.0);
        let modulation=0.85+0.15*sin(dot(p,vec2<f32>(-direction.y,direction.x))*0.31+seconds*0.13+f32(i));
        let amplitude=amplitudes[i]*modulation;
        slope+=direction*cos(phase)*amplitude*attenuation;
        variance+=amplitude*amplitude*0.5*(1.0-attenuation*attenuation);
    }
    // A non-periodic capillary field breaks the solar path into small glints.
    // Rotated coordinates avoid aligning a noise lattice with the block grid.
    let q=vec2<f32>(dot(p,vec2<f32>(0.866,0.5)),dot(p,vec2<f32>(-0.5,0.866)));
    let gradient=water_gradient(vec3<f32>(q.x*3.2-seconds*0.31,4.1+seconds*0.09,q.y*3.2+seconds*0.17));
    let footprint_squared=max(dot(pixel_x,pixel_x),dot(pixel_y,pixel_y));
    let attenuation=exp(-footprint_squared*3.2*3.2*1.65);
    slope+=vec2<f32>(0.866*gradient.x-0.5*gradient.y,0.5*gradient.x+0.866*gradient.y)*0.055*attenuation;
    variance+=0.055*0.055*0.35*(1.0-attenuation*attenuation);
    return vec3<f32>(slope,variance);
}

fn water_mirror_depth(uv: vec2<f32>) -> f32 {
    let dims=vec2<i32>(textureDimensions(reflection_depth));
    return textureLoad(reflection_depth,clamp(vec2<i32>(uv*vec2<f32>(dims)),vec2<i32>(0),dims-1),0);
}

// Mirror-camera positions are not ordinary scene positions. Undo the vertical
// reflection and virtual-eye offset before measuring a water-to-terrain ray.
fn water_mirror_position(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let v=frame.projection_inverse*vec4<f32>(uv.x*2.0-1.0,1.0-uv.y*2.0,depth,1.0);
    let p=(frame.view_inverse*vec4<f32>(v.xyz/v.w,0.0)).xyz;
    return p*vec3<f32>(1.0,-1.0,1.0)+vec3<f32>(0.0,2.0*(frame.water_plane-frame.camera_position.y),0.0);
}

fn water_mirror_project(p: vec3<f32>) -> vec2<f32> {
    let offset=vec3<f32>(0.0,2.0*(frame.water_plane-frame.camera_position.y),0.0);
    let clip=frame.projection*frame.view*vec4<f32>((p-offset)*vec3<f32>(1.0,-1.0,1.0),1.0);
    if(clip.w<=0.001) {return vec2<f32>(-1.0);}
    return vec2<f32>(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5);
}

fn water_reflection_uv(origin: vec3<f32>, screen: vec2<f32>, ray: vec3<f32>) -> vec2<f32> {
    let flat=reflect(normalize(origin),vec3<f32>(0.0,1.0,0.0));
    let initial_depth=water_mirror_depth(screen);
    var distance=frame.render_distance*2.0;
    if(initial_depth>0.0) {
        distance=clamp(dot(water_mirror_position(screen,initial_depth)-origin,flat),0.05,2000.0);
    }
    var uv=water_mirror_project(origin+ray*distance);
    // Two depth-guided projections account for the reflected object's distance:
    // nearby reeds barely shift, distant trees stretch across moving ripples.
    for(var i=0;i<2;i=i+1) {
        if(any(uv<=vec2<f32>(0.001)) || any(uv>=vec2<f32>(0.999))) {break;}
        let depth=water_mirror_depth(uv);
        if(depth<=0.0) {break;}
        let hit=water_mirror_position(uv,depth);
        distance=clamp(dot(hit-origin,ray),0.05,2000.0);
        uv=water_mirror_project(origin+ray*distance);
    }
    return uv;
}

fn water_safe_mirror(uv: vec2<f32>) -> vec4<f32> {
    if(any(uv<=vec2<f32>(0.0)) || any(uv>=vec2<f32>(1.0))) {return vec4<f32>(0.0,0.0,0.0,1.0);}
    let sample=water_mirror_sample(uv);
    let edge=min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y));
    return mix(vec4<f32>(0.0,0.0,0.0,1.0),sample,smoothstep(0.0,0.015,edge));
}

fn water_rough_mirror(uv: vec2<f32>, alpha: f32, view: vec3<f32>) -> vec4<f32> {
    let pixel=1.0/vec2<f32>(textureDimensions(reflection_depth));
    // Unresolved slopes broaden the reflection cone; reflection is less sensitive
    // to cross-wind microfacets when the view grazes the surface.
    let radius=clamp(vec2<f32>(frame.projection[0][0],frame.projection[1][1])
        *alpha*vec2<f32>(mix(0.22,0.75,abs(view.y)),0.75),pixel*0.35,pixel*14.0);
    var result=water_safe_mirror(uv)*0.4;
    result+=water_safe_mirror(uv+vec2<f32>(radius.x,0.0))*0.15;
    result+=water_safe_mirror(uv-vec2<f32>(radius.x,0.0))*0.15;
    result+=water_safe_mirror(uv+vec2<f32>(0.0,radius.y))*0.15;
    result+=water_safe_mirror(uv-vec2<f32>(0.0,radius.y))*0.15;
    return result;
}

fn summer_water(input: MaterialInput) -> Surface {
    if (frame.eye_in >= 2u) { return Surface(input.albedo * input.tint * vec4<f32>(input.lightmap,1.0)); }
    let world = input.position + frame.camera_position;
    let t = frame.time;
    let distance=length(input.position);
    // Metre-scale gravity waves survive a distant lake view. Short capillary
    // waves are filtered by their phase footprint; their missing variance goes
    // into the specular lobe instead of turning the lake into a perfect mirror.
    let waves=water_waves(world.xz,t);
    let footprint=max(length(dpdx(world.xz)),length(dpdy(world.xz)));
    let landscape_waves=1.0+coast_weight()*0.28-swamp_weight()*0.18;
    let slope=waves.xy*water_ripples*landscape_waves+rainfall_slope(world.xz,footprint)*smoothstep(0.9,1.0,input.light.y);
    let lost_variance=waves.z*water_ripples*water_ripples*landscape_waves*landscape_waves;
    let orientation=select(1.0,-1.0,input.normal.y<0.0);
    let n=normalize(input.normal+vec3<f32>(slope.x,0.0,slope.y)*orientation);
    let alpha_squared=0.00010+lost_variance;
    let roughness=pow(alpha_squared,0.25);
    let view = -input.position / max(distance,0.001);
    if (frame.eye_in==1u) { return underwater_surface(input,n,view); }
    let fresnel = 0.02 + 0.98*pow(1.0-clamp(dot(n,view),0.0,1.0),5.0);
    let size = vec2<f32>(textureDimensions(opaque_depth));
    let pixel = clamp(vec2<i32>(input.screen*size),vec2<i32>(0),vec2<i32>(size)-1);
    let behind_depth = textureLoad(opaque_depth,pixel,0);
    // Inverse projection reconstructs the opaque surface behind the fluid.
    let clip = vec4<f32>(input.screen.x*2.0-1.0,1.0-input.screen.y*2.0,behind_depth,1.0);
    let view_h = frame.projection_inverse*clip;
    let behind = (frame.view_inverse*vec4<f32>(view_h.xyz/max(abs(view_h.w),0.00001),1.0)).xyz;
    let thickness = select(clamp(length(behind)-length(input.position),0.0,100.0),100.0,behind_depth<=0.0);
    // A clear freshwater spectrum: red is removed first, while a modest blue
    // loss preserves a natural green-blue lake body rather than royal blue.
    let murk=clamp(swamp_weight()*swamp_water,0.0,1.0);
    let absorption = biome_water_absorption(vec3<f32>(0.25,0.055,0.045)*(1.4-water_clarity)+vec3<f32>(0.018));
    let transmittance = exp(-absorption*thickness);
    let view_slope=(frame.view*vec4<f32>(n-input.normal,0.0)).xy*vec2<f32>(1.0,-1.0);
    let refract_uv=clamp(input.screen+view_slope*0.012*smoothstep(0.0,3.0,thickness),vec2<f32>(0.001),vec2<f32>(0.999));
    let refract_pixel = clamp(vec2<i32>(refract_uv*size),vec2<i32>(0),vec2<i32>(size)-1);
    let refract_depth = textureLoad(opaque_depth,refract_pixel,0);
    let surface_clip = frame.projection*frame.view*vec4<f32>(input.position,1.0);
    // Reject foreground shore pixels so refraction cannot drag land over the water edge.
    let safe_uv=select(refract_uv,input.screen,refract_depth>surface_clip.z/surface_clip.w);
    let refracted=water_scene_color(safe_uv);
    let day = smoothstep(-0.1,0.18,frame.sun_direction.y);
    let deep=palette_linear(biome_water_body(vec3<f32>(0.025,0.21,0.24)))
        *mix(0.04,1.0,day)*max(input.light.y,0.1);
    let body = refracted*transmittance + deep*(vec3<f32>(1.0)-transmittance);
    let reflected_ray=reflect(-view,n);
    let clear_sky=water_sky(reflected_ray);
    var mirror=clear_sky;
    var sky_weight=1.0;
    if (water_reflections && frame.has_reflection != 0u) {
        let reflection_uv=water_reflection_uv(input.position,input.screen,reflected_ray);
        // The mirror target has no mip chain. Filter both terrain and uncovered
        // sky coverage together, so a softened silhouette cannot acquire a halo.
        let reflected=water_rough_mirror(reflection_uv,sqrt(alpha_squared),view);
        sky_weight=reflected.a;
        mirror=reflected.rgb+clear_sky*sky_weight;
    }
    if (water_cloud_reflections && water_reflections && sky_weight>0.001) {
        let cloudy_sky=reflected_clouds(world,reflected_ray,clear_sky);
        mirror+=(cloudy_sky-clear_sky)*sky_weight;
    }
    let half_sum=frame.light_direction+view;
    let h=half_sum/max(length(half_sum),0.001);
    let ndv=max(dot(n,view),0.001);
    let ndl=max(dot(n,frame.light_direction),0.0);
    let ndh=max(dot(n,h),0.0);
    let vdh=max(dot(view,h),0.0);
    let a2=alpha_squared;
    let denominator=ndh*ndh*(a2-1.0)+1.0;
    let distribution=a2/(3.141593*denominator*denominator);
    let k=roughness*roughness*0.5;
    let geometry=(ndv/(ndv*(1.0-k)+k))*(ndl/max(ndl*(1.0-k)+k,0.001));
    let sun_fresnel=0.02+0.98*pow(1.0-vdh,5.0);
    // Shadow-gated GGX reflects the same linear sunlight irradiance as terrain.
    var sun_visibility=smoothstep(0.75,0.98,input.light.y);
    if(frame.has_shadow!=0u) {
        let sp=shadow_position(input.position+vec3<f32>(0.0,0.08,0.0));
        if(all(sp.xy>vec2<f32>(0.002)) && all(sp.xy<vec2<f32>(0.998)) && sp.z>0.0 && sp.z<1.0) {
            sun_visibility=textureSampleCompareLevel(shadow_map,shadow_sampler,sp.xy,sp.z);
        }
    }
    // Cloud cover must occlude the solar path as well as the visible sun.
    // Otherwise the lake shines white beneath an opaque cloud bank.
    var cloud_sun=1.0;
    if (day>0.01 && ndl>0.0 && distribution>0.03) {
        cloud_sun=water_sun_transmission(world);
    }
    let sparkle=distribution*geometry*sun_fresnel/max(4.0*ndv,0.004)
        *smoothstep(-0.025,0.035,frame.sun_direction.y)*sun_visibility*cloud_sun
        *(1.0-frame.rain)*sunlight_strength*0.23;
    let base=mix(body,mirror,fresnel);
    // Gold belongs to the sun path, not a yellow tint over the entire lake.
    let color=base+palette_linear(daylight_color())*sparkle;
    // A half-float safety ceiling, not a display clamp. Solar highlights retain
    // their radiance above 1.0 for the downstream bloom and tone-map stages.
    return Surface(vec4<f32>(clamp(color,vec3<f32>(0.0),vec3<f32>(32000.0)),1.0));
}
