shader_type spatial;
uniform float poc_night=0.;
render_mode cull_disabled,specular_disabled,depth_prepass_alpha;
uniform sampler2D albedo_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 albedo_color:source_color=vec4(1);
uniform bool has_texture=true;
uniform float alpha_scissor=.42;
uniform vec3 crown_center=vec3(0,3,0);
uniform vec3 crown_radius=vec3(2);
uniform float height=5.;
uniform bool mixed_tree=false;
global uniform float wind_strength;
global uniform vec2 wind_direction;
varying vec3 crown_p;
varying vec3 crown_n;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){
 crown_p=VERTEX;
 vec3 radial=(VERTEX-crown_center)/max(crown_radius,vec3(.2));
 crown_n=normalize(MODEL_NORMAL_MATRIX*normalize(radial+vec3(0,.65,0)));
 float w=pow(clamp(VERTEX.y/max(height,.1),0.,1.),3.);
 vec3 bend=vec3(wind_direction.x,0,wind_direction.y)*sin(TIME*.7+NODE_POSITION_WORLD.x*.31)*.006*height*wind_strength*w;
 VERTEX+=(inverse(MODEL_MATRIX)*vec4(bend,0)).xyz;
}
void fragment(){
 vec4 leaf=(has_texture?texture(albedo_tex,UV):vec4(1))*albedo_color;
 float value=dot(leaf.rgb,vec3(.30,.59,.11));
 // Broad painted groups carry the canopy; the source image contributes quieter leaf marks.
 float cluster=noise(crown_p*1.55)*.68+noise(crown_p*.53+vec3(7,2,11))*.32;
 float group=smoothstep(.39,.63,cluster);
 vec3 colour=mix(vec3(.020,.10,.045),vec3(.20,.34,.045),group);
 colour*=.88+smoothstep(.02,.62,value)*.20;
 float leaf_mask=mixed_tree?smoothstep(1.02,1.22,leaf.g/max(leaf.r,.001)):1.;
 ALBEDO=mix(leaf.rgb,colour,leaf_mask)*mix(vec3(1),vec3(.65,.78,1.5),poc_night);
 ALPHA=leaf.a;ALPHA_SCISSOR_THRESHOLD=alpha_scissor;
 vec3 broad_normal=normalize((VIEW_MATRIX*vec4(crown_n,0)).xyz);
 NORMAL=normalize(mix(NORMAL,broad_normal,leaf_mask));
 ROUGHNESS=1.;
 AO=mix(1.,mix(.72,1.,smoothstep(-.8,.65,(crown_p.y-crown_center.y)/max(crown_radius.y,.2))),leaf_mask);
}
void light(){
 float ndl=dot(NORMAL,LIGHT);
 float band=mix(.12,1.,smoothstep(.15,.37,ndl));
 float transmission=pow(max(-ndl,0.),3.)*.10;
 DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*(band+transmission)/3.14159265;
}
