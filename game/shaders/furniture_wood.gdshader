shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://shaders/furniture_reflection.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(.66, .49, .31, 1.);
uniform vec4 finish_tint : source_color = vec4(1.);
uniform bool has_finish_tint = false;
uniform bool has_original = false;
uniform vec2 uv_scale = vec2(1.);
uniform vec2 uv_offset = vec2(0.);
uniform mat4 wood_transform;
uniform int grain_axis = 0;
uniform float grain_strength = .62;
uniform int use_profile = 1; // counter, home/cafe, workshop, outdoor seat, shelf
uniform int atlas_mode = 0; // pure timber, mixed atlas, dining top, kotatsu frame
uniform bool generated_atlas = false;
uniform bool generated_cloth = false;
uniform bool structural = false;
uniform float wear_strength : hint_range(0., 1.) = .35;
uniform float sheen_strength : hint_range(0., 1.) = .35;
uniform float environment_sheen : hint_range(0., .25) = .22;
uniform float roughness_base = .72;
uniform float roughness_polished = .48;
uniform float reflectance = .36;
uniform float authored_detail_strength = 0.;
uniform vec3 part_min = vec3(-.5);
uniform vec3 part_size = vec3(1.);
uniform int component_count = 0;
uniform vec4 component_min[64];
uniform vec4 component_max[64];
// Project into the actual timber surface: no floating paper or emissive glyph.
uniform bool engraving_enabled = false;
uniform sampler2D engraving_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 engraving_rect = vec4(0., .1, .5, .1);
uniform mat4 engraving_transform;
uniform bool engraving_two_sided = false;
uniform float engraving_strength = .70;
varying vec3 engraving_p;
varying vec3 engraving_n;
varying vec3 root_p;
varying vec3 root_normal;
varying vec3 board_p;
varying vec3 board_normal;
varying vec3 board_min;
varying vec3 board_size;
varying float board_horizontal;
varying float finish_polish;
varying float reflection_f0;
varying float reflection_roughness;

void vertex() {
	engraving_p = (engraving_transform * vec4(VERTEX, 1.)).xyz;
	engraving_n = normalize(mat3(engraving_transform) * NORMAL);
	root_p = (wood_transform * vec4(VERTEX, 1.)).xyz;
	root_normal = normalize(mat3(wood_transform) * NORMAL);
	board_p = VERTEX;
	board_normal = NORMAL;
	board_min = part_min;
	board_size = part_size;
	board_horizontal = 1. - step(max(part_size.x, part_size.z) * .60, part_size.y);
	for (int index = 0; index < 64; index++) {
		if (index >= component_count) { break; }
		if (all(greaterThanEqual(VERTEX, component_min[index].xyz - vec3(.00003))) && all(lessThanEqual(VERTEX, component_max[index].xyz + vec3(.00003)))) {
			board_min = component_min[index].xyz;
			board_size = component_max[index].xyz - component_min[index].xyz;
			board_horizontal = component_max[index].w;
			break;
		}
	}
}

