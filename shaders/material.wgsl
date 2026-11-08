override sunlight_strength: f32 = 3.4;
override ambient_strength: f32 = 0.45;
override shadow_softness: f32 = 1.5;
override foliage_transmission: f32 = 0.55;
override cloud_shadows: f32 = 0.45;
override surface_sheen: f32 = 0.35;

// Filter in shadow texels. Fade at the map boundary to avoid a hard square.
fn visibility(position: vec3<f32>, normal: vec3<f32>, skylight: f32) -> f32 {
    let fallback = smoothstep(0.75, 0.98, skylight);
    if (frame.has_shadow == 0u) { return fallback; }
    let ndl = max(dot(normal, frame.light_direction), 0.0);
    let bias = max(frame.shadow_center_texel, 0.005) * (0.6 + 1.5 * (1.0 - ndl));
    let p = shadow_position(position + normal * bias + frame.light_direction * bias * 0.3);
    if (any(p.xy <= vec2<f32>(0.002)) || any(p.xy >= vec2<f32>(0.998)) || p.z <= 0.0 || p.z >= 1.0) {
        return fallback;
    }
    var lit = 0.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * shadow_softness / frame.shadow_resolution;
            lit += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + offset, p.z);
        }
    }
    let edge = max(abs(p.x * 2.0 - 1.0), abs(p.y * 2.0 - 1.0));
    return mix(lit / 9.0, fallback, smoothstep(0.88, 0.99, edge));
}

// Keep terrain and its planar reflection in the same aerial perspective.
// Water extinction belongs to the post stage, so it is applied exactly once.
fn apply_surface_atmosphere(position: vec3<f32>, color: vec4<f32>) -> vec4<f32> {
    if(frame.eye_in!=0u) {return color;}
    let distance=max(length(position.xz),abs(position.y));
    let day=smoothstep(-0.10,0.15,frame.sun_direction.y);
    let direction=normalize(position);
    let summer=palette_radiance(mix(SKY_HORIZON,SKY_ZENITH,1.0-exp(-max(direction.y,0.0)*16.0)));
    let fog_color=mix(frame.fog_color,summer,day*(1.0-frame.rain));
    let fade=smoothstep(frame.render_distance*0.80,frame.render_distance*0.98,distance);
    return vec4<f32>(mix(color.rgb,fog_color,fade),color.a);
}

