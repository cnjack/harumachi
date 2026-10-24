shader_type spatial;
render_mode blend_mix,depth_prepass_alpha,cull_disabled,diffuse_toon,specular_toon;
uniform vec4 glass_tint : source_color=vec4(.53,.76,.80,1);
void fragment() {
	vec3 n=normalize(NORMAL);
	vec3 v=normalize(VIEW);
	float fresnel=pow(1.0-clamp(abs(dot(n,v)),0.0,1.0),3.0);
	vec3 reflected_world=normalize((INV_VIEW_MATRIX*vec4(reflect(-v,n),0.0)).xyz);
	float sky=smoothstep(-.06,.48,reflected_world.y);
	float sky_band=smoothstep(.18,.30,reflected_world.y)*(1.0-smoothstep(.48,.62,reflected_world.y));
	// A broad sky reflection follows the viewing direction. It receives scene
	// lighting like the tint, so the windows do not emit a white panel at night.
	vec3 sky_colour=mix(vec3(.52,.66,.76),vec3(.77,.86,.90),sky);
	ALBEDO=mix(glass_tint.rgb,sky_colour,.20+sky_band*.23);
	ALPHA=.075+fresnel*.13+sky_band*.024;
	ROUGHNESS=.24;
	SPECULAR=.32;
	METALLIC=0.0;
}
