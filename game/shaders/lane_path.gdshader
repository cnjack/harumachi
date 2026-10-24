shader_type spatial;
// The gravel remains opaque geometry, becoming a faint grassy track at its end.
render_mode diffuse_toon, specular_disabled;
#include "res://shaders/meadow_colour.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wear_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(.95, .9, .82, 1.0);
uniform float tile = 2.4;
uniform float macro_strength = .10;
uniform float surface_wear = .28;
uniform vec4 lane_bounds = vec4(42.7, -19.0, 132.0, -3.0);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 gravel = texture(albedo_tex, p / tile).rgb;
	gravel *= 1.0 + (field_noise(p * .025 + 7.0) - .5) * macro_strength * 2.0;
	float scuff = smoothstep(.43, .70, field_noise(p * .45 + 23.0));
	gravel = mix(gravel, texture(wear_tex, p / 3.7).rgb, surface_wear * scuff);
	gravel *= 1.0 + (field_noise(p * .18 + 9.0) - .5) * surface_wear * .45;
	float end_variation = (field_noise(p * .30) - .5) * 4.0;
	float track = 1.0 - smoothstep(lane_bounds.z - 40.0, lane_bounds.z - 4.0, wpos.x + end_variation);
	// UV2 carries the actual half-width and signed distance from the road centre.
	float edge_distance = UV2.x - abs(UV2.y);
	float ragged_edge = smoothstep(.01, .14 + field_noise(p * 2.3) * .10, edge_distance);
	float grass_verge = smoothstep(lane_bounds.x + 30.0, lane_bounds.x + 64.0, wpos.x);
	track *= mix(1.0, ragged_edge, grass_verge);
	ALBEDO = mix(meadow_colour(p), gravel * tint.rgb, track);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
