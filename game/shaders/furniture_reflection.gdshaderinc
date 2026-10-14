#ifndef FURNITURE_REFLECTION_INCLUDED
#define FURNITURE_REFLECTION_INCLUDED

// Dielectric GGX BRDF times NdotL. Shared by painted wood, enamel and glass.
// The renderer supplies LIGHT_COLOR (radiance * PI), attenuation and light specular.
// Indirect rough environment reflections remain on Godot's native non-toon path.
vec3 furniture_ggx(vec3 normal, vec3 view, vec3 light, float roughness, float f0) {
	vec3 n = normalize(normal);
	vec3 v = normalize(view);
	vec3 l = normalize(light);
	float nv = max(dot(n, v), 0.0);
	float nl = max(dot(n, l), 0.0);
	if (nv <= 0.0001 || nl <= 0.0001 || f0 <= 0.0) {
		return vec3(0.0);
	}
	vec3 h = normalize(v + l);
	float nh = max(dot(n, h), 0.0);
	float vh = max(dot(v, h), 0.0);
	float alpha = max(roughness * roughness, 0.0016);
	float alpha_squared = alpha * alpha;
	float denominator = nh * nh * (alpha_squared - 1.0) + 1.0;
	float distribution = alpha_squared / (3.14159265 * denominator * denominator);
	float masking_v = 2.0 * nv / (nv + sqrt(alpha_squared + (1.0 - alpha_squared) * nv * nv));
	float masking_l = 2.0 * nl / (nl + sqrt(alpha_squared + (1.0 - alpha_squared) * nl * nl));
	float fresnel = clamp(f0, 0.0, 1.0) + (1.0 - clamp(f0, 0.0, 1.0)) * pow(1.0 - vh, 5.0);
	// nl cancels the BRDF's 4*nv*nl denominator. No threshold or UV-painted lobe.
	return vec3(fresnel * distribution * masking_v * masking_l / (4.0 * nv));
}

#endif
