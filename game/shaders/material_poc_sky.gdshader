shader_type sky;
// Shared generated cloud layout; no second, differently lit cloud layer on clear days.
uniform sampler2D sky_day:source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D sky_dusk:source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D sky_night:source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D moon_tex:source_color,filter_linear_mipmap,repeat_disable;
uniform float dusk_w=0.;
uniform float night_w=0.;
uniform float drift=0.;
uniform float dusk_offset=0.;
uniform float night_offset=0.;
uniform vec3 tint=vec3(1);
uniform float energy=1.;
uniform float cloud_cover=.28;
uniform vec3 sun_direction=vec3(.5,.7,.3);
uniform float sun_visibility=1.;
vec3 panorama(sampler2D source,vec2 uv){
 // Wrapped coordinates otherwise select an excessively blurred mip at the
 // longitude boundary, producing a vertical stripe when the camera turns.
 vec2 dx=dFdx(uv),dy=dFdy(uv);
 dx.x-=round(dx.x);dy.x-=round(dy.x);
 vec3 c=textureGrad(source,uv,dx,dy).rgb;
 float u=fract(uv.x);
 float seam=1.-smoothstep(0.,.025,min(u,1.-u));
 vec3 mirrored=textureGrad(source,vec2(-uv.x,uv.y),vec2(-dx.x,dx.y),vec2(-dy.x,dy.y)).rgb;
 return mix(c,(c+mirrored)*.5,seam);
}
void sky(){
 vec2 uv=vec2(SKY_COORDS.x*3.,clamp(.55+(SKY_COORDS.y-.5)*2.4,0.,1.));
 vec3 day=panorama(sky_day,uv+vec2(drift,0));
 vec3 dusk=panorama(sky_dusk,uv+vec2(drift,0));
 vec3 night=panorama(sky_night,uv+vec2(drift,0));
 vec3 c=mix(mix(day,dusk,dusk_w),night,night_w);
 float cloud_value=smoothstep(.10,.82,dot(day,vec3(.30,.59,.11)));
 float storm=smoothstep(.42,.96,cloud_cover);
 vec3 grey=mix(vec3(.15,.22,.34),vec3(.40,.49,.60),cloud_value);
 c=mix(c,grey,storm*.93*(1.-night_w));
 float sun_dot=dot(normalize(EYEDIR),normalize(sun_direction));
 float disk=smoothstep(cos(.013),cos(.009),sun_dot);
 float halo=pow(max(sun_dot,0.),160.)*.12;
 float white_cloud=smoothstep(.10,.72,min(day.r,min(day.g,day.b)));
 c*=mix(mix(mix(.82,1.85,white_cloud),.95,storm),.75,night_w);
 c+=mix(vec3(1.,.94,.74),vec3(1.,.58,.22),dusk_w)*(disk*3.+halo)*sun_visibility*(1.-night_w);
 // The moon, its directional light and the water highlight share one bearing.
 vec3 moon_dir=normalize(sun_direction);
 vec3 moon_right=normalize(cross(vec3(0,1,0),moon_dir));
 vec3 moon_up=normalize(cross(moon_dir,moon_right));
 vec2 moon_uv=vec2(dot(EYEDIR,moon_right),-dot(EYEDIR,moon_up))/.040+.5;
 if(night_w>.01 && sun_dot>.9 && all(greaterThanEqual(moon_uv,vec2(0))) && all(lessThanEqual(moon_uv,vec2(1)))){
  vec4 moon=texture(moon_tex,moon_uv);
  c=mix(c,moon.rgb*vec3(2.,2.1,2.3),moon.a*night_w*(1.-storm*.85));
 }
 c+=vec3(.04,.06,.10)*pow(max(sun_dot,0.),1800.)*night_w;
 COLOR=c;
}
