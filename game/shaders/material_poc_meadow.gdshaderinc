// Metre-scaled painted grass marks, shared by the near ground and the outer meadow.
uniform float poc_night=0.;
vec3 poc_meadow(vec2 p){
 float macro=field_noise(p*.19)*.7+field_noise(p*.61+13.)*.3;
 vec3 colour=mix(vec3(.075,.21,.075),vec3(.23,.36,.08),smoothstep(.24,.79,macro));
 float distance_fade=1.-smoothstep(.12,.55,length(fwidth(p)));
 vec2 q=p*vec2(6.,10.);
 vec2 cell=floor(q),f=fract(q);
 float centre=.2+field_hash(cell)*.6;
 float stroke=(1.-smoothstep(.025,.16,abs(f.x-centre-(f.y-.5)*.22)))*smoothstep(.0,.25,f.y)*(1.-smoothstep(.64,.94,f.y));
 colour=mix(colour,colour*vec3(1.28,1.19,.95),stroke*.26*distance_fade);
 return colour*mix(vec3(1),vec3(.65,.72,1.10),poc_night);
}