void fragment() {
	NORMAL_MAP = vec3(.5, .5, 1.);
	NORMAL_MAP_DEPTH = 0.;
	vec3 extent = max(board_size, vec3(.001));
	vec3 q = clamp((board_p - board_min) / extent, vec3(0.), vec3(1.));
	float along = grain_axis == 1 ? root_p.y : (grain_axis == 2 ? root_p.z : root_p.x);
	float across = grain_axis == 1 ? (abs(root_normal.x) > .5 ? root_p.z : root_p.x) : (grain_axis == 2 ? (abs(root_normal.y) > .5 ? root_p.x : root_p.y) : (abs(root_normal.y) > .5 ? root_p.z : root_p.y));
	vec2 grain_uv = vec2(across * 2.2, along * .75);
	float grain = dot(texture(grain_tex, grain_uv).rgb, vec3(.2126, .7152, .0722));
	vec3 original = has_original ? texture(albedo_tex, UV * uv_scale + uv_offset).rgb * base_color.rgb : base_color.rgb * (.94 + grain * .14);
	float timber = 1.;
	if (atlas_mode > 0) {
		// Neutral paper, pale canvas, blue/grey glazing and black hardware stay original.
		timber = smoothstep(1.08, 1.24, original.r / max(original.g, .005)) * smoothstep(1.04, 1.22, original.g / max(original.b, .005));
		timber *= 1. - smoothstep(.66, .82, min(original.r, min(original.g, original.b)));
	}
	if (atlas_mode == 2) {
		bool top = root_normal.y > .7 && root_p.y > .66 && root_p.y < .82 && abs(root_p.x) < .54 && abs(root_p.z) < .36;
		timber *= top ? 1. : 0.;
	}
	if (atlas_mode == 3) {
		bool linen = root_p.y < .41 && root_p.y > .05 && (abs(root_p.x) > .48 || abs(root_p.z) > .46);
		float fold = dot(original, vec3(.2126, .7152, .0722));
		original = linen ? mix(vec3(.49, .65, .58), vec3(.84, .88, .75), clamp(fold * 1.25, .2, .9)) : original;
		bool frame = root_p.y > .38 || (root_p.y < .12 && abs(root_normal.y) < .7);
		timber *= frame && !linen ? 1. : 0.;
	}
	if (has_finish_tint) {
		float authored_fibre = has_original ? dot(texture(albedo_tex, UV * uv_scale + uv_offset).rgb, vec3(.2126, .7152, .0722)) : grain;
		// Keep the existing fine fibres and the approved furniture's real UV image.
		// The source-image contrast remains visible beneath the lacquer reflection.
		float fibre_contrast = 1. + (grain - .4) * grain_strength;
		if (has_original) {
			float image_detail = clamp(1. + (authored_fibre - .65) * authored_detail_strength, .72, 1.15);
			fibre_contrast = authored_detail_strength > 0. ? image_detail : (fibre_contrast * (.96 + .08 * authored_fibre));
		}
		vec3 art_wood = finish_tint.rgb * fibre_contrast;
		original = mix(original, art_wood, timber);
	}
	float top_face = smoothstep(.65, .92, board_normal.y);
	float horizontal_board = board_horizontal;
	float edge_x = min(q.x, 1. - q.x) * extent.x;
	float edge_z = min(q.z, 1. - q.z) * extent.z;
	float perimeter = 1. - smoothstep(.006, .034, min(edge_x, edge_z));
	float front_lip = 1. - smoothstep(.012, .10, (1. - q.z) * extent.z);
	vec2 patch_q = (q.xz - vec2(.56, .65)) / vec2(.37, .30);
	float touch = 1. - smoothstep(.48, 1., length(patch_q));
	if (use_profile == 3) {
		patch_q = (q.xz - vec2(.50, .52)) / vec2(.42, .44);
		touch = 1. - smoothstep(.45, 1., length(patch_q));
	}
	if (use_profile == 4) { touch *= .18; }
	// A fused atlas can include the entire cabinet. Its upward wood faces still
	// receive wear even though the component as a whole is taller than its shelves.
	float used_top = top_face * (atlas_mode > 0 ? 1. : horizontal_board);
	float polished = used_top * clamp(.16 + front_lip * .62 + touch * .43, 0., 1.);
	float front_corners = (1. - smoothstep(.08, .28, min(q.x, 1. - q.x))) * (1. - smoothstep(.07, .28, 1. - q.z));
	float rubbed = used_top * (perimeter * (.18 + front_corners * .58) + front_lip * touch * .24 + touch * .10);
	// These are 15–22cm shallow marks on the exposed front work area. Millimetre
	// widths survive a normal720p view; the centre remains available for tools.
	vec2 work_a = board_p.xz - (board_min.xz + extent.xz * vec2(.25, .80));
	vec2 work_b = board_p.xz - (board_min.xz + extent.xz * vec2(.73, .76));
	vec2 work_c = board_p.xz - (board_min.xz + extent.xz * vec2(.68, .87));
	float scratch_a = (1. - smoothstep(.0018, .0040, abs(work_a.y + work_a.x * .24))) * (1. - smoothstep(.08, .11, abs(work_a.x)));
	float scratch_b = (1. - smoothstep(.0015, .0034, abs(work_b.y - work_b.x * .17))) * (1. - smoothstep(.055, .085, abs(work_b.x)));
	float scratch_c = (1. - smoothstep(.0013, .0031, abs(work_c.y + work_c.x * .29))) * (1. - smoothstep(.05, .075, abs(work_c.x)));
	float scratch = clamp(scratch_a + scratch_b + scratch_c, 0., 1.);
	float marks = use_profile == 2 ? scratch * used_top * .25 : 0.;
	if (use_profile == 0 || use_profile == 1) {
		vec2 cup_p = board_p.xz - (board_min.xz + extent.xz * vec2(.29, .62));
		float ring = 1. - smoothstep(.001, .0035, abs(length(cup_p) - .042));
		marks = ring * used_top * .045;
	}
	if (structural) { polished = 0.; rubbed *= .35; marks = 0.; }
	vec3 colour = original;
	if (use_profile == 2 && !structural) {
		float luminance = dot(original, vec3(.2126, .7152, .0722));
		vec3 quieter = mix(original, vec3(luminance), .10);
		colour = mix(original, quieter, timber * used_top * wear_strength);
	}
	// Rubbed fibres are a warm, slightly lighter version of the same wood. Only
	// the front corners/contact patches change; untouched grain stays authored.
	vec3 dry_fibre = colour * vec3(1.24, 1.27, 1.25) + vec3(.026, .022, .014);
	colour = mix(colour, dry_fibre, timber * wear_strength * rubbed);
	colour *= 1. - timber * wear_strength * marks;
	if (use_profile == 2 && !structural) {
		float scratch_lip = (1. - smoothstep(.001, .003, abs(work_a.y + work_a.x * .24 - .004))) * (1. - smoothstep(.08, .11, abs(work_a.x)));
		colour += timber * wear_strength * used_top * scratch_lip * vec3(.035, .029, .018);
	}
	if (use_profile == 3) { colour *= 1. + timber * used_top * wear_strength * .022; }
	if (engraving_enabled && (engraving_n.z > .45 || (engraving_two_sided && engraving_n.z < -.45))) {
		vec2 ink_uv = (engraving_p.xy - engraving_rect.xy) / engraving_rect.zw + vec2(.5);
		ink_uv.y = 1. - ink_uv.y;
		if (engraving_n.z < 0.) { ink_uv.x = 1. - ink_uv.x; }
		if (all(greaterThanEqual(ink_uv, vec2(0.))) && all(lessThanEqual(ink_uv, vec2(1.)))) {
			vec2 pixel = 1. / vec2(textureSize(engraving_mask, 0));
			float cut = texture(engraving_mask, ink_uv).r;
			float lip = texture(engraving_mask, ink_uv + pixel * vec2(-1.2, -1.2)).r - texture(engraving_mask, ink_uv + pixel * vec2(1.2, 1.2)).r;
			// Dark recessed fibres with an asymmetric bevel lip, lit by the same
			// sun/room light as the underlying original atlas. Never a bright label.
			colour *= 1. - cut * engraving_strength;
			colour += lip * vec3(.13, .095, .055) * engraving_strength;
			vec2 slope = vec2(texture(engraving_mask, ink_uv + vec2(pixel.x, 0.)).r - texture(engraving_mask, ink_uv - vec2(pixel.x, 0.)).r, texture(engraving_mask, ink_uv + vec2(0., pixel.y)).r - texture(engraving_mask, ink_uv - vec2(0., pixel.y)).r);
			NORMAL_MAP = normalize(vec3(-slope * .42, 1.)) * .5 + .5;
			NORMAL_MAP_DEPTH = engraving_strength;
		}
	}
	ALBEDO = colour;
	finish_polish = timber * polished;
	ROUGHNESS = structural ? .92 : mix(roughness_base, roughness_polished, finish_polish);
	// Native rough reflection follows the actual curved normals and environment.
	// The sheen control also drives the gloss-off diagnostic capture.
	SPECULAR = structural ? .08 : reflectance * clamp(sheen_strength / .35, 0., 1.2) * clamp(environment_sheen / .22, 0., 1.2) * (.65 + .35 * finish_polish);
	if (generated_atlas) {
		float paint = smoothstep(1.03, 1.16, original.g / max(original.r, .005));
		float original_reflectance = SPECULAR;
		ROUGHNESS = mix(mix(.91, .58, paint), ROUGHNESS, timber);
		SPECULAR = mix(mix(.09, .25, paint), original_reflectance, timber);
		if (generated_cloth) {
			ROUGHNESS = mix(.94, ROUGHNESS, timber);
			SPECULAR = mix(.07, SPECULAR, timber);
		}
	}
	reflection_f0 = .16 * SPECULAR * SPECULAR;
	reflection_roughness = ROUGHNESS;
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.);
	float cel = mix(.34, 1., smoothstep(.08, .16, facing));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cel / 3.14159265;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * furniture_ggx(NORMAL, VIEW, LIGHT, reflection_roughness, reflection_f0);
}
