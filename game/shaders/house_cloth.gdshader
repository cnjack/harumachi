shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool textured = true;
uniform float amplitude = 0.027;
uniform bool physical_anchor = false;
uniform float cloth_top = 1.0;
uniform float cloth_height = 1.0;
global uniform float wind_strength;

void vertex() {
	// Blender-to-glTF V conversion: sewn top is one, free lower edge is zero.
	float free_edge = 1.0 - UV.y;
	if (physical_anchor) free_edge = clamp((cloth_top - VERTEX.y) / cloth_height, 0.0, 1.0);
	float weight = free_edge * free_edge;
	float phase = NODE_POSITION_WORLD.x * 0.31 + NODE_POSITION_WORLD.z * 0.23;
	float breeze = sin(TIME * 1.30 + phase + VERTEX.x * 1.4);
	VERTEX.z += breeze * amplitude * wind_strength * weight;
	VERTEX.x += sin(TIME * 0.83 + phase) * amplitude * 0.28 * weight;
}

void fragment() {
	vec4 colour = albedo_color;
	if (textured) colour *= texture(albedo_tex, UV);
	ALBEDO = colour.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
