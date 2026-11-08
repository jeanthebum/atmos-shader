// Premultiplied cloud radiance reconstructed without filtering the terrain image.
fn cloud_path(uv: vec2<f32>, depth: f32) -> bool {
    let p=view_position(uv,max(depth,0.000001));
    let ray=normalize(p);
    if(abs(ray.y)<0.008) {return false;}
    let a=(185.0-frame.camera_position.y)/ray.y;
    let b=(340.0-frame.camera_position.y)/ray.y;
    let start=max(min(a,b),0.0);
    let end=min(max(a,b),select(length(p),3000.0,depth==0.0));
    return end>start && start<3000.0;
}

fn post(input: PostInput) -> vec4<f32> {
    if(frame.dimension!=0 || frame.eye_in!=0u || !cloud_path(input.uv,input.depth)) {return input.color;}
    let size=vec2<f32>(textureDimensions(cloud_light));
    let grid=input.uv*size-0.5;
    let base=floor(grid); let f=fract(grid);
    var weight_sum=0.0; var cloud=vec4<f32>(0.0);
    for(var y=0;y<2;y=y+1) {
        for(var x=0;x<2;x=x+1) {
            let texel=clamp(vec2<i32>(base)+vec2<i32>(x,y),vec2<i32>(0),vec2<i32>(size)-1);
            let uv=(vec2<f32>(texel)+0.5)/size;
            if(!cloud_path(uv,depth_at(uv))) {continue;}
            let w=select(1.0-f.x,f.x,x==1)*select(1.0-f.y,f.y,y==1);
            cloud+=textureLoad(cloud_light,texel,0)*w;
            weight_sum+=w;
        }
    }
    cloud/=max(weight_sum,0.00001);
    return vec4<f32>(cloud.rgb+input.color.rgb*(1.0-cloud.a),input.color.a);
}
