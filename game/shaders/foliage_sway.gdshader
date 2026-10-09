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
global uniform float wind_strength;
global uniform vec2 wind_direction;
void vertex() {
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
 ALBEDO=colour.rgb;ALPHA=colour.a;ALPHA_SCISSOR_THRESHOLD=alpha_scissor;
 if(!FRONT_FACING)NORMAL=-NORMAL;
 if(part_role==1)NORMAL=normalize(mix(NORMAL,(VIEW_MATRIX*vec4(0,1,0,0)).xyz,.45));
 ROUGHNESS=1.0;
}
