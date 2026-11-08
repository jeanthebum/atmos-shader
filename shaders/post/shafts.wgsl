override rays_strength: f32 = 1.0;
override rays_density: f32 = 1.0;
override rays_quality: u32 = 1u;

// Sunlight reaching air through the same moving cloud volume as the sky.
// Cache along the view ray, not across unrelated pixels.
fn beam_cloud_visibility(world: vec3<f32>) -> f32 {
    if (cloud_coverage <= 0.0) { return 1.0; }
    let sun = frame.sun_direction;
    let start = max((185.0 - world.y) / max(sun.y, 0.025), 0.0);
    let end = max((340.0 - world.y) / max(sun.y, 0.025), start);
    // Low sunlight crosses more cloud banks. Increase this budget at sunset
    // so a few widely separated probes cannot jump over an entire cloud.
    let minimum_base = select(select(4,6,rays_quality==1u),10,rays_quality==2u);
    let minimum=select(minimum_base,12,rays_quality==3u);
    let maximum_base = select(select(8,16,rays_quality==1u),24,rays_quality==2u);
    let maximum=select(maximum_base,32,rays_quality==3u);
    let samples = clamp(i32(ceil((end-start)/48.0)),minimum,maximum);
    let stride = (end - start) / f32(samples);
    var optical = 0.0;
    for (var i = 0; i < samples; i = i + 1) {
        let p = world + sun * (start + (f32(i) + 0.5) * stride);
        optical += cloud_mass(p, false) * stride * 0.18;
        if (optical > 8.0) { return 0.0; }
    }
    return exp(-optical);
}

fn beam_phase(mu: f32, g: f32) -> f32 {
    return (1.0 - g*g) / pow(max(1.0 + g*g - 2.0*g*mu, 0.001), 1.5);
}

// RGB is in-scattered radiance, A is remaining view transmission. The neutral
// value must have A=1, including underwater/night/disabled paths.
fn post(input: PostInput) -> vec4<f32> {
    let neutral = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    let day = smoothstep(0.0, 0.12, frame.sun_direction.y);
    if (frame.dimension != 0 || frame.eye_in != 0u || frame.has_shadow == 0u ||
        rays_strength <= 0.0 || rays_density <= 0.0 || atmosphere_density <= 0.0 || day <= 0.0) {
        return neutral;
    }
    let endpoint = view_position(input.uv, max(input.depth, 0.000001));
    let ray = normalize(endpoint);
    var distance = min(length(endpoint), 240.0);
    // Air in front of the clouds only. Their own pass integrates cloud light.
    if (cloud_coverage > 0.0) {
        if (frame.camera_position.y >= 185.0) { return neutral; }
        if (ray.y > 0.001) {
            distance = min(distance, (185.0 - frame.camera_position.y) / ray.y);
        }
    }
    if (distance <= 0.01) { return neutral; }
    let steps = select(select(select(32, 64, rays_quality == 1u), 96, rays_quality == 2u),128,rays_quality==3u);
    let jitter = textureLoad(density_noise, vec2<i32>(input.pixel) % vec2<i32>(256), 0).g;
    let mu = clamp(dot(ray, frame.sun_direction), -1.0, 1.0);
    // Broad aerosol scattering makes oblique woodland beams visible. The
    // forward lobe still gives the strongest glow when facing the sun.
    let phase = 0.06 + 0.15 * beam_phase(mu, 0.72);
    let sunlight = palette_linear(daylight_color()) * 2.2 * phase;
    let weather = day * (1.0 - frame.rain * 0.85);
    var transmission = 1.0;
    var radiance = vec3<f32>(0.0);
    var cloud_start = beam_cloud_visibility(frame.camera_position);
    var cloud_end = cloud_start;
    for (var i = 0; i < steps; i = i + 1) {
        let a = f32(i) / f32(steps);
        let b = f32(i + 1) / f32(steps);
        // Quadratic placement resolves the first few metres under a canopy.
        let near = distance * a*a;
        let far = distance * b*b;
        let t = mix(near, far, 0.15 + 0.70*jitter);
        let position = ray * t;
        let world = frame.camera_position + position;
        if (i % 4 == 0) {
            cloud_start = cloud_end;
            let next = f32(min(i + 4, steps)) / f32(steps);
            cloud_end = beam_cloud_visibility(frame.camera_position + ray * (distance * next*next));
        }
        let knot_a = f32((i / 4) * 4) / f32(steps);
        let knot_b = f32(min((i / 4 + 1) * 4, steps)) / f32(steps);
        let cloud_mix = clamp((t-distance*knot_a*knot_a) / max(distance*(knot_b*knot_b-knot_a*knot_a),0.001),0.0,1.0);
        let cloud = mix(cloud_start, cloud_end, cloud_mix);
        let sp = shadow_position(position);
        let edge = max(abs(sp.x * 2.0 - 1.0), abs(sp.y * 2.0 - 1.0));
        // Fade where the map cannot tell whether air is lit. Assuming full
        // sun here would leak beams through distant hills.
        let support = (1.0 - smoothstep(0.86, 0.98, edge)) *
            select(0.0, 1.0, sp.z > 0.0 && sp.z < 1.0);
        if (support <= 0.0) { continue; }
        let texel = 0.65 / frame.shadow_resolution;
        var lit = textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy + vec2<f32>(texel,texel), sp.z - 0.000015);
        lit += textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy - vec2<f32>(texel,texel), sp.z - 0.000015);
        lit *= 0.5 * cloud;
        let altitude = exp(-max(world.y - 64.0, 0.0) * 0.018);
        // Concentrate the visible mist in the part of the shadow volume with
        // useful foliage detail. A smooth distance fade avoids turning a clear
        // summer sky into a flat veil while retaining beams close to the player.
        let local_air = 0.0015 * exp(-t / 120.0) + 0.0030 * exp(-t / 24.0);
        let below_cloud = select(1.0, 1.0-smoothstep(165.0,185.0,frame.camera_position.y), cloud_coverage>0.0);
        let biome_air_boost=1.0+biome_character*biome_mist*(jungle_weight()*jungle_moisture*1.7+swamp_weight()*0.65+forest_weight()*0.7+taiga_weight()*0.5);
        let extinction = local_air * biome_air_boost * altitude * support * rays_density * atmosphere_density * weather * below_cloud;
        let opacity = 1.0 - exp(-extinction * (far - near));
        radiance += transmission * opacity * (sunlight * lit + palette_linear(SKY_AMBIENT) * 0.08);
        transmission *= 1.0 - opacity;
    }
    return vec4<f32>(radiance * rays_strength, mix(1.0, transmission, min(rays_strength,1.0)));
}
