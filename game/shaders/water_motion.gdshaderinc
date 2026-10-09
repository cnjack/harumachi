// Two half-cycle advections blend before either sample resets. Wave slopes are analytic.
uniform float animation_time=-1.0;
uniform float rain_amount=0.0;
uniform float wave_strength=1.0;
float water_clock() { return animation_time>=0.0?animation_time:TIME; }
float water_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float water_noise(vec2 p) { vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(water_hash(i),water_hash(i+vec2(1,0)),f.x),mix(water_hash(i+vec2(0,1)),water_hash(i+vec2(1,1)),f.x),f.y); }
float flow_sample(vec2 p,vec2 velocity,float t) {
	float phase_a=fract(t/8.0);float phase_b=fract(t/8.0+.5);float blend=abs(phase_a*2.0-1.0);
	vec2 a=p-velocity*phase_a*8.0;vec2 b=p-velocity*phase_b*8.0;
	float n_a=water_noise(a*vec2(.75,3.4))*.7+water_noise(a*vec2(1.7,5.2)+7.0)*.3;
	float n_b=water_noise(b*vec2(.75,3.4))*.7+water_noise(b*vec2(1.7,5.2)+7.0)*.3;
	return mix(n_a,n_b,blend);
}
vec3 gerstner(vec2 p,float t,vec2 direction,float wavelength,float amplitude,float speed) {
	vec2 d=normalize(direction);float k=6.2831853/wavelength;float phase=k*dot(d,p)-t*speed;float slope=k*amplitude*cos(phase);
	return vec3(d*slope,amplitude*sin(phase));
}
vec3 water_waves(vec2 p,float t) { return (gerstner(p,t,vec2(1,.32),3.8,.014,1.35)+gerstner(p,t,vec2(.2,1),1.9,.006,1.65)+gerstner(p,t,vec2(-.8,.45),.85,.002,1.8))*wave_strength; }
float rain_rings(vec2 p,float t) {
 vec2 cell=floor(p*1.1);float result=0.0;
 for(int x=-1;x<=1;x++){for(int y=-1;y<=1;y++){
  vec2 q=cell+vec2(float(x),float(y));float seed=water_hash(q);
  vec2 center=(q+vec2(seed,water_hash(q+17.0)))/1.1;
  float age=fract(t*.68+seed);float radius=age*.5;float distance=length(p-center);
  result+=smoothstep(.035,.0,abs(distance-radius))*sin(age*3.14159)*.22;
 }}return result*rain_amount;
}
