shader_type spatial;
// A fixed root, slow bounded branch bend, and independent small leaf flutter.
render_mode diffuse_toon,specular_disabled,cull_disabled,depth_prepass_alpha;
uniform sampler2D albedo_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 albedo_color : source_color=vec4(1);
uniform float height=2.0;
uniform float anchored_height=0.0;
uniform float amp=.06;
uniform float speed=1.3;
uniform int part_role=2; // 0 trunk, 1 foliage, 2 crops and small plants
uniform float animation_time=-1.0;
uniform float alpha_scissor=.42;
uniform bool has_texture=true;
uniform bool aged_bark=false;
uniform bool meadow_foliage=false;
varying vec3 tree_position;
varying vec3 tree_normal;
global uniform float wind_strength;
global uniform vec2 wind_direction;
float bark_hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float bark_noise(vec3 p){
 vec3 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
 return mix(mix(mix(bark_hash(i),bark_hash(i+vec3(1,0,0)),f.x),mix(bark_hash(i+vec3(0,1,0)),bark_hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(bark_hash(i+vec3(0,0,1)),bark_hash(i+vec3(1,0,1)),f.x),mix(bark_hash(i+vec3(0,1,1)),bark_hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() {
 tree_position=VERTEX;tree_normal=NORMAL;
 float t=animation_time>=0.0?animation_time:TIME;
 float h=clamp((VERTEX.y-anchored_height)/max(height-anchored_height,.05),0.0,1.0);float weight=h*h*h;
 vec3 world=NODE_POSITION_WORLD;float phase=world.x*.37+world.z*.23;
 float gust=.65+.35*sin(t*.31+world.x*.05);
 float slow=sin(t*.65+phase)*.7+sin(t*1.07+phase*1.4)*.3;
 float amount=(part_role==0?.002:(part_role==1?.008:amp))*wind_strength*gust*weight*max(height,.3);
 vec3 bend=vec3(wind_direction.x,0,wind_direction.y)*slow*amount;
 VERTEX+=(inverse(MODEL_MATRIX)*vec4(bend,0)).xyz;
 if(part_role==1) {
  float leaf_phase=dot(VERTEX.xz,vec2(2.7,3.9));float flutter=sin(t*2.1+leaf_phase)*.004*wind_strength;
  VERTEX.y+=flutter;VERTEX.x+=flutter*.45;
 }
 // Use the tangent slope of the low amplitude bend rather than leaving normals stationary.
 NORMAL=normalize(NORMAL+vec3(-slow*amount*3.0/max(height,.3),0,0));
}
void fragment() {
 vec4 colour=(has_texture?texture(albedo_tex,UV):vec4(1))*albedo_color;
 if(meadow_foliage){
  float value=clamp(dot(colour.rgb,vec3(.30,.59,.11))*2.1,0.,1.);
  colour.rgb=mix(vec3(.048,.12,.025),vec3(.15,.29,.052),value);
 }
 if(aged_bark){
  float patches=bark_noise(tree_position*1.15+vec3(5,2,9));
  float basal=1.-smoothstep(.55,2.5,tree_position.y);
  float damp_side=smoothstep(-.3,.7,tree_normal.z)*(1.-smoothstep(1.5,4.0,tree_position.y));
  float painted_moss=smoothstep(.008,.055,colour.g-colour.r);
  float moss=max(painted_moss,smoothstep(.44,.68,patches)*(basal*.85+damp_side*.26));
  vec3 bark=colour.rgb*vec3(.43,.42,.40);
  float wood_value=dot(colour.rgb,vec3(.299,.587,.114));
  bark=mix(bark,vec3(.065,.085,.025)*clamp(wood_value/.35,.5,1.15),painted_moss);
  vec3 green=mix(vec3(.032,.065,.022),vec3(.083,.145,.040),floor(patches*3.)/2.);
  colour.rgb=mix(bark,green,clamp(moss,0.,.96)*.035);
 }
 ALBEDO=colour.rgb;ALPHA=colour.a;ALPHA_SCISSOR_THRESHOLD=alpha_scissor;
 if(!FRONT_FACING)NORMAL=-NORMAL;
 if(part_role==1)NORMAL=normalize(mix(NORMAL,(VIEW_MATRIX*vec4(0,1,0,0)).xyz,.45));
 ROUGHNESS=1.0;
}
