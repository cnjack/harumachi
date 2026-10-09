shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D wood_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(.76,.57,.36,1);
uniform mat4 part_transform;
uniform int finish_kind=0; // wood, cloth, selective dining table, summer linen
uniform bool has_original=false;
uniform float grain_strength=1.0;
uniform int grain_axis=0;
varying vec3 p;
varying vec3 normal_part;
void vertex(){p=(part_transform*vec4(VERTEX,1)).xyz;normal_part=normalize(mat3(part_transform)*NORMAL);}
vec3 wood(){
 float along=grain_axis==1?p.y:(grain_axis==2?p.z:p.x);
 float across=grain_axis==1?(abs(normal_part.x)>.5?p.z:p.x):(grain_axis==2?(abs(normal_part.y)>.5?p.x:p.y):(abs(normal_part.y)>.5?p.z:p.y));
 vec2 grain_uv=vec2(across*2.2,along*.75);
 float grain=dot(texture(wood_tex,grain_uv).rgb,vec3(.2126,.7152,.0722));
 vec3 colour=base_color.rgb*(1.+(grain-.4)*grain_strength);
 if(normal_part.y>.5){float board=fract((p.z+.46)/.185);float seam=smoothstep(.003,.012,min(board,1.-board));colour*=.90+.10*seam;}
 return colour;
}
void fragment(){
 vec3 original=has_original?texture(albedo_tex,UV).rgb:base_color.rgb;
 vec3 colour=wood();
 if(finish_kind==1){float weave=.96+.04*sin(p.x*90.)*sin(p.z*90.);colour=base_color.rgb*weave;}
 if(finish_kind==2){bool top=normal_part.y>.7&&p.y>.66&&p.y<.82&&abs(p.x)<.54&&abs(p.z)<.36;colour=top?wood():original;}
 if(finish_kind==3){
  bool linen=p.y<.41&&p.y>.05&&(abs(p.x)>.48||abs(p.z)>.46);
  float fold=dot(original,vec3(.2126,.7152,.0722));
  colour=linen?mix(vec3(.49,.65,.58),vec3(.84,.88,.75),clamp(fold*1.25,.2,.9)):original;
 }
 ALBEDO=colour;ROUGHNESS=1.;SPECULAR=0.;
}
