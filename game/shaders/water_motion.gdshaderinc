// Two half-cycle advections blend before either sample resets. Wave slopes are analytic.
uniform float animation_time=-1.0;
uniform float rain_amount=0.0;
uniform float wave_strength=1.0;
// World metres. A light summer shower makes small ripples, not metre-wide hoops.
uniform float rain_ring_radius=.145;
uniform float rain_ring_width=.008;
uniform float rain_ring_strength=.11;
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
// The short ripples affect the reflected light, without lifting the shoreline.
vec2 water_fine_slopes(vec2 p,float t) {
 return (gerstner(p,t,vec2(.92,.38),.48,.0036,2.2).xy+
         gerstner(p,t,vec2(-.35,.94),.29,.0018,2.65).xy)*min(wave_strength,1.65);
}
float water_sparkle_mask(vec2 p,vec2 velocity,float t) {
 vec2 drift=p-velocity*t;
 float broken=water_noise(drift*vec2(3.7,14.0))*.72+water_noise(drift*vec2(8.1,23.0)+vec2(t*.11,3.7))*.28;
 float aa=max(fwidth(broken),.018);
 return smoothstep(.65-aa,.78+aa,broken);
}
float rain_rings(vec2 p,float t) {
 float density=2.35;
 vec2 cell=floor(p*density);float result=0.0;
 // The continuous world-position footprint survives a cell change. Taking a
 // derivative of distance-to-a-hashed-centre makes hard rectangular seams.
 float aa=max(length(fwidth(p)),.002);
 for(int x=-1;x<=1;x++){for(int y=-1;y<=1;y++){
  vec2 q=cell+vec2(float(x),float(y));float seed=water_hash(q);
  vec2 center=(q+vec2(seed,water_hash(q+17.0)))/density;
  float age=fract(t*1.15+seed);float radius=age*rain_ring_radius;float distance=length(p-center);
  float ring=1.0-smoothstep(rain_ring_width,rain_ring_width+aa,abs(distance-radius));
  result+=ring*sin(age*3.14159)*(1.0-age)*rain_ring_strength;
 }}return result*rain_amount;
}
