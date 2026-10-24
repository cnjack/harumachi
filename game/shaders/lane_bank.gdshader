shader_type spatial;
// The same meadow colour and lighting continue over the cut. Only restrained
// close-range pigment uses the metre-scale cross-section UVs.
render_mode diffuse_toon, specular_disabled;
#include "res://shaders/meadow_colour.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 2.8;
uniform vec4 lane_bounds = vec4(42.7, -19.0, 132.0, -3.0);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 meadow = meadow_colour(wpos.xz);
	float verge = min(wpos.z - lane_bounds.y, lane_bounds.w - wpos.z);
	float side_blend = smoothstep(0.0, 3.2, verge);
	float start_blend = smoothstep(lane_bounds.x, lane_bounds.x + 3.0, wpos.x);
	float distant_blend = 1.0 - smoothstep(lane_bounds.x + 30.0, lane_bounds.x + 64.0, wpos.x);
	float pixel_detail = 1.0 - smoothstep(.08, .28, length(fwidth(UV)));
	vec3 painted = texture(albedo_tex, UV / tile).rgb;
	float pigment = dot(painted, vec3(.2126, .7152, .0722));
	float strokes = field_noise(vec2(UV.x * 1.6 + UV.y * .4, UV.y * 5.5));
	float mark = (pigment - .5) * .14 + (strokes - .5) * .025;
	ALBEDO = meadow * (1.0 + mark * side_blend * start_blend * distant_blend * pixel_detail);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
