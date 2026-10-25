// Opaque scene reflections. Screen exits and hidden geometry fall back to the painted sky.
uniform sampler2D reflected_scene:hint_screen_texture,repeat_disable,filter_linear_mipmap;
uniform bool scene_reflections=true;

vec3 poc_view_depth(vec2 uv,mat4 inverse_projection){
 float depth_value=textureLod(scene_depth,uv,0.).r;
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 vec3 ndc=vec3(uv*2.-1.,depth_value*2.-1.);
 #else
 vec3 ndc=vec3(uv*2.-1.,depth_value);
 #endif
 vec4 result=inverse_projection*vec4(ndc,1.);
 return result.xyz/result.w;
}

vec4 poc_scene_reflection(vec3 origin,vec3 direction,mat4 projection,mat4 inverse_projection,mat4 inverse_view,float water_y){
 if(!scene_reflections)return vec4(0);
 float travel=.22;
 float previous=0.;
 float stride=.30;
 for(int step_index=0;step_index<48;step_index++){
  vec3 point=origin+direction*travel;
  if(point.z>-.1||travel>160.)break;
  vec4 clip=projection*vec4(point,1.);
  vec2 uv=clip.xy/clip.w*.5+.5;
  if(any(lessThan(uv,vec2(.002)))||any(greaterThan(uv,vec2(.998))))break;
  vec3 surface=poc_view_depth(uv,inverse_projection);
  float difference=surface.z-point.z;
  if(difference>0.){
   float low=previous,high=travel;
   for(int refinement=0;refinement<6;refinement++){
    float middle=(low+high)*.5;
    vec3 probe=origin+direction*middle;
    vec4 probe_clip=projection*vec4(probe,1.);
    vec2 probe_uv=probe_clip.xy/probe_clip.w*.5+.5;
    float gap=poc_view_depth(probe_uv,inverse_projection).z-probe.z;
    if(gap>0.)high=middle;else low=middle;
   }
   point=origin+direction*high;
   clip=projection*vec4(point,1.);
   uv=clip.xy/clip.w*.5+.5;
   surface=poc_view_depth(uv,inverse_projection);
   vec3 real_surface=(inverse_view*vec4(surface,1.)).xyz;
   float thickness=.16+high*.014;
   float gap=surface.z-point.z;
   if(gap>=0.&&gap<thickness&&real_surface.y>water_y+.04){
    float edge=min(min(uv.x,1.-uv.x),min(uv.y,1.-uv.y));
    float confidence=smoothstep(.005,.075,edge)*(1.-smoothstep(100.,160.,high));
    return vec4(textureLod(reflected_scene,uv,.8).rgb,confidence);
   }
  }
  previous=travel;
  travel+=stride;
  stride*=1.13;
 }
 return vec4(0);
}
