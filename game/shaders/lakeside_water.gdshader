shader_type spatial;
render_mode blend_mix,depth_draw_never,diffuse_toon,specular_disabled,cull_disabled;
#include "res://shaders/water_motion.gdshaderinc"
#include "res://shaders/lakeside_shape.gdshaderinc"
uniform vec4 deep_color : source_color=vec4(.035,.21,.34,1);
uniform vec4 shallow_color : source_color=vec4(.43,.79,.70,1);
uniform vec4 foam_color : source_color=vec4(.87,.97,.95,1);
uniform float flow_highlight=.24;
uniform float foam_amount=.35;
uniform float shallow_opacity=.62;
uniform sampler2D scene_depth : hint_depth_texture,repeat_disable,filter_nearest;
uniform vec4 tint : source_color=vec4(1);
uniform sampler2D sky_day : source_color,filter_linear_mipmap;
uniform sampler2D sky_dusk : source_color,filter_linear_mipmap;
uniform sampler2D sky_night : source_color,filter_linear_mipmap;
uniform float dusk_w=0.0;
uniform float night_w=0.0;
uniform vec3 sun_direction=vec3(.5,.5,.3);
varying vec2 p;
varying vec3 world_position;
void vertex(){p=VERTEX.xz;VERTEX.y+=water_waves(p,water_clock()).z;world_position=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 float d=water_distance(p);if(d>.12)discard;
 float raw_depth=textureLod(scene_depth,SCREEN_UV,0.0).r;
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 vec3 ndc=vec3(SCREEN_UV*2.0-1.0,raw_depth*2.0-1.0);
 #else
 vec3 ndc=vec3(SCREEN_UV*2.0-1.0,raw_depth);
 #endif
 vec4 behind=INV_VIEW_MATRIX*INV_PROJECTION_MATRIX*vec4(ndc,1.0);
 behind.xyz/=behind.w;
 float actual_depth=clamp(world_position.y-behind.y,0.0,5.0);
 float depth=mix(water_depth_at(p),actual_depth,.85);
 float depth_weight=smoothstep(.12,1.7,depth);
 float t=water_clock();float river_weight=1.0-smoothstep(70.0,83.0,p.x);
 vec2 velocity=mix(vec2(.035,.015),flow_direction(p)*.38,river_weight);
 float flowing=flow_sample(p,velocity,t);
 vec3 ripple=water_waves(p,t);vec3 normal=normalize(vec3(-ripple.x,1,-ripple.y));
 vec3 sight=normalize(CAMERA_POSITION_WORLD-world_position);
 vec3 reflected=reflect(-sight,normal);reflected.y=abs(reflected.y);
 vec2 sky_uv=vec2(atan(reflected.z,reflected.x)/6.2831853+.5,acos(clamp(reflected.y,-1,1))/3.14159265);
 vec3 sky=mix(texture(sky_day,sky_uv).rgb,texture(sky_dusk,sky_uv).rgb,dusk_w);
 sky=mix(sky,texture(sky_night,sky_uv).rgb,night_w);
 float fresnel=pow(1.0-max(dot(sight,normal),0.0),3.0);
 vec3 col=mix(shallow_color.rgb,deep_color.rgb,depth_weight);
 col=mix(col,sky,.035+fresnel*.085);
 float streak=smoothstep(.75,.84,flowing)*river_weight;
 float sun_path=pow(max(dot(reflected,normalize(sun_direction)),0.0),52.0)*(1.0-night_w);
 vec3 light=mix(vec3(.85,.98,1),vec3(1,.80,.49),dusk_w);
 col=mix(col,light,streak*flow_highlight*.60+sun_path*.12*(1.0-rain_amount));
 col=mix(col,vec3(.65,.82,.91),rain_rings(p,t));
 float shore_foam=(1.0-smoothstep(.02,.34,abs(d+.03)))*smoothstep(.38,.69,flowing);
 float stone_foam=(1.0-smoothstep(.035,.17,actual_depth))*smoothstep(.54,.72,flowing);
 col=mix(col,foam_color.rgb,max(shore_foam,stone_foam*.55)*foam_amount);
 NORMAL=normalize((VIEW_MATRIX*vec4(normal,0)).xyz);
 ALBEDO=col*tint.rgb;EMISSION=col*tint.rgb*.045;ROUGHNESS=1.0;
 ALPHA=mix(shallow_opacity,1.0,smoothstep(.20,1.25,depth));
}
