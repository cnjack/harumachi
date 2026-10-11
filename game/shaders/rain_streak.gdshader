shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 rain_color : source_color = vec4(0.78, 0.85, 0.98, 0.32);
uniform float near_start = 1.5;
uniform float near_end = 4.0;
uniform float streak_height = 0.55;
uniform bool clip_region = false;
uniform vec4 clip_rect = vec4(-100000.0, -100000.0, 100000.0, 100000.0);
// Numeric metres sampled once from P09's actual upward-facing canopy triangles.
// The inverse model matrix keeps this local shelter correct after any transform.
uniform bool shelter_enabled = false;
uniform mat4 shelter_world_to_local;
uniform vec4 shelter_rect;
uniform sampler2D shelter_height : filter_nearest, repeat_disable;
uniform float shelter_surface_margin = 0.002;
varying float near_alpha;
varying vec3 rain_world;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	float scale_x = length(MODEL_MATRIX[0].xyz);
	float scale_y = length(MODEL_MATRIX[1].xyz);
	vec3 forward = vec3(INV_VIEW_MATRIX[2].x, 0.0, INV_VIEW_MATRIX[2].z);
	forward = length(forward) > 0.001 ? normalize(forward) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
	vec3 world_vertex = centre + right * VERTEX.x * scale_x + vec3(0.0, 1.0, 0.0) * VERTEX.y * scale_y;
	rain_world = world_vertex;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_vertex, 1.0);
	// Fade the entire particle, using its nearest possible edge depth. Per-
	// vertex fading can leave a bright cut-off across a near-clipped quad.
	float nearest_depth = -(VIEW_MATRIX * vec4(centre, 1.0)).z - streak_height * scale_y * 0.5;
	near_alpha = smoothstep(near_start, near_end, nearest_depth);
}

void fragment() {
	if (clip_region && (rain_world.x < clip_rect.x || rain_world.z < clip_rect.y || rain_world.x > clip_rect.z || rain_world.z > clip_rect.w)) { discard; }
	if (shelter_enabled) {
		vec3 local_rain = (shelter_world_to_local * vec4(rain_world, 1.0)).xyz;
		vec2 shelter_uv = (local_rain.xz - shelter_rect.xy) / (shelter_rect.zw - shelter_rect.xy);
		if (all(greaterThanEqual(shelter_uv, vec2(0.0))) && all(lessThan(shelter_uv, vec2(1.0)))) {
			ivec2 size = textureSize(shelter_height, 0);
			vec2 grid = shelter_uv * vec2(size - ivec2(1));
			ivec2 cell = clamp(ivec2(floor(grid)), ivec2(0), size - ivec2(2));
			vec2 f = grid - vec2(cell);
			float a = texelFetch(shelter_height, cell, 0).r;
			float b = texelFetch(shelter_height, cell + ivec2(1, 0), 0).r;
			float c = texelFetch(shelter_height, cell + ivec2(0, 1), 0).r;
			float d = texelFetch(shelter_height, cell + ivec2(1, 1), 0).r;
			// A real uncovered cell stays wet; do not bridge holes with a mask.
			if (min(min(a, b), min(c, d)) >= 0.0) {
				float roof_y = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
				if (local_rain.y < roof_y - shelter_surface_margin) { discard; }
			}
		}
	}
	float across = smoothstep(0.0, 0.35, UV.x) * (1.0 - smoothstep(0.65, 1.0, UV.x));
	float along = smoothstep(0.0, 0.22, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	ALBEDO = rain_color.rgb;
	ALPHA = rain_color.a * across * along * near_alpha;
}
