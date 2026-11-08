override cloud_quality: u32 = 1u;

fn cloud_phase(mu: f32, g: f32) -> f32 {
    return (1.0-g*g)/pow(max(1.0+g*g-2.0*g*mu,0.001),1.5);
}

fn post(input: PostInput) -> vec4<f32> {
    if (frame.dimension != 0 || frame.eye_in != 0u || cloud_coverage <= 0.0 || cloud_quality == 3u) { return vec4<f32>(0.0); }
    let endpoint = view_position(input.uv, max(input.depth, 0.000001));
    let ray = normalize(endpoint);
    if (abs(ray.y) < 0.008) { return vec4<f32>(0.0); }
    let bottom = (185.0 - frame.camera_position.y) / ray.y;
    let top = (340.0 - frame.camera_position.y) / ray.y;
    let start = max(min(bottom, top), 0.0);
    let terrain_end = select(length(endpoint), 3000.0, input.depth == 0.0);
    let end = min(min(max(bottom, top), 3000.0), terrain_end);
    if (end <= start) { return vec4<f32>(0.0); }
    // Spend extra samples where low-angle rays travel far through the cloud layer.
    let base_steps_raw = select(select(select(64, 128, cloud_quality == 1u), 256, cloud_quality >= 2u && cloud_quality != 4u),32,cloud_quality==4u);
    let base_steps=select(base_steps_raw,384,cloud_quality==5u);
    let target_stride_raw = select(select(select(4.5, 2.0, cloud_quality == 1u), 0.75, cloud_quality >= 2u && cloud_quality != 4u),7.0,cloud_quality==4u);
    let target_stride=select(target_stride_raw,0.5,cloud_quality==5u);
    let steps = clamp(i32(ceil((end-start)/target_stride)),base_steps,base_steps*5);
    let stride = (end - start) / f32(steps);
    let sun = frame.light_direction;
    let day = smoothstep(-0.08, 0.18, frame.sun_direction.y);
    let mu=clamp(dot(ray,sun),-1.0,1.0);
    // A broad backward lobe keeps the anti-solar side luminous; the forward
    // lobe produces silver linings only where optical depth allows sunlight in.
    let phase=0.55+0.45*min(cloud_phase(mu,0.72)*0.80+cloud_phase(mu,-0.25)*0.20,5.0);
    let sun_color=mix(vec3<f32>(0.012,0.020,0.040),palette_linear(daylight_color()),day);
    let jitter = textureLoad(density_noise,vec2<i32>(input.pixel)%vec2<i32>(256),0).g;
    // Cloud aerial perspective must not reuse the rendered sky: it contains
    // the bright solar disk, which would then leak through opaque cloud.
    let air_color=mix(vec3<f32>(0.005,0.009,0.022),
        mix(palette_radiance(mix(SKY_HORIZON,SKY_ZENITH,1.0-exp(-max(ray.y,0.0)*16.0))),
            palette_linear(vec3<f32>(0.38,0.42,0.48)),storm_amount()),day);
    var transmission = 1.0; var radiance = vec3<f32>(0.0);
    var cached_energy=vec3<f32>(0.0);
    var has_lighting=false;
    let lighting_interval=select(select(select(3,2,cloud_quality==1u),1,cloud_quality>=2u && cloud_quality!=4u),4,cloud_quality==4u);
    var distance=start+jitter*stride;
    for (var i = 0; i < steps; i = i + 1) {
        if(distance>=end) {break;}
        let p = frame.camera_position + ray * distance;
        let density = cloud_mass(p, true);
        if (density < 0.002) {
            // Fine integration resumes as soon as we enter a visible bank.
            // Empty sky needs no expensive lighting and tolerates longer steps.
            distance+=stride*select(2.0,1.0,cloud_quality>=2u && cloud_quality!=4u);
            has_lighting=false;
            continue;
        }
        if(!has_lighting || (transmission>0.015 && i%lighting_interval==0)) {
        var optical=0.0;
        var light_travel=0.0;
        let light_steps_raw=select(select(select(9,12,cloud_quality==1u),16,cloud_quality>=2u && cloud_quality!=4u),6,cloud_quality==4u);
        let light_steps=select(light_steps_raw,20,cloud_quality==5u);
        let fine_probes_raw=select(select(select(4,7,cloud_quality==1u),10,cloud_quality>=2u && cloud_quality!=4u),2,cloud_quality==4u);
        let fine_probes=select(fine_probes_raw,14,cloud_quality==5u);
        let probe_growth=select(1.5,1.4,cloud_quality>=2u && cloud_quality!=4u);
        let cone_axis=normalize(cross(sun,vec3<f32>(0.0,1.0,0.01)));
        for(var j=0;j<light_steps;j=j+1) {
            let width=pow(probe_growth,f32(j));
            let probe=p+sun*(light_travel+width*0.5);
            var sampled=0.0;
            if(j<fine_probes) {
                sampled=cloud_mass(probe,true);
            } else {
                // Distant probes represent a widening region. A single binary
                // point here stamped the parent cells into broad shadow plates.
                let spread=cone_axis*min(1.5+light_travel*0.07,9.0);
                sampled=(cloud_mass(probe-spread,false)+cloud_mass(probe+spread,false))*0.5;
            }
            optical+=sampled*width*0.18;
            light_travel+=width;
        }
        let sunlight=exp(-optical);
        let powder=1.0-exp(-density*3.0);
        let powder_view=mix(0.55+powder*0.80,1.0,smoothstep(0.0,0.7,mu));
        // Three declining multiple-scattering orders preserve blue-grey depth
        // without flattening every optically thick surface to the same grey.
        let multiple=exp(-optical*0.30)*0.30+exp(-optical*0.07)*0.14+exp(-optical*0.02)*0.07;
        let height = clamp((p.y - 185.0) / 155.0, 0.0, 1.0);
        let sky_optical=(cloud_mass(p+vec3<f32>(0.0,5.0,0.0),true)*6.0
            +cloud_mass(p+vec3<f32>(0.0,18.0,0.0),false)*15.0
            +cloud_mass(p+vec3<f32>(0.0,45.0,0.0),false)*32.0)*0.065;
        let sky_access=0.35+0.65*exp(-sky_optical*0.6);
        let ambient=sky_access*mix(vec3<f32>(0.20,0.25,0.35),vec3<f32>(0.30,0.40,0.60),height)*mix(0.035,1.0,day);
        let storm=storm_amount();
        cached_energy=ambient*(1.0-storm*0.40)+sun_color*(sunlight*phase*1.35+multiple)*powder_view*(1.0-frame.rain*0.6)*(1.0-storm*0.45);
        has_lighting=true;
        }
        let haze = 1.0 - exp(-distance * 0.00055);
        // Continue density integration after light becomes visually negligible;
        // it still matters for blocking the HDR sun behind an opaque cloud.
        let cloud_color = mix(cached_energy, air_color, haze * 0.65);
        let alpha=(1.0-exp(-density*stride*0.18))*(1.0-smoothstep(1200.0,3000.0,distance));
        radiance += transmission * alpha * cloud_color;
        transmission *= 1.0 - alpha;
        // Tiny residuals matter against a bright HDR solar disk. Stopping at
        // 0.8% transmission makes the sun visible even through thick cloud.
        if (transmission < 0.0002) { break; }
        distance+=stride;
    }
    return vec4<f32>(radiance,1.0-transmission);
}
