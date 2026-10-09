shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D town_programme : source_color,filter_linear;
uniform sampler2D farm_programme : source_color,filter_linear;
uniform bool broadcast_on=true;
uniform int channel=0;
uniform float rain_amount=0.0;
void fragment() {
	vec2 p=UV*2.0-1.0;
	if(length(max(abs(p)-vec2(.87,.86),vec2(0)))>.12)discard;
	vec2 drift=vec2(sin(TIME*.10)*.009,cos(TIME*.12)*.006);
	vec3 colour=channel==0?texture(town_programme,UV+drift).rgb:texture(farm_programme,UV+drift).rgb;
	if(channel==1) {
		colour=mix(colour,colour*vec3(.61,.70,.84),rain_amount*.55);
		float drops=step(.97,fract(UV.x*27.0+floor(UV.y*15.0)))*smoothstep(.1,.8,fract(UV.y*8.0+TIME*.55));
		colour+=vec3(.13,.18,.22)*drops*rain_amount;
	}
	colour*=.96+.025*sin(UV.y*360.0+TIME*.4);
	if(!broadcast_on)colour=vec3(.018,.034,.035);
	ALBEDO=colour;EMISSION=colour*.25;
}
