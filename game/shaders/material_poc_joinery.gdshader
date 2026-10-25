shader_type spatial;
render_mode diffuse_toon;
uniform vec4 base_colour:source_color=vec4(.7,.6,.4,1);
uniform int material_kind=0;
uniform float poc_night=0.;
uniform sampler2D reflected_sky:source_color,filter_linear_mipmap,repeat_enable;
uniform float sky_storm=0.;
varying vec3 local_point;
void vertex(){local_point=VERTEX;}
void fragment(){
 vec3 colour=base_colour.rgb;
 if(material_kind==1){
  float grain=sin(local_point.y*210.+sin(local_point.x*13.)*.7)*.012;
  colour*=1.+grain;
 }
 if(material_kind==2){
  float weave=sin(local_point.x*750.)*sin(local_point.z*750.)*.008;
  colour*=1.+weave;
 }
 if(material_kind==3){
  vec3 direction=normalize((INV_VIEW_MATRIX*vec4(reflect(-VIEW,NORMAL),0)).xyz);
  vec2 panorama_uv=vec2(atan(direction.x,-direction.z)*.159154943+.5,acos(clamp(direction.y,-1.,1.))*.318309886);
  panorama_uv=vec2(panorama_uv.x*3.+.46,clamp(.55+(panorama_uv.y-.5)*2.4,0.,1.));
  vec3 reflection=textureLod(reflected_sky,panorama_uv,2.).rgb;
  reflection=mix(reflection,vec3(.16,.23,.31),sky_storm*.85);
  float fresnel=.16+.35*pow(1.-clamp(dot(NORMAL,VIEW),0.,1.),3.);
  colour=mix(colour,vec3(.43,.22,.067),poc_night);
  EMISSION=reflection*fresnel*(1.-poc_night*.7)+vec3(.64,.27,.06)*poc_night*.65;
 }
 ALBEDO=colour;
 ROUGHNESS=material_kind==3?.22:(material_kind==1?.64:.96);
 SPECULAR=material_kind==3?.5:(material_kind==1?.3:.12);
}
