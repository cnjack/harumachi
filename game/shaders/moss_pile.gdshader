shader_type spatial;
render_mode diffuse_burley,specular_disabled,cull_disabled,depth_prepass_alpha;
uniform sampler2D albedo_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 albedo_color:source_color=vec4(1);
uniform float height=6.8;
uniform int part_role=0;
uniform float shell_height=.001;
uniform float shell_layer=0.;
global uniform float wind_strength;
global uniform vec2 wind_direction;
varying vec3 root_position;
varying vec3 root_normal;
float mh(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float mn(vec3 p){
 vec3 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
 return mix(mix(mix(mh(i),mh(i+vec3(1,0,0)),f.x),mix(mh(i+vec3(0,1,0)),mh(i+vec3(1,1,0)),f.x),f.y),mix(mix(mh(i+vec3(0,0,1)),mh(i+vec3(1,0,1)),f.x),mix(mh(i+vec3(0,1,1)),mh(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){
 root_position=VERTEX-NORMAL*shell_height;root_normal=NORMAL;
 float h=clamp(root_position.y/max(height,.05),0.,1.);float weight=h*h*h;
 vec3 world=NODE_POSITION_WORLD;float phase=world.x*.37+world.z*.23;
 float gust=.65+.35*sin(TIME*.31+world.x*.05);
 float slow=sin(TIME*.65+phase)*.7+sin(TIME*1.07+phase*1.4)*.3;
 float amount=.002*wind_strength*gust*weight*max(height,.3);
 VERTEX+=(inverse(MODEL_MATRIX)*vec4(vec3(wind_direction.x,0,wind_direction.y)*slow*amount,0)).xyz;
}
void fragment(){
 vec3 p=root_position;
 float damp=(1.-smoothstep(.45,1.85,p.y))*(.70+.30*max(root_normal.y,root_normal.z));
 float patch=smoothstep(.50,.73,mn(p*2.1+vec3(5,2,9)))*damp;
 float strand=mh(floor(p*220.));
 float rim=smoothstep(.34+shell_layer*.12,.43+shell_layer*.12,patch);
 float pile=smoothstep(.035+shell_layer*.79,.085+shell_layer*.79,strand);
 vec3 weights=pow(abs(root_normal),vec3(4));weights/=max(dot(weights,vec3(1)),.0001);
 vec3 colour=texture(albedo_tex,p.yz*1.6).rgb*weights.x+texture(albedo_tex,p.xz*1.6).rgb*weights.y+texture(albedo_tex,p.xy*1.6).rgb*weights.z;
 ALBEDO=colour*mix(.72,1.08,shell_layer);
 ALPHA=rim*pile;ALPHA_SCISSOR_THRESHOLD=.42;ROUGHNESS=1.;
 if(!FRONT_FACING)NORMAL=-NORMAL;
}
