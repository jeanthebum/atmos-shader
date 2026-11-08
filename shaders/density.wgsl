override cloud_coverage: f32 = 0.38;
override cloud_density: f32 = 1.0;

// Procedural data texture, generated locally from a fixed seed. No reference assets.
fn noise3(p: vec3<f32>) -> f32 {
    let cell = floor(p);
    let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
    let xy = cell.xy + cell.z * vec2<f32>(37.0, 17.0) + u.xy;
    let a = textureSampleLevel(density_noise, density_noise_sampler, (xy + 0.5) / 256.0, 0.0).r;
    let b = textureSampleLevel(density_noise, density_noise_sampler, (xy + vec2<f32>(37.5, 17.5)) / 256.0, 0.0).r;
    return mix(a, b, u.z);
}
fn cloud_volume_at(p: vec3<f32>) -> vec4<f32> {
    // 71 cubed, packed15x5 with wrapped one-texel gutters. Both atlas axes
    // remain below Horizon's2048px limit; all RGBA scalar channels are retained.
    let q = fract(p) * 71.0;
    let iz = u32(floor(q.z)); let next = (iz+1u)%71u;
    let uv0 = (vec2<f32>(f32(iz%15u),f32(iz/15u))*73.0 + q.xy+1.5)/vec2<f32>(1095.0,365.0);
    let uv1 = (vec2<f32>(f32(next%15u),f32(next/15u))*73.0 + q.xy+1.5)/vec2<f32>(1095.0,365.0);
    let a=textureSampleLevel(cloud_volume,cloud_volume_sampler,uv0,0.0);
    let b=textureSampleLevel(cloud_volume,cloud_volume_sampler,uv1,0.0);
    return mix(a,b,fract(q.z));
}
fn cloud_mass(world: vec3<f32>, detailed: bool) -> f32 {
    let height=(world.y-185.0)/155.0;
    if (height<=0.0 || height>=1.0 || cloud_coverage<=0.0) { return 0.0; }
    let p=world+vec3<f32>(frame.time*0.7,0.0,frame.time*0.21);
    let weather=noise3(vec3<f32>(p.x*0.0014,4.7,p.z*0.0014));
    let warp=vec3<f32>(noise3(p*0.003),0.0,noise3(p*0.003+17.0))-vec3<f32>(0.5,0.0,0.5);
    let q=p*vec3<f32>(0.0022,0.0032,0.0022)+warp*0.10;
    let volume=cloud_volume_at(q);
    // Dilate a connected Perlin mass with packed cellular billows, rather than
    // averaging the noises into a featureless blob. R is Perlin, A coarse
    // Worley, G medium billows, B fine erosion in the generated data volume.
    let cellular=volume.a*0.70+volume.g*0.30;
    let shape=(volume.r+cellular)/(1.0+cellular);
    // Keep the condensation surface inside the integration bounds. A fixed
    // seven-metre floor clipped thick banks into broad flat plates overhead.
    let base_height=0.065+(1.0-volume.g)*0.16+(1.0-volume.b)*0.045;
    let lower=smoothstep(base_height,base_height+0.12,height);
    let profile=lower*(1.0-smoothstep(0.50,1.0,height));
    // Weather controls entire cloud banks and blue gaps. Detail below cannot
    // create isolated islands outside this connected parent mass.
    let storm=storm_amount();
    let cover=clamp(0.375+(cloud_coverage-0.42)*0.55+(weather-0.5)*mix(0.50,0.24,storm)+frame.rain*0.09+storm*0.16,
        0.02,0.46+(cloud_coverage-0.42)*0.45+frame.rain*0.20+storm*0.10);
    var density=shape-(1.0-cover)-(1.0-profile)*0.22;
    if (density<=0.0) { return 0.0; }
    let edge=1.0-smoothstep(0.08,0.26,density);
    if (detailed) {
        let turbulence=cloud_volume_at(q*1.7+vec3<f32>(0.13,0.47,0.71)).gba-vec3<f32>(0.5);
        let detail_q=q+turbulence*0.10;
        // Cellular channels have a deliberately narrow statistical range.
        // Expand it before erosion so secondary billows displace the surface,
        // rather than merely putting wisps around a smooth parent sphere.
        let medium=clamp((cloud_volume_at(detail_q*1.73+0.17).g-0.20)*1.75,0.0,1.0);
        let fine=clamp((cloud_volume_at(detail_q*3.53+0.31).b-0.20)*1.75,0.0,1.0);
        let micro=clamp((cloud_volume_at(detail_q*7.17+0.73).b-0.20)*1.75,0.0,1.0);
        let erosion=(1.0-medium)*0.145+(1.0-fine)*0.065+(1.0-micro)*0.018;
        density-=erosion*edge;
    } else {
        // Average the omitted erosion for distant light/shadow/reflection
        // queries. An un-eroded envelope casts much wider shadows than the
        // visible cumulus and closes blue gaps in water reflections.
        density-=0.114*edge;
    }
    // A liquid-water gradient, not a nearly binary surface. The former 0.025
    // transition made most of each underside uniformly opaque within one ray
    // step; sparse light probes then stamped large hard patches into that skin.
    let liquid=smoothstep(0.0,0.065,density);
    let interior=0.70+0.30*volume.g;
    return liquid*interior*cloud_density*(1.0+storm*0.65)*mix(0.55,1.0,smoothstep(0.0,0.45,height));
}
