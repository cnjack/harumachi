shader_type spatial;
render_mode diffuse_toon,specular_disabled;
uniform sampler2D painted_tex : source_color,filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color=vec4(1);
uniform float water_level=-.28;
varying float world_y;
void vertex(){world_y=(MODEL_MATRIX*vec4(VERTEX,1)).y;}
void fragment(){
 vec3 col=texture(painted_tex,UV).rgb*tint.rgb;
 float wet=1.-smoothstep(water_level-.035,water_level+.025,world_y);
 ALBEDO=col*mix(1.0,.69,wet);ROUGHNESS=1.0;SPECULAR=0.0;
}
