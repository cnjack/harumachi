shader_type spatial;
render_mode diffuse_toon,specular_disabled,cull_disabled;
uniform sampler2D weave_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 tint:source_color=vec4(1);
void fragment(){
 ALBEDO=texture(weave_tex,UV*3.).rgb*tint.rgb;
 ROUGHNESS=1.;if(!FRONT_FACING)NORMAL=-NORMAL;
}
