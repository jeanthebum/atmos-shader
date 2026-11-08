// API 0.2: the scene is already linear; decode only authored colour swatches.
const SUN_IVORY: vec3<f32> = vec3<f32>(255.0,226.0,160.0)/255.0; // #FFE2A0
const SKY_AMBIENT: vec3<f32> = vec3<f32>(134.0,189.0,241.0)/255.0; // #86BDF1
const SKY_ZENITH: vec3<f32> = vec3<f32>(67.0,143.0,217.0)/255.0; // #438FD9
const SKY_HORIZON: vec3<f32> = vec3<f32>(196.0,229.0,245.0)/255.0; // #C4E5F5
const LEAF_SUN: vec3<f32> = vec3<f32>(131.0,185.0,63.0)/255.0; // #83B93F
const LEAF_SHADE: vec3<f32> = vec3<f32>(36.0,91.0,70.0)/255.0; // #245B46
override brightness_gain: f32 = 1.0;
override night_exposure: f32 = 2.6;
override auto_exposure: f32 = 0.0;
override atmosphere_density: f32 = 1.0;

fn to_linear(c: vec3<f32>) -> vec3<f32> {return pow(max(c,vec3<f32>(0.0)),vec3<f32>(2.2));}
fn to_display(c: vec3<f32>) -> vec3<f32> {return pow(max(c,vec3<f32>(0.0)),vec3<f32>(1.0/2.2));}
fn palette_linear(c: vec3<f32>) -> vec3<f32> {return to_linear(c);}
fn palette_radiance(c: vec3<f32>) -> vec3<f32> {
    // Art-directed sky swatches expressed as radiance for the final fitted curve.
    let y=clamp(palette_linear(c),vec3<f32>(0.0),vec3<f32>(0.99));
    let a=2.51-2.43*y;
    let b=0.03-0.59*y;
    return (-b+sqrt(b*b+0.56*a*y))/(2.0*a);
}
fn daylight_color() -> vec3<f32> {
    // A restrained honey-gold sunset shared by terrain, clouds and water.
    return mix(vec3<f32>(1.0,0.76,0.44),SUN_IVORY,smoothstep(0.02,0.35,frame.sun_direction.y));
}
