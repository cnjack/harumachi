shader_type spatial;
render_mode world_vertex_coords,diffuse_toon,specular_disabled,cull_disabled;
global uniform float wind_strength;
global uniform vec2 wind_direction;
void vertex() {
	// UV.y is zero on the tied edge, one at the free tip.
	float weight=UV.y*UV.y;
	float wave=sin(TIME*2.5+VERTEX.x*3.1)*.7+sin(TIME*4.2+VERTEX.x*1.7)*.3;
	VERTEX.xz+=wind_direction*wave*.12*wind_strength*weight;
	VERTEX.y+=abs(wave)*.035*wind_strength*weight;
}
void fragment() {
	ALBEDO=COLOR.rgb;ROUGHNESS=1.0;
	if(!FRONT_FACING)NORMAL=-NORMAL;
}
