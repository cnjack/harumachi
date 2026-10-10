shader_type spatial;
render_mode diffuse_toon,specular_disabled;
uniform vec3 meadow_green:source_color=vec3(.40,.54,.26);
uniform vec3 dry_green:source_color=vec3(.53,.58,.32);
uniform vec3 cool_green:source_color=vec3(.29,.44,.27);
varying vec3 meadow_world;
float field_hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float field_noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(field_hash(i),field_hash(i+vec2(1,0)),f.x),mix(field_hash(i+vec2(0,1)),field_hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){meadow_world=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec2 p=meadow_world.xz;
 float growth=field_noise(p*.12)+field_noise(p*.37+vec2(13,7))*.26;
 float dry=smoothstep(.63,.96,growth)*.62;
 float shade=smoothstep(.46,.76,field_noise(p*.24-vec2(4,19)))*.34;
 vec3 colour=mix(meadow_green,dry_green,dry);
 colour=mix(colour,cool_green,shade);
 // Quiet strokes break the uniform distant plane without photographic noise.
 float detail=1.-smoothstep(.25,.8,length(fwidth(p))*5.);
 float fleck=smoothstep(.64,.84,field_noise(p*vec2(5,2.8)))*.045*detail;
 ALBEDO=colour*(.985+fleck);ROUGHNESS=1.;
}
