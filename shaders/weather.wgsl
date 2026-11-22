fn weather(input: WeatherInput) -> vec4<f32> {
    let day=smoothstep(-0.10,0.15,frame.sun_direction.y);
    let sky_access=pow(input.light.y,1.25);
    let sky=palette_linear(SKY_AMBIENT)*mix(0.025,0.65,day)*sky_access;
    let lamp=palette_linear(vec3<f32>(1.0,0.65,0.35))*pow(input.light.x,2.2)*0.7;
    if(input.snow) {
        return vec4<f32>((sky*1.6+lamp)*input.color.rgb,input.color.a*0.85);
    }
    if(frame.eye_in!=0u) {return vec4<f32>(0.0);}
    // Place animated beads on Horizon's rain columns in world coordinates.
    let world=input.position+frame.camera_position;
    let face=cross(dpdx(input.position),dpdy(input.position));
    let horizontal=select(world.x,world.z,abs(face.x)>abs(face.z));
    let grid=vec2<f32>(horizontal*5.0,world.y*1.8+frame.time*14.0);
    let cell=floor(grid);
    let seed=env_hash(cell);
    let center=vec2<f32>(0.25+0.5*seed,0.25+0.5*env_hash(cell+37.1));
    let p=(fract(grid)-center)*vec2<f32>(7.0,5.0);
    let visibility=select(0.0,1.0,seed<mix(0.38,0.75,clamp(rain_detail*0.5,0.0,1.0)));
    let r2=dot(p,p);
    let edge=clamp(fwidth(r2),0.018,1.2);
    let radius_px=1.0/max(fwidth(p.x),0.08);
    var coverage=(1.0-smoothstep(1.0-edge,1.0+edge,r2))*visibility;
    coverage*=clamp(radius_px*2.0,0.0,1.0);
    if(coverage<0.003) {return vec4<f32>(0.0);}

    let view=normalize(-input.position);
    let right=normalize(cross(vec3<f32>(0.0,1.0,0.0),view)+vec3<f32>(1e-6,0.0,0.0));
    let up=normalize(cross(view,right));
    let nz=sqrt(max(1.0-min(r2,0.999),0.001));
    var normal=normalize(right*p.x-up*p.y+view*nz);

    let facing=clamp(abs(dot(normal,view)),0.0,1.0);
    let fresnel=0.0204+0.9796*pow(1.0-facing,5.0);
    let reflected=reflect(-view,normal);
    let upper=clamp(reflected.y*0.5+0.5,0.0,1.0);
    var reflection=mix(sky*0.25,sky*1.7,upper)+lamp;
    let half_vector=normalize(frame.light_direction+view);
    let highlight=pow(max(dot(normal,half_vector),0.0),96.0);
    let sun=palette_linear(daylight_color())*day*(1.0-frame.rain*0.82);
    reflection+=sun*highlight*7.0*sky_access;

    // Alpha blending transmits the live scene through the clear center.
    let color=reflection+sun*highlight*0.75*sky_access;
    let distance=length(input.position);
    let opacity=coverage*(0.04+0.78*fresnel+0.18*highlight)
        *smoothstep(0.5,1.5,distance)*(1.0-smoothstep(18.0,38.0,distance));
    return vec4<f32>(max(color,vec3<f32>(0.0)),clamp(opacity,0.0,0.92));
}
