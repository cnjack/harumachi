shader_type spatial;
// Dry painted ground: world-space UVs (seamless across meshes), two-scale sampling and
// low-frequency tint noise to hide tiling. No specular, so the street always reads dry.
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/lakeside_shape.gdshaderinc"
uniform bool landscape_contours=false;
uniform vec3 terrain_origin=vec3(700,0,0);

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile = 3.0;
uniform bool structured_texture = false;
uniform float macro_strength = 0.10;
uniform float surface_wear = 0.0;
uniform sampler2D wear_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform float wet = 0.0; // only used by the planter soil, never by streets
// v0.5 meadows: two more grass paintings mixed in by large-scale noise, plus bare dirt patches
uniform bool use_variety = false;
uniform sampler2D meadow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float dirt_amount = 0.12;
// v0.6 lawns: no photo texture; the same world-space palette as grass_blade.gdshader so the soil
// between the blades and the lawn beyond the blades' draw distance match the grass
uniform bool lawn_mode = false;
uniform vec3 root_col : source_color = vec3(0.11, 0.26, 0.13);
uniform vec3 fresh_col : source_color = vec3(0.64, 0.85, 0.28);
uniform vec3 deep_col : source_color = vec3(0.22, 0.49, 0.31);
uniform float lawn_mix = 0.4;
// ragged edges: within `feather` metres of the plane's border, pixels drop out by noise
uniform float feather = 0.0;
instance uniform vec2 plane_size = vec2(0.0);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

vec3 lawn_tip(vec2 p) {
	float n1 = noise(p * 0.045 + 3.1) * 0.65 + noise(p * 0.13 + 9.0) * 0.35;
	float n2 = noise(p * 0.21 + 17.0);
	vec3 tip = mix(deep_col, fresh_col, smoothstep(0.3, 0.7, n1));
	// a few warm, sun-bleached patches
	tip = mix(tip, vec3(0.80, 0.82, 0.42), smoothstep(0.66, 0.9, noise(p * 0.03 + 41.0)) * 0.45);
	return tip * (0.93 + smoothstep(0.55, 0.95, n2) * 0.16);
}

void fragment() {
	if (feather > 0.0 && plane_size.x > 0.0) {
		vec2 e = min(UV, 1.0 - UV) * plane_size;
		float d = min(e.x, e.y);
		float n = noise(wpos.xz * 2.3) * 0.6 + noise(wpos.xz * 7.0 + 3.0) * 0.4;
		if (d < feather * n) { discard; }
	}
	if (lawn_mode) {
		vec3 lc = mix(root_col, lawn_tip(wpos.xz), lawn_mix);
		// soft painted strokes instead of a photographed texture
		float s1 = noise(vec2(wpos.x * 1.6 + wpos.z * 0.4, wpos.z * 5.5));
		float s2 = noise(wpos.xz * 0.6 + 11.0);
		lc *= 0.9 + s1 * 0.12 + (s2 - 0.5) * 0.08;
		vec3 painted = texture(albedo_tex, wpos.xz / tile).rgb;
		ALBEDO = mix(lc, painted * vec3(0.74, 0.83, 0.70), 0.52) * tint.rgb;
	} else {
	vec2 uv = wpos.xz / tile;
	vec3 a = texture(albedo_tex, uv).rgb;
	vec3 b = texture(albedo_tex, uv * 0.43 + vec2(0.31, 0.17)).rgb;
	float n = noise(wpos.xz * 0.07);
	vec3 c = structured_texture ? a : mix(a, b, smoothstep(0.3, 0.7, n) * 0.45);
	if (use_variety) {
		vec3 m = texture(meadow_tex, wpos.xz / (tile * 1.3) + vec2(0.13, 0.41)).rgb;
		vec3 dk = texture(dark_tex, wpos.xz / (tile * 1.1) + vec2(0.57, 0.23)).rgb;
		float n1 = noise(wpos.xz * 0.045 + 3.1) * 0.65 + noise(wpos.xz * 0.13 + 9.0) * 0.35;
		float n2 = noise(wpos.xz * 0.06 + 17.0) * 0.7 + noise(wpos.xz * 0.21) * 0.3;
		c = mix(c, m, smoothstep(0.42, 0.62, n1) * 0.85);
		c = mix(c, dk * 1.08, smoothstep(0.55, 0.75, n2) * 0.7);
		float nd = noise(wpos.xz * 0.09 + 31.0) * 0.6 + noise(wpos.xz * 0.35 + 5.0) * 0.4;
		vec3 dt = texture(dirt_tex, wpos.xz / (tile * 1.2)).rgb;
		c = mix(c, dt, smoothstep(1.0 - dirt_amount, 1.0 - dirt_amount * 0.4, nd) * 0.85);
	}
	c *= 1.0 + (noise(wpos.xz * 0.025 + 7.0) - 0.5) * macro_strength * 2.0;
	if(surface_wear>0.0){
		float scuff=smoothstep(.43,.70,noise(wpos.xz*.45+23.));
		vec3 grain=texture(wear_tex,wpos.xz/3.7).rgb;
		c=mix(c,grain,surface_wear*scuff);
		c*=1.0+(noise(wpos.xz*.18+9.)-.5)*surface_wear*.45;
	}
	c = mix(c, c * 0.55, wet);
	ALBEDO = c * tint.rgb;
	}
	ROUGHNESS = 1.0;
	if(landscape_contours){
		float shore=water_distance(wpos.xz-terrain_origin.xz);
		vec3 bed=mix(vec3(.34,.31,.23),vec3(.49,.45,.33),floor(noise(wpos.xz*3.7)*3.)/3.);
		ALBEDO=mix(ALBEDO,bed,1.0-smoothstep(-.35,.7,shore));
	}
	SPECULAR = 0.0;
}
