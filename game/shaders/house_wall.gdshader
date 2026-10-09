shader_type spatial;
// Painted interior walls. Everything is placed in world space so cut-away walls never stretch:
//   plaster (or tile) with a hand-painted mottle, a wooden wainscot (koshi-ita) of vertical boards
//   with a dark rail, a dark skirting board, a nageshi rail at door-head height and a cornice
//   under the ceiling line. The top face of the wall is a dark wood cap. Lighting is the same
//   two-tone ramp as the floors: warm flat light, lavender shade.
render_mode specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile = 1.6;
uniform vec4 cap_color : source_color = vec4(0.36, 0.24, 0.16, 1.0);
uniform vec4 top_warm : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float foot_dark = 0.2;
uniform float floor_y = 0.0;
uniform float wainscot_h = 0.0;          // 0 = plain wall
uniform vec4 wain_tint : source_color = vec4(0.78, 0.6, 0.44, 1.0);
uniform vec4 trim_color : source_color = vec4(0.33, 0.22, 0.15, 1.0);
uniform float skirting_h = 0.07;
uniform float nageshi_y = 0.0;           // 0 = no nageshi rail
uniform float cornice_y = 2.34;
uniform float mottle = 0.07;
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.6, 0.9, 1.0);
uniform float shadow_fill = 0.16;
uniform float band_soft = 0.22;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// a flat painted band with a thin light edge on top and a soft dark line under it
vec3 trim(vec3 c, float h, float y0, float y1, vec3 col) {
	float inside = step(y0, h) * step(h, y1);
	vec3 t = col * (0.9 + 0.2 * smoothstep(y0, y1, h));
	t = mix(t, col * 1.45, smoothstep(y1 - 0.012, y1, h) * inside);
	c = mix(c, t, inside);
	c *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.03, y0 - h)) * step(h, y0);
	return c;
}

void fragment() {
	if (wnorm.y > 0.5) {
		ALBEDO = cap_color.rgb;
	} else {
		float u = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
		float h = wpos.y - floor_y;
		vec3 c = texture(albedo_tex, vec2(u, -wpos.y) / tile).rgb;
		c *= 1.0 + (noise(vec2(u, wpos.y) * 2.3) - 0.5) * mottle * 2.0;
		c *= 1.0 - foot_dark * (1.0 - smoothstep(0.0, 0.7, h));
		c = mix(c, c * top_warm.rgb, smoothstep(1.2, 2.4, h));
		c *= tint.rgb;
		if (wainscot_h > 0.0 && h < wainscot_h) {
			// vertical boards: the floor texture's planks already run vertically
			vec3 w = texture(wood_tex, vec2(u / 1.3, -h / 1.3)).rgb * wain_tint.rgb * 1.25;
			float seam = smoothstep(0.012, 0.0, abs(fract(u / 0.18) - 0.5) - 0.48);
			w *= 1.0 - 0.22 * seam;
			w *= 0.86 + 0.14 * smoothstep(0.0, wainscot_h, h);
			c = w;
		}
		if (wainscot_h > 0.0) {
			c = trim(c, h, wainscot_h - 0.045, wainscot_h + 0.01, trim_color.rgb * 1.2);
		}
		c = trim(c, h, -1.0, skirting_h, trim_color.rgb);
		if (nageshi_y > 0.0) {
			c = trim(c, h, nageshi_y, nageshi_y + 0.08, trim_color.rgb * 1.1);
		}
		c = trim(c, h, cornice_y, 9.0, trim_color.rgb);
		ALBEDO = c;
	}
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 col = LIGHT_COLOR / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		float band = smoothstep(0.5 - band_soft, 0.5 + band_soft, ndl * ATTENUATION * 1.6);
		DIFFUSE_LIGHT += col * (band + shadow_tint.rgb * shadow_fill * (1.0 - band));
	} else {
		float a = ndl * ATTENUATION;
		float band = smoothstep(0.01, 0.12, a) * 0.45 + smoothstep(0.22, 0.42, a) * 0.55;
		DIFFUSE_LIGHT += col * band;
	}
}
