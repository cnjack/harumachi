shader_type spatial;
render_mode specular_disabled;
// Independent small-prop shader: stepped light, restrained rim and simple patterns.
uniform vec4 tint:source_color=vec4(.64,.49,.31,1.);
uniform int pattern=0; // 0 flat, 1 quiet wood, 2 picnic checks
uniform int light_steps=3;
varying vec3 local_point;
void vertex(){local_point=VERTEX;}
void fragment(){
 vec3 color=tint.rgb;
 if(pattern==1){
  float grain=sin(local_point.x*32.+sin(local_point.z*4.)*1.4);
  color*=mix(.88,1.04,step(-.30,grain));
 }
 if(pattern==2){
  vec2 grid=floor(local_point.xz*8.);
  float stripe=mod(grid.x,2.)+mod(grid.y,2.);
  color=mix(vec3(.9,.86,.72),tint.rgb,stripe*.36);
 }
 ALBEDO=color;ROUGHNESS=1.;
 float rim=step(.78,1.-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.,1.));
 EMISSION=color*rim*.035;
}
void light(){
 float facing=clamp(dot(NORMAL,LIGHT),0.,1.);
 float bands=light_steps==2?mix(.35,1.,step(.46,facing)):mix(.32,mix(.68,1.,step(.72,facing)),step(.28,facing));
 DIFFUSE_LIGHT+=ALBEDO*LIGHT_COLOR*bands*ATTENUATION/3.14159265;
}
