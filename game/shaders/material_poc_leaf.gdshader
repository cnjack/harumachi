shader_type spatial;
render_mode cull_disabled,specular_disabled,alpha_to_coverage;
uniform sampler2D albedo_tex : source_color,filter_linear_mipmap_anisotropic,repeat_disable;
uniform float poc_night=0.;
uniform float height=7.;
global uniform float wind_strength;
global uniform vec2 wind_direction;
varying float leaf_height;
void vertex(){
 leaf_height=VERTEX.y/max(height,.1);
 vec3 wind=vec3(wind_direction.x,0,wind_direction.y);
 vec3 bend=wind*(sin(TIME*.85+NODE_POSITION_WORLD.x*.3)*.018+sin(TIME*1.6+VERTEX.x*2.7)*.006)*wind_strength*pow(clamp(leaf_height,0.,1.),2.);
 VERTEX+=(inverse(MODEL_MATRIX)*vec4(bend,0)).xyz;
}
void fragment(){
 vec4 tex=texture(albedo_tex,UV);
 // UV is exported independently of the temporary source material's vertex colours.
 bool inner=UV.x<-.5;
 vec3 paint=inner?vec3(.10,.24,.036):mix(vec3(.045,.14,.028),vec3(.19,.31,.055),smoothstep(.11,.35,tex.g));
 ALBEDO=paint*COLOR.rgb*mix(vec3(1),vec3(.58,.73,1.10),poc_night);
 // The imported mip chain preserves coverage at this exact alpha-test threshold.
 ALPHA=inner?1.:tex.a;
 ALPHA_SCISSOR_THRESHOLD=.35;
 ALPHA_ANTIALIASING_EDGE=.20;
 ALPHA_TEXTURE_COORDINATE=UV*vec2(textureSize(albedo_tex,0));
 ROUGHNESS=1.;
 AO=mix(.76,1.,smoothstep(.25,.95,leaf_height));
}
void light(){
 float nl=dot(NORMAL,LIGHT);
 float light_band=mix(.20,.62,smoothstep(-.1,.15,nl));
 light_band=mix(light_band,1.,smoothstep(.35,.53,nl));
 float translucency=pow(max(-nl,0.),3.)*.12;
 DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*(light_band+translucency)/3.14159265;
}
