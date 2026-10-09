shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform mat4 part_transform;
varying vec3 p;
varying vec3 n;
void vertex(){p=(part_transform*vec4(VERTEX,1)).xyz;n=normalize(mat3(part_transform)*NORMAL);}
void fragment(){
 vec3 colour=texture(albedo_tex,UV).rgb;
 // The original frame stays visible. Repaint only the measured front blackboard.
 if(abs(p.x)<.273&&p.y>.195&&p.y<.923&&p.z>.02){
  float dust=.0015*sin(p.x*23.+p.y*7.)*sin(p.y*19.);
  colour=vec3(.048,.085,.077)+dust;
 }
 ALBEDO=colour;ROUGHNESS=1.;SPECULAR=0.;
}
