shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D view_tex:source_color,filter_linear_mipmap_anisotropic;
uniform float daylight=1.;
void fragment(){
 vec3 c=texture(view_tex,UV).rgb;
 ALBEDO=mix(c*vec3(.065,.10,.20),c*.82,daylight);
}
