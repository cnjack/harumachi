shader_type canvas_item;
uniform vec2 surface_size = vec2(248.0);
uniform float feather_pixels = 5.0;
varying vec2 map_pixel;
void vertex() {
	map_pixel = VERTEX;
}
void fragment() {
	float radius = min(surface_size.x, surface_size.y) * 0.5;
	float distance_from_center = length(map_pixel - surface_size * 0.5);
	COLOR.a *= 1.0 - smoothstep(radius - feather_pixels, radius, distance_from_center);
}
