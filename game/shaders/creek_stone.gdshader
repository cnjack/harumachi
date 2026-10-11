shader_type spatial;
render_mode diffuse_toon,specular_disabled;
uniform sampler2D painted_tex : source_color,repeat_enable,filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color=vec4(1);
uniform float water_level=-.28;
uniform float grain_scale=1.15;
uniform float wet_darkening=.72;
uniform float wet_band_height=.028;
varying vec3 world_position;
varying vec3 stone_normal;
void vertex(){
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 stone_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment(){
 // World-space painting avoids stretching an imported rock atlas into one large blob.
 vec3 weights=pow(abs(stone_normal),vec3(4.0));
 weights/=max(dot(weights,vec3(1.0)),.0001);
 vec3 q=world_position*grain_scale;
 vec3 col=texture(painted_tex,q.zy).rgb*weights.x+
          texture(painted_tex,q.xz).rgb*weights.y+
          texture(painted_tex,q.xy).rgb*weights.z;
 col*=tint.rgb;
 float waterline=water_level+wet_band_height+.006*sin(world_position.x*7.1+world_position.z*4.7);
 float wet=1.0-smoothstep(waterline-.015,waterline+.018,world_position.y);
 // A restrained cool wet edge, not an all-green moss band or a glossy PBR rock.
 col*=mix(1.0,wet_darkening,wet);
 float damp_edge=(1.0-smoothstep(.005,.019,abs(world_position.y-waterline)))*.055;
 ALBEDO=mix(col,col*vec3(.83,.96,1.05),wet*.30)+vec3(.48,.61,.65)*damp_edge;
 ROUGHNESS=1.0;SPECULAR=0.0;
}
