override contact_shading: f32 = 0.5;

fn ambient_occlusion(input: PostInput) -> f32 {
    if (input.depth <= 0.0 || contact_shading <= 0.0) { return 1.0; }
    let size = vec2<f32>(textureDimensions(scene_depth));
    let surf = surface_at(vec2<i32>(input.uv * size));
    if (!surf.present) { return 1.0; }
    let p = view_position(input.uv, input.depth);
    let radius_px = clamp(size.y * 0.65 / max(length(p), 0.1), 2.0, 60.0);
    var occlusion = 0.0;
    for (var i = 0; i < 8; i = i + 1) {
        let angle = f32(i) * 2.399963;
        let r = sqrt((f32(i) + 0.5) / 8.0);
        let uv = input.uv + vec2<f32>(cos(angle), sin(angle)) * radius_px * r / size;
        if (any(uv < vec2<f32>(0.0)) || any(uv > vec2<f32>(1.0))) { continue; }
        let depth = depth_at(uv);
        if (depth <= 0.0) { continue; }
        let delta = view_position(uv, depth) - p;
        let distance = length(delta);
        let horizon = max(dot(surf.normal, delta) / max(distance, 0.001) - 0.08, 0.0);
        occlusion += horizon * (1.0 - smoothstep(0.2, 1.5, distance));
    }
    return clamp(1.0 - occlusion * contact_shading * 0.35, 0.55, 1.0);
}

fn filtered_rays(input: PostInput) -> vec4<f32> {
    let size = vec2<f32>(textureDimensions(sun_rays));
    let grid = input.uv * size - 0.5;
    let base = floor(grid); let f = fract(grid);
    let center_depth = input.depth;
    let center_distance = length(view_position(input.uv, max(center_depth, 0.00001)));
    var total = 0.0; var result = vec4<f32>(0.0);
    for (var y = 0; y < 2; y = y + 1) {
        for (var x = 0; x < 2; x = x + 1) {
            let cell = clamp(vec2<i32>(base) + vec2<i32>(x,y), vec2<i32>(0), vec2<i32>(size) - 1);
            let uv = (vec2<f32>(cell) + 0.5) / size;
            let d = depth_at(uv);
            let distance = length(view_position(uv, max(d, 0.00001)));
            var weight = select(1.0-f.x, f.x, x == 1) * select(1.0-f.y, f.y, y == 1);
            weight *= exp(-abs(distance-center_distance) / max(center_distance * 0.05, 0.5));
            weight *= select(0.0, 1.0, (d == 0.0) == (center_depth == 0.0));
            result += textureLoad(sun_rays, cell, 0) * weight;
            total += weight;
        }
    }
    if (total < 0.00001) { return vec4<f32>(0.0,0.0,0.0,1.0); }
    return result / total;
}

fn frame_exposure() -> f32 {
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
    let old=textureSampleLevel(history,linear_sampler,vec2<f32>(0.5),0.0).a;
    let valid=old>0.01 && frame.delta_time>0.0 && frame.delta_time<0.5;
    let response=1.0-exp(-frame.delta_time*select(0.8,1.8,desired<old));
    return select(desired,mix(old,desired,response),valid);
}

fn post(input: PostInput) -> vec4<f32> {
    let daylight = smoothstep(-0.08, 0.16, frame.sun_direction.y);
    let summer = daylight * (1.0-frame.rain*0.75) * select(0.0, 1.0, frame.dimension == 0);
    var color = input.color.rgb * ambient_occlusion(input);
    let rays = filtered_rays(input);
    color = color * rays.a + rays.rgb;
    let bloom = textureSampleLevel(bloom_y, linear_sampler, input.uv, 0.0).rgb;
    color += bloom * bloom_strength;
    if(frame.dimension==0 && frame.eye_in==0u) {
        let p=view_position(input.uv,max(input.depth,0.000001));
        let air=biome_air(p,input.depth<=0.0);
        color=color*air.a+air.rgb*(1.0-air.a);
    }
    if (input.depth > 0.0 && frame.eye_in == 0u) {
        let p = view_position(input.uv, input.depth);
        let distance = length(p);
        let toward_sun = pow(max(dot(normalize(p), frame.sun_direction), 0.0), 5.0);
        let altitude=exp(-max(frame.camera_position.y+p.y-64.0,0.0)*0.006);
        let mist=(1.0-exp(-distance*0.0005*altitude*atmosphere_density))*0.16*summer;
        color=mix(color,mix(palette_radiance(SKY_HORIZON),palette_linear(daylight_color())*1.6,toward_sun*0.65),mist);
    }
    if (frame.eye_in == 1u) {
        // Wavelength-dependent extinction preserves nearby underwater detail.
        let p=view_position(input.uv,max(input.depth,0.00001));
        let travel=select(min(length(p),80.0),80.0,input.depth<=0.0);
        let murk=clamp(swamp_weight()*swamp_water,0.0,1.0);
        let transmission=exp(-biome_water_absorption(vec3<f32>(0.14,0.045,0.027))*travel);
        let water_light=mix(0.05,1.0,daylight)*max(frame.eye_light_smooth.y,0.12);
        let water_fog=palette_linear(biome_water_body(vec3<f32>(0.035,0.28,0.39)))*water_light;
        color=color*transmission+water_fog*(vec3<f32>(1.0)-transmission);
    } else if (frame.eye_in>=2u || frame.dimension!=0) {
        let travel=length(view_position(input.uv,max(input.depth,0.00001)));
        let fog=smoothstep(frame.fog_start,max(frame.fog_end,frame.fog_start+0.01),travel);
        color=mix(color,frame.fog_color,fog);
    }
    // This second-to-last pass receives its previous output in history.
    // Exposure travels in alpha through spatial AA; the display ignores coverage here.
    return vec4<f32>(max(color,vec3<f32>(0.0)),frame_exposure());
}
