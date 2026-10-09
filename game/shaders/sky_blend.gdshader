shader_type sky;
// Day / dusk / night panoramas blended by the clock (WorldBuilder.update_time). The whole dome
// drifts slowly around the vertical axis so the painted clouds seem to move.

uniform sampler2D sky_day : source_color, filter_linear, repeat_enable;
uniform sampler2D sky_dusk : source_color, filter_linear, repeat_enable;
uniform sampler2D sky_night : source_color, filter_linear, repeat_enable;
uniform float dusk_w : hint_range(0.0, 1.0) = 0.0;
uniform float night_w : hint_range(0.0, 1.0) = 0.0;
uniform float drift = 0.0;          // 0..1 of a turn
uniform float dusk_offset = -0.48;  // puts the painted sunset sun in the west, behind the evening light
uniform float night_offset = 0.0;
uniform vec3 tint = vec3(1.0);
uniform float energy = 1.0;
uniform float cloud_cover = 0.28;
uniform vec2 cloud_offset = vec2(0.0);
uniform vec3 sun_direction = vec3(0.5,0.7,0.3);
uniform float sun_visibility = 1.0;
uniform sampler2D cloud_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex_second : source_color, filter_linear_mipmap, repeat_enable;

float cloud_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float cloud_noise(vec2 p) {
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(cloud_hash(i),cloud_hash(i+vec2(1,0)),f.x),mix(cloud_hash(i+vec2(0,1)),cloud_hash(i+vec2(1,1)),f.x),f.y);
}

void sky() {
	vec2 uv = SKY_COORDS;
	vec3 c = texture(sky_day, vec2(uv.x + drift, uv.y)).rgb;
	if (dusk_w > 0.001) {
		c = mix(c, texture(sky_dusk, vec2(uv.x + dusk_offset + drift * 0.5, uv.y)).rgb, dusk_w);
	}
	if (night_w > 0.001) {
		c = mix(c, texture(sky_night, vec2(uv.x + night_offset + drift * 0.25, uv.y)).rgb, night_w);
	}
	// Move the existing painted cumulus cutouts at different speeds, without rotating stars.
	vec4 layer=texture(cloud_tex,vec2(uv.x*5.0+cloud_offset.x*.3,uv.y*3.3-.13));
	vec4 layer_second=texture(cloud_tex_second,vec2(uv.x*6.0-cloud_offset.x*.18+.4,uv.y*3.8+.25));
	float horizon=smoothstep(-.02,.15,EYEDIR.y);
	float overcast=smoothstep(.45,.96,cloud_cover)*horizon;
	float cloud_noise_value=cloud_noise(EYEDIR.xz*5.0+cloud_offset);
	vec3 storm=mix(vec3(.54,.61,.75),vec3(.72,.77,.84),cloud_noise_value);
	storm=mix(storm,vec3(.15,.20,.33),night_w);
	c=mix(c,storm,overcast*.90);
	vec3 cloud_tint=mix(vec3(1.0),vec3(1.0,.81,.66),dusk_w*.55);
	cloud_tint=mix(cloud_tint,vec3(.19,.25,.41),night_w*.9);
	cloud_tint*=mix(1.0,.69,overcast);
	float clouds=layer.a*horizon*mix(.08,.42,cloud_cover);
	c=mix(c,layer.rgb*cloud_tint,clouds);
	c=mix(c,layer_second.rgb*cloud_tint,layer_second.a*horizon*cloud_cover*.22);
	float sun_dot=dot(normalize(EYEDIR),normalize(sun_direction));
	float disk=smoothstep(cos(.018),cos(.014),sun_dot);
	float halo=pow(max(sun_dot,0.0),120.0)*.16;
	float sun_amount=sun_visibility*(1.0-night_w)*smoothstep(.0,.08,sun_direction.y)*(1.0-clouds);
	c+=mix(vec3(1.0,.94,.74),vec3(1.0,.63,.30),dusk_w)*(disk*1.7+halo)*sun_amount;
	COLOR = c * tint * energy;
}
