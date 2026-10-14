shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://shaders/furniture_reflection.gdshaderinc"
// Native rough reflections include the real sky/environment even in direct-light shadow.
// Curved bevels and authored surface painting provide the visible material response.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool has_albedo = false;
uniform bool has_emission = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float opacity = 1.0; // Kept for material diagnostics; this shader stays opaque.
uniform int finish_kind = 0; // enamel, brushed steel, brass, coated content painting
uniform float roughness_value = .48;
uniform float gloss_strength = .18;
uniform float wear_strength = .2;
uniform bool oven_surface = false;
uniform mat4 part_transform;
varying vec3 part_position;
varying vec3 part_normal;
varying float reflection_f0;
varying float reflection_roughness;

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
	vec2 authored_uv = UV * uv_scale + uv_offset;
	vec3 colour = base_color.rgb * (has_albedo ? texture(albedo_tex, authored_uv).rgb : vec3(1.0));
	if (has_albedo && finish_kind == 1) {
		// The authored horizontal brushing is real UV colour, kept quiet enough
		// that curved metal reflections, rather than dense fibres, describe steel.
		colour = base_color.rgb * mix(vec3(.42), texture(albedo_tex, authored_uv).rgb, .35);
	}
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
	if (!has_albedo && (finish_kind == 1 || finish_kind == 2)) {
		float wipe = pow(.5 + .5 * sin(part_position.y * 164.0 + part_position.x * .8), 18.0);
		colour *= 1.0 - wipe * wear_strength * .022;
	}
	ALBEDO = colour;
	ROUGHNESS = clamp(roughness_value - use_polish * .035, .3, .8);
	METALLIC = 0.0;
	SPECULAR = clamp(gloss_strength * (finish_kind == 0 ? 1.85 : 2.25), 0.0, .65);
	reflection_f0 = .16 * SPECULAR * SPECULAR;
	reflection_roughness = ROUGHNESS;
	EMISSION = emission_color.rgb * (has_emission ? texture(emission_tex, authored_uv).rgb : vec3(1.0));
}

void light() {
	float facing = max(dot(normalize(NORMAL), normalize(LIGHT)), 0.0);
	float cel = mix(.34, 1.0, smoothstep(.12, .23, facing));
	// Forward+ applies ALBEDO once after accumulating DIFFUSE_LIGHT.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cel / 3.14159265;
	SPECULAR_LIGHT += furniture_ggx(NORMAL, VIEW, LIGHT, reflection_roughness, reflection_f0) * LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT;
}
