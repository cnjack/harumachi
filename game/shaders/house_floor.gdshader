shader_type spatial;
// Painted interior floors for the player's house. One shader, four looks (floor_mode):
//   0 wood planks  1 tatami (mat layout + cloth borders computed from world position)
//   2 washed-pebble genkan  3 engawa boards
// Lighting is a soft two-tone ramp: sunlit areas stay warm and flat, shadows get a cool
// lavender fill instead of turning grey, which keeps the anime look.
render_mode specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int floor_mode = 0;
uniform bool painted_planks=false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile = 2.0;                 // metres per texture repeat
uniform vec4 room_rect = vec4(-1.0, -1.0, 1.0, 1.0);   // x0, z0, x1, z1 in house-local metres
uniform vec3 house_origin = vec3(0.0, 0.0, 400.0);
uniform float edge_dark = 0.22;           // painted contact shadow along the walls
uniform vec4 heri_color : source_color = vec4(0.16, 0.2, 0.3, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.6, 0.9, 1.0);
uniform float shadow_fill = 0.16;
uniform float band_soft = 0.22;

varying vec3 lpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	lpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - house_origin;
}

vec3 tatami(vec2 p) {
	// rows of 1.8 x 0.9 m mats running east-west, every other row offset by half a mat
	float row = floor(p.y / 0.9);
	float off = mod(row, 2.0) * 0.9;
	float col = floor((p.x + off) / 1.8);
	vec2 cell = vec2(col, row);
	vec2 f = vec2(fract((p.x + off) / 1.8), fract(p.y / 0.9));
	vec2 uv = vec2(f.x * 1.8 / tile * 1.6, f.y * 0.9 / tile * 1.6) + hash(cell) * 3.1;
	vec3 c = texture(albedo_tex, uv).rgb;
	c *= 0.93 + 0.1 * hash(cell + 3.7);
	// cloth border (heri) along the long edges, thin seam at the short ends
	float hb = 0.045 / 0.9;
	float heri = step(f.y, hb) + step(1.0 - hb, f.y);
	float hp = 0.5 + 0.5 * sin((p.x) * 60.0);
	vec3 hc = heri_color.rgb * (0.85 + 0.25 * hp);
	c = mix(c, hc, clamp(heri, 0.0, 1.0));
	float seam = smoothstep(0.012, 0.0, min(f.x, 1.0 - f.x) * 1.8);
	c *= 1.0 - 0.25 * seam;
	return c;
}

void fragment() {
	vec2 p = lpos.xz;
	vec3 c;
	if (floor_mode == 1) {
		c = tatami(p);
	} else if (floor_mode == 3) {
		c = texture(albedo_tex, p / tile).rgb;
	} else {
		c = texture(albedo_tex, p / tile).rgb;
		vec3 b = texture(albedo_tex, p / (tile * 2.3) + vec2(0.37, 0.61)).rgb;
		c = mix(c, b, 0.18);
	}
	if(painted_planks){
		float row=floor(p.x/.22);float edge=fract(p.x/.22);
		vec3 grain=texture(albedo_tex,vec2(p.x*1.7,p.y/2.4+hash(vec2(row,2.7)))).rgb;
		c=mix(vec3(.45,.29,.16),grain,.68)*(.94+.10*hash(vec2(row,3.1)));
		c*=.87+.13*smoothstep(.006,.018,min(edge,1.-edge));
	}
	// soft painted darkening where the floor meets the walls
	float d = min(min(p.x - room_rect.x, room_rect.z - p.x), min(p.y - room_rect.y, room_rect.w - p.y));
	c *= 1.0 - edge_dark * (1.0 - smoothstep(0.0, 0.45, d));
	ALBEDO = c * tint.rgb;
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
