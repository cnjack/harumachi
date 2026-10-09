shader_type spatial;
render_mode blend_mix,depth_prepass_alpha,cull_disabled,diffuse_toon,specular_disabled;
uniform vec4 glass_tint : source_color=vec4(.52,.80,.85,1);
void fragment() {
	float fresnel=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
	ALBEDO=glass_tint.rgb;EMISSION=glass_tint.rgb*.10;ALPHA=.11+fresnel*.11;ROUGHNESS=.75;
}
