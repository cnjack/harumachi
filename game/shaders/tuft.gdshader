shader_type spatial;
// Grass and wildflower tufts (MultiMesh of crossed quads). INSTANCE_CUSTOM: x = atlas cell 0..7,
// y = colour variation, z = sway phase. Tops bend with the shared wind; the base stays planted.
render_mode diffuse_lambert, specular_disabled, cull_disabled, depth_prepass_alpha;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.45;
uniform vec4 tint : source_color = vec4(1.0);
global uniform float wind_strength;
global uniform vec2 wind_direction;

varying float v_var;

void vertex() {
	float cell = floor(INSTANCE_CUSTOM.x + 0.5);
	vec2 cr = vec2(mod(cell, 4.0), floor(cell / 4.0));
	UV = (cr + UV) / vec2(4.0, 2.0);
	v_var = INSTANCE_CUSTOM.y;
	float h = clamp(VERTEX.y, 0.0, 1.0);
	float ph = INSTANCE_CUSTOM.z * 6.283;
	float s = sin(TIME * 1.7 + ph) * 0.7 + sin(TIME * 3.1 + ph * 1.3) * 0.3;
	vec3 world_bend=vec3(wind_direction.x,0.0,wind_direction.y)*s*.08*wind_strength*h*h;
	VERTEX += (inverse(MODEL_MATRIX)*vec4(world_bend,0.0)).xyz;
	// face normals up so the tufts light like the ground they stand on
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 c = texture(atlas, UV);
	if (c.a < alpha_cut) { discard; }
	vec3 col = c.rgb * tint.rgb * mix(vec3(0.86, 0.92, 0.84), vec3(1.08, 1.04, 0.95), v_var);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.25, 0.3, 0.15);
}
