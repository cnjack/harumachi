shader_type spatial;
// v0.7.3 shop windows: "interior mapping". The quad sits on a shop's painted glass; each pixel casts
// the view ray into an imaginary room behind it (back wall, side walls, floor, ceiling) plus one
// cut-out layer of display furniture, so the inside shifts with the camera like a real room.
// Quad-local frame: x right, y up, origin at the rectangle's bottom-left, z out to the street.

uniform sampler2D back_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D mid_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 size = vec2(4.0, 2.0);          // the window rectangle (m)
uniform float depth = 2.4;                   // how deep the room is
uniform float floor_y = -0.3;                // room floor / ceiling, relative to the rectangle's bottom
uniform float ceil_y = 2.6;
uniform float side = 0.6;                    // room walls this far beyond the rectangle's sides
uniform float back_aspect = 1.5;
uniform float mid_d = 0.9;                   // furniture layer: distance behind the glass, height
uniform float mid_h = 1.3;
uniform float mid_aspect = 1.5;
uniform float mid_shift = 0.0;
uniform vec3 wall_col : source_color = vec3(0.93, 0.88, 0.8);
uniform vec3 wainscot_col : source_color = vec3(0.55, 0.38, 0.26);
uniform vec3 ceil_col : source_color = vec3(0.86, 0.82, 0.76);
uniform float lamp = 0.35;                   // interior light (0.3 by day, ~1 at night), set by WorldBuilder
uniform vec3 lamp_col : source_color = vec3(1.0, 0.86, 0.68);
uniform vec3 sky_col : source_color = vec3(0.72, 0.82, 0.94);

varying vec3 lp;
varying vec3 cam_l;

void vertex() {
	lp = VERTEX;
	cam_l = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

vec3 back_wall(vec3 p) {
	float rw = size.x + 2.0 * side;
	float rh = ceil_y - floor_y;
	float w = rw;
	float h = rw / back_aspect;
	if (h < rh) {
		h = rh;
		w = rh * back_aspect;
	}
	vec2 uv = vec2((p.x - size.x * 0.5) / w + 0.5, 1.0 - (p.y - floor_y) / h);
	if (uv.y < 0.0) {
		return ceil_col * 0.8;
	}
	return texture(back_tex, clamp(uv, vec2(0.002), vec2(0.998))).rgb;
}

void fragment() {
	vec3 ro = lp;
	vec3 rd = normalize(lp - cam_l);
	if (rd.z > -0.02) {
		rd.z = -0.02;
		rd = normalize(rd);
	}
	float x0 = -side;
	float x1 = size.x + side;
	float t = (-depth - ro.z) / rd.z;
	int hit = 0;
	float ts = 1e9;
	if (rd.x > 1e-5) { ts = (x1 - ro.x) / rd.x; } else if (rd.x < -1e-5) { ts = (x0 - ro.x) / rd.x; }
	if (ts > 0.0 && ts < t) { t = ts; hit = 1; }
	float tv = 1e9;
	if (rd.y < -1e-5) { tv = (floor_y - ro.y) / rd.y; } else if (rd.y > 1e-5) { tv = (ceil_y - ro.y) / rd.y; }
	if (tv > 0.0 && tv < t) { t = tv; hit = rd.y < 0.0 ? 2 : 3; }
	vec3 p = ro + rd * t;
	float dz = clamp(-p.z / depth, 0.0, 1.0);
	vec3 col;
	if (hit == 0) {
		col = back_wall(p);
	} else if (hit == 1) {
		float wy = p.y - floor_y;
		col = wy < 0.9 ? wainscot_col : wall_col;
		// Shelves continue along the side walls of a narrow shop; at an oblique
		// street camera the window must not turn into an empty beige rectangle.
		vec2 side_uv = vec2(clamp(-p.z / depth, 0.002, 0.998), clamp(1.0 - wy / (ceil_y - floor_y), 0.002, 0.998));
		col = mix(col, texture(back_tex, side_uv).rgb, 0.88);
		col *= mix(0.92, 0.72, dz);
	} else if (hit == 2) {
		col = texture(floor_tex, p.xz * 0.7).rgb * 0.8;
		col *= mix(0.95, 0.75, dz);
	} else {
		col = ceil_col * mix(0.85, 0.7, dz);
	}
	// soft contact shading where the room's planes meet
	float edge = min(min(p.x - x0, x1 - p.x), min(p.y - floor_y, ceil_y - p.y));
	col *= mix(0.72, 1.0, smoothstep(0.0, 0.35, edge));
	// display furniture layer
	float tm = (-mid_d - ro.z) / rd.z;
	if (tm > 0.0 && tm < t) {
		vec3 pm = ro + rd * tm;
		float tile = mid_h * mid_aspect;
		float u = (pm.x - mid_shift) / tile;
		float f = fract(u);
		if (mod(floor(u), 2.0) > 0.5) { f = 1.0 - f; }
		float v = 1.0 - (pm.y - floor_y) / mid_h;
		if (v >= 0.0 && v <= 1.0) {
			vec4 m = texture(mid_tex, vec2(f, v));
			col = mix(col * 0.82, m.rgb, m.a);   // things behind the furniture sit in its shade
		}
	}
	// lamps: warm, brightest near the ceiling at the front
	float glow = lamp * (0.85 + 0.25 * smoothstep(floor_y, ceil_y, p.y) - 0.2 * dz);
	vec3 inside = col * lamp_col * glow;
	// glass: sky reflection that grows at grazing angles, plus a faint diagonal sheen
	float fres = pow(1.0 - abs(rd.z), 3.0);
	float sheen = smoothstep(0.46, 0.5, fract((lp.x + lp.y * 0.7) * 0.18)) * smoothstep(0.62, 0.5, fract((lp.x + lp.y * 0.7) * 0.18));
	float refl = clamp(0.1 + 0.55 * fres + 0.12 * sheen, 0.0, 0.8);
	ALBEDO = mix(inside * 0.5, sky_col * 0.5, refl);
	EMISSION = inside * (1.0 - refl) * 0.9;
	ROUGHNESS = 0.25;
	SPECULAR = 0.35;
}
