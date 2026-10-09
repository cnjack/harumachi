shader_type spatial;
// Stylized blade grass (v0.6). A MultiMesh of blade clumps; UV.y runs 0 at the root to 1 at the tip,
// COLOR.r / COLOR.g are per-blade random values. The blades are lit with the ground's normal so a lawn
// reads as one soft surface, and take their colour from a world-space palette that ground.gdshader
// ("lawn" mode) shares, so the soil between blades and the lawn in the distance match.
render_mode world_vertex_coords, diffuse_lambert, specular_disabled, cull_disabled;

global uniform float wind_strength;
global uniform vec2 wind_direction;
global uniform vec4 grass_push;   // xyz = player position, w = radius the blades bend away within

uniform vec3 root_col : source_color = vec3(0.11, 0.26, 0.13);
uniform vec3 fresh_col : source_color = vec3(0.64, 0.85, 0.28);
uniform vec3 deep_col : source_color = vec3(0.22, 0.49, 0.31);
uniform vec3 dry_col : source_color = vec3(0.84, 0.78, 0.45);
uniform float dry_amount = 0.10;
uniform float brightness = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);

varying float v_h;
varying float v_rand;
varying float v_wave;
varying float v_side;
varying vec3 v_wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 lawn_tip(vec2 p) {
	float n1 = noise(p * 0.045 + 3.1) * 0.65 + noise(p * 0.13 + 9.0) * 0.35;
	float n2 = noise(p * 0.21 + 17.0);
	vec3 tip = mix(deep_col, fresh_col, smoothstep(0.3, 0.7, n1));
	// a few warm, sun-bleached patches
	tip = mix(tip, vec3(0.80, 0.82, 0.42), smoothstep(0.66, 0.9, noise(p * 0.03 + 41.0)) * 0.45);
	return tip * (0.93 + smoothstep(0.55, 0.95, n2) * 0.16);
}

void vertex() {
	float h = UV.y;
	v_h = h;
	v_side = UV.x;
	v_rand = fract(COLOR.r + INSTANCE_CUSTOM.x);
	vec2 wd = normalize(wind_direction);
	// bands of wind travel across the lawn; each blade also flutters on its own
	float band = dot(VERTEX.xz, wd) * 0.21 - TIME * 1.55;
	float gust = sin(band) * 0.5 + 0.5;
	gust *= gust;
	float flutter = sin(TIME * 3.1 + COLOR.g * 6.283 + VERTEX.x * 0.9 + VERTEX.z * 0.6);
	float bend = (0.10 + gust * 0.5 + flutter * 0.06) * wind_strength * h * h;
	vec3 disp = vec3(wd.x, 0.0, wd.y) * bend * 0.3;
	vec3 d = VERTEX - grass_push.xyz;
	d.y = 0.0;
	float dist = length(d);
	float push = (1.0 - smoothstep(grass_push.w * 0.25, grass_push.w, dist)) * h;
	disp += d / max(dist, 0.001) * push * 0.28;
	disp.y -= length(disp.xz) * 0.55;
	VERTEX += disp;
	v_wave = gust * h;
	v_wp = VERTEX;
	NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), NORMAL, 0.12));
}

void fragment() {
	vec3 tip = lawn_tip(v_wp.xz);
	float t = pow(v_h, 0.7);
	vec3 c = mix(root_col, tip, t);
	c *= 0.9 + v_rand * 0.2;
	float dry = step(1.0 - dry_amount, fract(v_rand * 7.13)) * smoothstep(0.45, 1.0, v_h);
	c = mix(c, dry_col, dry * 0.7);
	// one side of each blade a touch darker: a crisp, painted fold
	c *= mix(0.9, 1.04, step(0.5, v_side));
	// the passing wind catches the tips (the silver sheen of a meadow)
	c += vec3(0.09, 0.10, 0.05) * v_wave;
	ALBEDO = c * brightness;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.28, 0.34, 0.12) * v_h;
}
