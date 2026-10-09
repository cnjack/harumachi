shader_type spatial;
render_mode diffuse_toon,specular_disabled,cull_disabled;
#include "res://shaders/water_motion.gdshaderinc"
uniform vec4 deep : source_color=vec4(.09,.39,.49,1);
uniform vec4 shallow : source_color=vec4(.35,.70,.65,1);
uniform vec4 highlight : source_color=vec4(.84,.97,.96,1);
uniform vec4 tint : source_color=vec4(1);
uniform float flow=.38;
uniform float width=6.0;
varying vec2 world_xz;
varying vec3 wave_normal;
void vertex() {
 world_xz=(MODEL_MATRIX*vec4(VERTEX,1)).xz;
 vec3 wave=water_waves(world_xz,water_clock());VERTEX.y+=wave.z;
 wave_normal=normalize(vec3(-wave.x,1,-wave.y));
}
void fragment() {
 float t=water_clock();float moving=flow_sample(world_xz,vec2(flow,0),t);
 float across=abs(UV.y-.5)*2.0;vec3 col=mix(deep.rgb,shallow.rgb,smoothstep(.35,1.0,across)*.8);
 float streak=smoothstep(.69,.79,moving)*(.30+.20*sin(world_xz.y*2.4));
 float foam=smoothstep(.82,.98,across)*smoothstep(.42,.68,moving);
 col=mix(col,highlight.rgb,streak*.62+foam*.42);
 col=mix(col,highlight.rgb,rain_rings(world_xz,t));
 vec3 ripple=water_waves(world_xz,t);vec3 normal=normalize(vec3(-ripple.x,1,-ripple.y));
 NORMAL=normalize((VIEW_MATRIX*vec4(normal,0)).xyz);
 ALBEDO=col*tint.rgb;EMISSION=col*tint.rgb*.12;ROUGHNESS=1.0;
}
