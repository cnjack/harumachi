shader_type spatial;
render_mode diffuse_toon,specular_disabled;
uniform sampler2D painted_tex : source_color,filter_linear_mipmap_anisotropic,repeat_disable;
varying vec3 local_pos;
varying float front_face;
void vertex(){local_pos=VERTEX;front_face=abs(NORMAL.z);}
void fragment(){
 vec2 uv=vec2(local_pos.x/1.12+.5,.5-local_pos.y/.55);
 vec3 face=texture(painted_tex,uv).rgb;
 ALBEDO=mix(vec3(.32,.22,.12),face,front_face);
 ROUGHNESS=1.;SPECULAR=0.;
}
