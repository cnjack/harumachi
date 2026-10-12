shader_type spatial;
render_mode diffuse_toon,specular_disabled,cull_disabled;
// Small, shallow water: two drifting wave bands, authored independently of Blender nodes.
varying vec3 point;
void vertex(){point=VERTEX;}
void fragment(){
 vec2 p=point.xz*21.;
 float a=sin(p.x+sin(p.y*.73+TIME*.28)*1.5+TIME*.32);
 float b=sin(p.y*1.13+sin(p.x*.6-TIME*.19)*1.3-TIME*.25);
 float glint=smoothstep(.88,.99,max(a,b));
 ALBEDO=mix(vec3(.12,.34,.37),vec3(.50,.69,.64),glint*.42);
 ROUGHNESS=1.;
}
