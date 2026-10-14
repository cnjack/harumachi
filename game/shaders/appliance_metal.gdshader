shader_type spatial;
render_mode diffuse_toon;
// Broad painted enamel and a narrower restrained steel lobe, both from actual lights.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool has_albedo = false;
uniform bool has_emission = false;
uniform float opacity = 1.0; // Kept for material diagnostics; this shader stays opaque.
uniform int finish_kind = 0; // enamel, brushed steel, brass, coated content painting
uniform float roughness_value = .48;
uniform float gloss_strength = .18;
uniform float wear_strength = .2;
uniform bool oven_surface = false;
uniform mat4 part_transform;
varying vec3 part_position;
varying vec3 part_normal;
varying float polish;

void vertex() {
	part_position = (part_transform * vec4(VERTEX, 1.0)).xyz;
	part_normal = normalize(mat3(part_transform) * NORMAL);
}

float window_rim(vec2 point, float level) {
	vec2 border = abs(point - vec2(-.115, level - .037)) - vec2(.40, .104);
	float distance_to_edge = max(border.x, border.y);
	// The black gasket covers the first 13mm outside the aperture. Place the
	// maintained warm lip on the visible enamel beyond it, not under the pane.
	float visible_lip = smoothstep(.011, .020, distance_to_edge) * (1.0 - smoothstep(.025, .090, distance_to_edge));
	float lower_lip = 1.0 - smoothstep(-.10, .10, point.y - (level - .037));
	return visible_lip * (.70 + .30 * lower_lip);
}

float dial_touch(vec2 point, float level) {
	float radius = length(point - vec2(.585, level));
	float arc = smoothstep(.034, .046, radius) * (1.0 - smoothstep(.068, .090, radius));
	// Fingers sweep beside the knobs; the printed ticks retain their separate material.
	return arc * smoothstep(-.025, .035, point.x - .585);
}

void fragment() {
	vec3 colour = base_color.rgb * (has_albedo ? texture(albedo_tex, UV).rgb : vec3(1.0));
	float use_polish = 0.0;
	if (oven_surface) {
		float front = smoothstep(.62, .94, part_normal.z) * smoothstep(.40, .43, part_position.z);
		float heat = max(window_rim(part_position.xy, .905), window_rim(part_position.xy, 1.465));
		float touch = max(max(dial_touch(part_position.xy, .976), dial_touch(part_position.xy, .793)), max(dial_touch(part_position.xy, 1.536), dial_touch(part_position.xy, 1.353)));
		// Local warm enamel at the chamber lips and gently wiped control arcs.
		colour *= mix(vec3(1.0), vec3(.94, .82, .64), heat * front * wear_strength * .80);
		colour = mix(colour, min(colour * 1.20 + vec3(.045, .040, .032), vec3(1.0)), touch * front * wear_strength * .95);
		use_polish = touch * front;
	}
	// Sparse long wiping marks belong to metal, never to every face of the appliance.
	if (finish_kind == 1 || finish_kind == 2) {
		float wipe = pow(.5 + .5 * sin(part_position.y * 164.0 + part_position.x * .8), 18.0);
		colour *= 1.0 - wipe * wear_strength * .022;
	}
	ALBEDO = colour;
	ROUGHNESS = clamp(roughness_value - use_polish * .035, .3, .8);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = emission_color.rgb * (has_emission ? texture(emission_tex, UV).rgb : vec3(1.0));
	polish = use_polish;
}

void light() {
	float n_dot_l = max(dot(normalize(NORMAL), normalize(LIGHT)), 0.0);
	float ramp = mix(.34, 1.0, smoothstep(.12, .23, n_dot_l));
	// Forward+ multiplies accumulated diffuse light by ALBEDO after light().
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ramp / 3.14159265;
	vec3 half_direction = normalize(normalize(LIGHT) + normalize(VIEW));
	float facing = max(dot(normalize(NORMAL), half_direction), 0.0);
	float exponent = finish_kind == 0 ? 18.0 : (finish_kind == 3 ? 32.0 : 70.0);
	float lobe = pow(facing, exponent);
	// A wide low shoulder with a soft-edged, bounded core reads as painted gloss.
	float band = .35 * lobe + .65 * smoothstep(.34, .64, lobe);
	vec3 tint = finish_kind == 2 ? vec3(1.0, .90, .68) : vec3(.92, .97, 1.0);
	SPECULAR_LIGHT += tint * LIGHT_COLOR * ATTENUATION * band * gloss_strength * (1.0 + polish * .12) * smoothstep(.02, .22, n_dot_l);
}
