override wind_strength: f32 = 0.7;
override wind_speed: f32 = 1.0;

fn vertex(input: VertexInput) -> vec3<f32> {
    if (input.material < 10u || input.material > 15u) { return input.position; }
    let world = input.position + frame.camera_position;
    let t = frame.time * wind_speed * (1.0-jungle_weight()*0.25+coast_weight()*0.20+savanna_weight()*0.15);
    // A shared world-space field keeps neighbouring leaf faces connected.
    let phase = dot(world.xz, vec2<f32>(0.53, 0.37));
    let gust = 0.65 + 0.35 * sin(t * 0.63 + dot(world.xz, vec2<f32>(0.08, 0.05)));
    let wave = sin(phase + t * 2.1) * 0.7 + sin(phase * 1.83 - t * 3.2) * 0.3;
    var bend = 1.0;
    var amplitude = 0.075;
    if (input.material >= 11u && input.material <= 13u) {
        // UV is sprite-local in VertexInput: bottom stays planted.
        let height = 1.0 - clamp(input.uv.y, 0.0, 1.0);
        bend = height;
        // Separate lower/upper sprites maintain continuity at tall-plant seams.
        if (input.material == 12u) { bend = height * 0.5; }
        if (input.material == 13u) { bend = 0.5 + height * 0.5; }
        bend *= bend;
        amplitude = 0.20;
    }
    let shelter = smoothstep(0.15, 0.85, input.light.y);
    let amount = wind_strength * amplitude * bend * gust * shelter * (1.0 + frame.rain * 0.6);
    let offset = vec3<f32>(wave, -abs(wave) * 0.12, sin(phase * 0.83 + t * 1.7) * 0.45);
    return input.position + offset * amount;
}
