shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D view_tex:source_color,filter_linear_mipmap_anisotropic;
uniform float daylight=1.;
uniform vec3 weather_tint=vec3(1.);
uniform float cloud_amount=0.;
uniform vec2 uv_scale=vec2(1.);
uniform vec2 uv_offset=vec2(0.);
uniform vec3 view_tint=vec3(1.);
uniform float day_gain=.82;
uniform bool front_only=false;
void fragment(){
 if(front_only&&!FRONT_FACING){discard;}
 vec3 c=texture(view_tex,UV*uv_scale+uv_offset).rgb;
 float grey=dot(c,vec3(.2126,.7152,.0722));
 c=mix(c,vec3(grey),cloud_amount*.65)*weather_tint;
 ALBEDO=mix(c*vec3(.065,.10,.20),c*day_gain,daylight)*view_tint;
}