fn material(input: MaterialInput) -> Surface {
    // Keep the game's dimension-specific lighting outside the Overworld.
    if (frame.dimension != 0) {
        return Surface(input.albedo * input.tint * vec4<f32>(input.lightmap, 1.0));
    }
    if (input.fluid == 1u && input.translucent) { return Surface(apply_surface_atmosphere(input.position,summer_water(input).color)); }
    let normal = normalize(input.normal);
    let day = smoothstep(-0.08, 0.16, frame.sun_direction.y);
    let light_color = mix(to_linear(vec3<f32>(0.42,0.55,0.77)),to_linear(daylight_color())*biome_sun_tint(),day);
    let weather = (1.0 - 0.85 * frame.rain)*(1.0-frame.thunder*weather_response*0.18);
    let strength = mix(0.18, sunlight_strength, day) * weather;
    let shadow = visibility(input.position, normal, input.light.y);
    let diffuse = max(dot(normal, frame.light_direction), 0.0);
    let leaf = input.material >= 10u && input.material <= 15u;
    let view_ray = input.position / max(length(input.position), 0.001);
    let forward_scatter = pow(max(dot(view_ray, frame.light_direction), 0.0), 6.0);
    let thinness = select(1.0, 1.3, input.material >= 11u && input.material <= 13u);
    let transmission = select(0.0, foliage_transmission * thinness * (0.15 + 0.4 * max(dot(-normal, frame.light_direction), 0.0) + 0.8 * forward_scatter), leaf);
    // Broad cloud shadow uses the same moving density field as the cloud pass.
    var cloud_visibility = 1.0;
    if (cloud_shadows > 0.0 && frame.sun_direction.y > 0.08) {
        let world = input.position + frame.camera_position;
        let travel = max((218.0 - world.y) / frame.sun_direction.y, 0.0);
        let cover = cloud_mass(world + frame.sun_direction * travel, false);
        cloud_visibility = mix(1.0, exp(-cover * 2.0), cloud_shadows);
    }
    // Lambertian diffuse plus separate transmission through thin foliage.
    let direct = light_color * strength * (diffuse + transmission) * shadow * cloud_visibility;
    let sky_access = pow(input.light.y, 1.5);
    let hemisphere = mix(0.4, 1.0, normal.y * 0.5 + 0.5);
    let sky_tint = mix(to_linear(vec3<f32>(0.18,0.26,0.42)),to_linear(SKY_AMBIENT),day);
    let ambient = sky_tint * biome_ambient_tint() * ambient_strength * sky_access * hemisphere * mix(1.8,1.0,day);
    let block_tint = block_light_color(input.position);
    let lamp_color = mix(palette_linear(vec3<f32>(1.0, 0.57, 0.25)), block_tint.rgb, clamp(block_tint.a, 0.0, 1.0));
    let lamp = lamp_color * pow(input.light.x, 2.2) * 1.35;
    // Artistic ground bounce, sky-gated so caves do not glow.
    let bounce = vec3<f32>(0.035,0.045,0.020) * sky_access * day * (1.0 - 0.4 * frame.rain);
    let cherry_bounce=palette_linear(vec3<f32>(0.92,0.59,0.72))*0.085*cherry_weight()*biome_character
        *select(0.0,1.0,biome_light_tint)*sky_access*day*(1.0-shadow*diffuse);
    let jungle_bounce=vec3<f32>(0.022,0.045,0.015)*jungle_weight()*biome_character
        *day*smoothstep(0.05,0.45,input.light.y)*(1.0-shadow*diffuse*0.75);
    let illumination = (direct + ambient + bounce + cherry_bounce + jungle_bounce)*biome_light_level()
        + lamp + input.colored_light + vec3<f32>(0.006);
    // Lift baked tint magnitude without changing its hue: reduce double shading.
    let tint_peak = max(max(input.tint.r, input.tint.g), input.tint.b);
    let cross_plant=input.material>=11u && input.material<=13u;
    let face_shade=select(abs(normal.x)*0.6+abs(normal.z)*0.8+abs(normal.y)*select(0.5,1.0,normal.y>0.0),1.0,cross_plant);
    // Remove the known baked cardinal shade while retaining vertex AO.
    let tint = input.tint.rgb / pow(max(face_shade,0.5),2.2) / pow(max(tint_peak,0.08),0.15);
    var base = to_display(input.albedo.rgb*tint);
    let green_mask=smoothstep(1.05,1.6,base.g/max(max(base.r,base.b),0.015));
    // Restrained palette bias preserves texture detail and non-green flowers.
    let lit_leaf=clamp(diffuse*shadow*cloud_visibility,0.0,1.0);
    let palette=biome_foliage_palette(lit_leaf);
    let palette_luma=dot(palette,vec3<f32>(0.2126,0.7152,0.0722));
    let base_luma=dot(base,vec3<f32>(0.2126,0.7152,0.0722));
    base=mix(base,palette*base_luma/max(palette_luma,0.01),green_mask*mix(0.35,0.65,clamp((jungle_weight()+taiga_weight()+swamp_weight()+savanna_weight())*biome_character,0.0,1.0)));
    let damp=humid_wetness()*smoothstep(0.10,0.65,input.light.y);
    let moisture_material=select(0.0,1.0,leaf || input.material==22u || input.material==23u);
    base*=1.0-damp*moisture_material*select(0.10,0.17,input.material==23u);
    let albedo=to_linear(base);
    var linear = albedo * max(illumination, vec3<f32>(input.emission));
    // Soft dielectric sheen: strongest on leaves and upward-facing wet surfaces.
    let half_sum = frame.light_direction - view_ray;
    let half_vector = half_sum / max(length(half_sum), 0.001);
    var smoothness = select(0.04, 0.25, leaf) + frame.wetness * max(normal.y, 0.0) * 0.25 + damp*moisture_material*0.20;
    let gloss = pow(max(dot(normal, half_vector), 0.0), mix(12.0, 64.0, smoothness));
    linear += light_color * gloss * smoothness * surface_sheen * shadow * cloud_visibility * day;
    // Antialiased beads on leaves/vines catch small sharp glints.
    // Their relief follows a face-local world projection, not the screen.
    if(damp>0.001 && leaf) {
        let world=input.position+frame.camera_position;
        let plane=select(select(world.xy,world.zy,abs(normal.x)>0.5),world.xz,abs(normal.y)>0.5);
        let grid=plane*22.0;let cell=floor(grid);let uv=fract(grid);
        let center=vec2<f32>(0.2)+vec2<f32>(env_hash(cell),env_hash(cell+31.9))*0.6;
        let d=length((uv-center)*vec2<f32>(1.0,1.4));
        let aa=max(fwidth(d),0.015);
        let bead=1.0-smoothstep(0.06-aa,0.13+aa,d);
        let resolved=1.0-smoothstep(0.20,0.55,max(length(dpdx(grid)),length(dpdy(grid))));
        let bead_glint=pow(max(dot(normal,half_vector),0.0),96.0);
        linear+=light_color*bead*resolved*damp*(bead_glint*2.0+gloss*0.15)
            *shadow*cloud_visibility*day;
        linear+=ambient*damp*0.035*(0.3+0.7*pow(1.0-abs(dot(normal,view_ray)),4.0));
    }
    var shading_normal=normal;
    // Rain collects on open, upward-facing solid surfaces. No puddles on
    // foliage, snow, ice, walls, water, or sheltered cave floors.
    let rain_wet=frame.wetness*select(0.0,1.0,frame.precipitation==1u);
    let humid_ground=select(0.0,damp*0.55,input.material==22u);
    let wet=max(rain_wet,humid_ground)*puddle_strength;
    if(wet>0.001 && !leaf && input.material!=20u && input.material!=21u && input.fluid==0u && normal.y>0.95) {
        let world=input.position+frame.camera_position;
        let pattern=env_noise(world.xz*0.13)*0.74+env_noise(world.xz*0.43+12.0)*0.26;
        let pool=smoothstep(0.60-wet*0.22,0.75-wet*0.16,pattern)*wet*smoothstep(mix(0.90,0.30,humid_ground),mix(1.0,0.75,humid_ground),input.light.y);
        let footprint=max(length(dpdx(world.xz)),length(dpdy(world.xz)));
        let ripple=rainfall_slope(world.xz,footprint);
        let puddle_normal=normalize(vec3<f32>(ripple.x,1.0,ripple.y));
        let fresnel=0.02+0.98*pow(1.0-clamp(dot(puddle_normal,-view_ray),0.0,1.0),5.0);
        let reflected=water_sky(reflect(view_ray,puddle_normal));
        let specular=pow(max(dot(puddle_normal,half_vector),0.0),180.0)*shadow*cloud_visibility*day*weather;
        let puddle=mix(linear*0.70,reflected,fresnel)+light_color*specular*0.8;
        linear=mix(linear,puddle,clamp(pool,0.0,1.0));
        smoothness=mix(smoothness,0.9,pool);
        shading_normal=normalize(mix(normal,puddle_normal,pool));
    }
    set_surface(shading_normal, smoothness, input.light.y);
    linear = mix(linear, max(linear, albedo * 0.8), frame.night_vision);
    return Surface(apply_surface_atmosphere(input.position,vec4<f32>(linear,input.albedo.a*input.tint.a)));
}
