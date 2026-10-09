shader_type spatial;
// Japanese concrete block wall: procedural 0.4 x 0.2 m blocks with mortar lines and a cap band.
render_mode diffuse_toon, specular_disabled;

uniform vec4 block_color : source_color = vec4(0.80, 0.78, 0.72, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.62, 0.61, 0.58, 1.0);
uniform vec4 cap_color : source_color = vec4(0.70, 0.69, 0.66, 1.0);
uniform float wall_top = 1.4;
uniform bool plaster = false;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float u = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
	float v = wpos.y;
	float row = floor(v / 0.2);
	float uu = u / 0.4 + mod(row, 2.0) * 0.5;
	vec2 cell = vec2(floor(uu), row);
	vec2 f = vec2(fract(uu), fract(v / 0.2));
	float m = step(0.035, f.x) * step(f.x, 0.965) * step(0.07, f.y) * step(f.y, 0.93);
	vec3 blk = block_color.rgb * (0.94 + 0.08 * hash(cell));
	vec3 c = mix(mortar_color.rgb, blk, m);
	if (wpos.y > wall_top - 0.08 || wnorm.y > 0.5) { c = cap_color.rgb; }
	if (plaster) {
		// Courtyard lime plaster over a restrained stone footing; street walls remain concrete blocks.
		c = vec3(0.90, 0.87, 0.78) * (0.97 + 0.04 * hash(floor(vec2(u, v) * 4.8)));
		if (v < 0.23) { c = mix(vec3(0.48, 0.50, 0.55), vec3(0.66, 0.67, 0.69), m); }
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}
