shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 rain_color : source_color = vec4(0.78, 0.85, 0.98, 0.32);
uniform float near_start = 1.5;
uniform float near_end = 4.0;
uniform float streak_height = 0.55;
uniform bool clip_region = false;
uniform vec4 clip_rect = vec4(-100000.0, -100000.0, 100000.0, 100000.0);
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
	float across = smoothstep(0.0, 0.35, UV.x) * (1.0 - smoothstep(0.65, 1.0, UV.x));
	float along = smoothstep(0.0, 0.22, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	ALBEDO = rain_color.rgb;
	ALPHA = rain_color.a * across * along * near_alpha;
}
