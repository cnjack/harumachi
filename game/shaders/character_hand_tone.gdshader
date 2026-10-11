shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D diffuse : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 skin_color : source_color = vec3(0.90, 0.79, 0.66);
uniform float roughness_value = 0.95;
uniform float specular_value = 0.5;
uniform float metallic_value = 0.0;
uniform vec4 albedo_factor : source_color = vec4(1.0);
uniform float hand_bind_mask[128];
varying float hand_weight;

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex() {
	hand_weight = dot(BONE_WEIGHTS, vec4(hand_bind_mask[int(BONE_INDICES.x)], hand_bind_mask[int(BONE_INDICES.y)], hand_bind_mask[int(BONE_INDICES.z)], hand_bind_mask[int(BONE_INDICES.w)]));
}
void fragment() {
	vec3 original = texture(diffuse, UV).rgb * albedo_factor.rgb;
	vec3 painted = to_srgb(original);
	float peak = max(painted.r, max(painted.g, painted.b));
	float trough = min(painted.r, min(painted.g, painted.b));
	float saturation = (peak - trough) / max(peak, 0.001);
	float orange = smoothstep(0.42, 0.65, saturation) * smoothstep(0.06, 0.15, painted.r - painted.g);
	float amount = smoothstep(0.20, 0.80, hand_weight) * orange;
	vec3 palette = to_srgb(skin_color);
	vec3 corrected = palette * peak / max(max(palette.r, palette.g), max(palette.b, 0.001));
	ALBEDO = mix(original, to_linear(clamp(corrected, vec3(0.0), vec3(1.0))), amount);
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
}
