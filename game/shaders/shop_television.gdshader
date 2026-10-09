shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D town_programme : source_color,filter_linear,repeat_disable;
uniform sampler2D farm_programme : source_color,filter_linear,repeat_disable;
uniform bool broadcast_on=true;
uniform int channel=0;
uniform float rain_amount=0.0;
uniform float snow_amount=0.13;
uniform float tuning_amount=0.0;
float noise_at(vec2 point) {
	// Avoid large floating-point sine hashes, which can collapse to a constant.
	uint value=uint(point.x)*uint(1664525)+uint(point.y)*uint(1013904223);
	value=value^(value>>uint(16));
	value=value*uint(2246822519);
	value=value^(value>>uint(13));
	return float(value&uint(1023))/1023.0;
}
void fragment() {
	vec2 p=UV*2.0-1.0;
	vec2 content_uv=.5+(UV-.5)*(1.0+.025*dot(p,p));
	float frame=floor(TIME*24.0);
	float tear=(noise_at(vec2(floor(UV.y*36.0),frame))-.5)*.035*tuning_amount;
	content_uv.x+=tear;
	vec3 colour=channel==0?texture(town_programme,content_uv).rgb:texture(farm_programme,content_uv).rgb;
	if(channel==1) {
		colour=mix(colour,colour*vec3(.61,.70,.84),rain_amount*.55);
		float drops=step(.97,fract(UV.x*27.0+floor(UV.y*15.0)))*smoothstep(.1,.8,fract(UV.y*8.0+TIME*.55));
		colour+=vec3(.13,.18,.22)*drops*rain_amount;
	}
	colour*=.96+.025*sin(UV.y*360.0+TIME*.4);
	float snow=noise_at(floor(UV*vec2(360.0,270.0))+vec2(frame*13.0,frame*37.0));
	colour=mix(colour,vec3(snow),snow_amount);
	float roll=1.0-smoothstep(.015,.075,abs(UV.y-fract(TIME*1.3)));
	colour*=1.0-roll*.3*tuning_amount;
	colour*=1.0-.1*pow(abs(p.x),3.0)-.07*pow(abs(p.y),3.0);
	if(!broadcast_on)colour=vec3(.018,.034,.035);
	ALBEDO=colour;EMISSION=colour*.25;
}
