shader_type spatial;
render_mode world_vertex_coords,cull_disabled,specular_disabled;
#include "res://shaders/meadow_colour.gdshaderinc"
#include "res://shaders/material_poc_meadow.gdshaderinc"
global uniform float wind_strength;
global uniform vec2 wind_direction;
varying vec3 grass_world;
varying float blade_height;
varying float blade_random;
varying float blade_side;
void vertex(){
 blade_height=UV.y;
 blade_side=UV.x;
 blade_random=fract(COLOR.r+INSTANCE_CUSTOM.x);
 float wave=sin(dot(VERTEX.xz,wind_direction)*.8-TIME*1.4)*.5+.5;
 vec2 displacement=wind_direction*(.018+.045*wave)*wind_strength*UV.y*UV.y;
 VERTEX.xz+=displacement;
 VERTEX.y-=length(displacement)*.18;
 grass_world=VERTEX;
 NORMAL=normalize(mix(vec3(0,1,0),NORMAL,.22));
}
void fragment(){
 float h=clamp(blade_height,0.,1.);
 vec3 colour=poc_meadow(grass_world.xz);
 colour*=mix(.50,1.10,pow(h,.7))*(.78+clamp(blade_random,0.,1.)*.30);
 colour*=mix(.96,1.04,smoothstep(.35,.65,blade_side));
 NORMAL=normalize(mix(NORMAL,(VIEW_MATRIX*vec4(0,1,0,0)).xyz,.88));
 ALBEDO=colour;
 ROUGHNESS=1.;
 BACKLIGHT=vec3(.018,.028,.008)*h;
}
void light(){
 // Keep real tuft shadows, with the same readable darks as a painted background.
 float shade=LIGHT_IS_DIRECTIONAL?mix(.28,1.,ATTENUATION):ATTENUATION;
 DIFFUSE_LIGHT+=LIGHT_COLOR*shade*max(dot(NORMAL,LIGHT),0.)/3.14159265;
}
