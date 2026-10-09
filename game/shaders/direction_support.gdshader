shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform mat4 part_transform;
varying vec3 p;
void vertex(){p=(part_transform*vec4(VERTEX,1)).xyz;}
void fragment(){
 // Keep the original generated timber post and planting, remove its intersecting old arrows.
 if(p.y>1.28&&(abs(p.x+.174)>.105||abs(p.z+.119)>.12))discard;
 ALBEDO=texture(albedo_tex,UV).rgb;ROUGHNESS=1.;SPECULAR=0.;
}
