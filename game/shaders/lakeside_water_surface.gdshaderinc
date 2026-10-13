#include "res://shaders/water_motion.gdshaderinc"
#include "res://shaders/lakeside_shape.gdshaderinc"
uniform vec4 deep_color : source_color=vec4(.035,.20,.34,1);
uniform vec4 middle_color : source_color=vec4(.075,.46,.55,1);
uniform vec4 shallow_color : source_color=vec4(.38,.77,.69,1);
uniform vec4 foam_color : source_color=vec4(.87,.97,.95,1);
uniform float flow_highlight=.18;
uniform float ripple_contrast=.072;
uniform float sun_path_width=24.0;
uniform float foam_amount=.22;
uniform float shallow_opacity=.34;
uniform float sunlight_amount=1.0;
uniform float lamp_amount=0.0;
uniform float moonlight_amount=1.0;
uniform vec3 moon_position=vec3(95,118,420);
// Positions of actual nearby farm lamps, filled after the farm finishes building.
uniform vec3 reflection_lamps[8];
uniform float reflection_lamp_weights[8];
uniform int reflection_lamp_count=0;
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
 float actual_depth=water_depth_at(p);
 if(abs(behind.w)>.00001){
  behind.xyz/=behind.w;
  actual_depth=clamp(world_position.y-behind.y,0.0,5.0);
 }
 // Opaque stones, the real bottom and bridge supports affect the water above them.
 float depth=mix(water_depth_at(p),actual_depth,.92);
 float depth_weight=smoothstep(.22,2.25,depth);
 float t=water_clock();float river_weight=1.0-smoothstep(70.0,83.0,p.x);
 vec2 velocity=mix(vec2(.035,.015),flow_direction(p)*.38,river_weight);
 float flowing=flow_sample(p,velocity,t);
 vec3 ripple=water_waves(p,t);
 vec2 slopes=ripple.xy+water_fine_slopes(p,t);
 vec3 normal=normalize(vec3(-slopes.x,1.0,-slopes.y));
 vec3 sight=normalize(CAMERA_POSITION_WORLD-world_position);
 vec3 reflected=reflect(-sight,normal);
 vec3 sky_ray=vec3(reflected.x,abs(reflected.y),reflected.z);
 vec2 sky_uv=vec2(atan(sky_ray.z,sky_ray.x)/6.2831853+.5,acos(clamp(sky_ray.y,-1,1))/3.14159265);
 vec3 sky=mix(texture(sky_day,sky_uv).rgb,texture(sky_dusk,sky_uv).rgb,dusk_w);
 sky=mix(sky,texture(sky_night,sky_uv).rgb,night_w);
 float fresnel=pow(1.0-max(dot(sight,normal),0.0),3.0);
 vec3 col=mix(shallow_color.rgb,middle_color.rgb,smoothstep(.10,.85,depth));
 col=mix(col,deep_color.rgb,smoothstep(.75,2.35,depth));
 col=mix(col,sky,.09+fresnel*.23);
 // Quiet, broken bands make small waves readable away from the exact
 // reflection angle. They move with the same analytic normals as the light.
 float wave_band=slopes.x*.55+slopes.y*.85;
 float band_aa=max(fwidth(wave_band),.004);
 float crest=smoothstep(.024-band_aa,.055+band_aa,wave_band);
 float broken_crest=crest*smoothstep(.28,.61,flowing);
 col=mix(col,vec3(.58,.79,.80),broken_crest*ripple_contrast*(1.0-night_w*.65));
 float streak=smoothstep(.70,.88,flowing)*river_weight;
 col=mix(col,vec3(.66,.88,.86),streak*flow_highlight*(1.0-night_w*.75));
 // Sparse moving dashes exist only inside the reflected sun/moon/light path.
 float fragments=water_sparkle_mask(p,velocity,t);
 float sun_path=pow(max(dot(reflected,normalize(sun_direction)),0.0),sun_path_width);
 float sun_glints=sun_path*fragments*sunlight_amount*(1.0-night_w)*(1.0-rain_amount);
 vec3 sun_color=mix(vec3(1.0,.98,.84),vec3(1.0,.76,.43),dusk_w);
 col=mix(col,sun_color,clamp(sun_glints*.72,0.0,.72));
 float moon_path=pow(max(dot(reflected,normalize(moon_position-world_position)),0.0),96.0);
 float moon_glints=moon_path*fragments*night_w*moonlight_amount*(1.0-rain_amount*.85);
 vec3 lamp_glints=vec3(0.0);
 for(int light_index=0;light_index<8;light_index++){
  if(light_index<reflection_lamp_count){
   vec3 to_lamp=reflection_lamps[light_index]-world_position;
   float distance_to_lamp=length(to_lamp);
   float path=pow(max(dot(reflected,normalize(to_lamp)),0.0),80.0);
   float falloff=1.0-smoothstep(2.0,9.0,distance_to_lamp);
   lamp_glints+=vec3(1.0,.69,.32)*path*falloff*(.035+fragments*.965)*lamp_amount*reflection_lamp_weights[light_index];
  }
 }
 vec3 night_palette=mix(vec3(.14,.30,.38),vec3(.045,.11,.25),depth_weight);
 col=mix(col,night_palette,night_w*.55);
 col=mix(col,vec3(.65,.82,.91),rain_rings(p,t));
 float shore_foam=(1.0-smoothstep(.02,.25,abs(d+.025)))*smoothstep(.57,.77,flowing);
 float stone_foam=(1.0-smoothstep(.025,.12,actual_depth))*smoothstep(.61,.81,flowing);
 col=mix(col,foam_color.rgb,max(shore_foam,stone_foam*.45)*foam_amount);
 NORMAL=normalize((VIEW_MATRIX*vec4(normal,0)).xyz);
 vec3 surface_tint=mix(tint.rgb,vec3(.53,.64,.84),night_w*.60);
 ALBEDO=col*surface_tint;
 // A low blue floor preserves night depth bands; only narrow light paths glow.
 EMISSION=col*mix(surface_tint*.075,vec3(.16),night_w)+sun_color*sun_glints*.42+
          vec3(.48,.69,.98)*moon_glints*.36+lamp_glints*.70;
 ROUGHNESS=1.0;
 ALPHA=clamp(mix(shallow_opacity,.98,smoothstep(.12,2.2,depth))+rain_amount*.035,0.0,1.0);
}
