// Surface-gradient bump in view space; no assumption about imported UV tangents.
vec3 poc_surface_normal(vec3 n, vec3 position_view, float height_m) {
	vec3 dx = dFdx(position_view);
	vec3 dy = dFdy(position_view);
	vec3 rx = cross(dy, n);
	vec3 ry = cross(n, dx);
	float determinant = dot(dx, rx);
	vec3 gradient = (rx * dFdx(height_m) + ry * dFdy(height_m)) * sign(determinant) / max(abs(determinant), .000001);
	return normalize(n - gradient);
}
