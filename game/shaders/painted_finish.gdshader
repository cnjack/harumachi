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
uniform bool timber_detail=false;
uniform bool horizontal_face_grain=false;
uniform vec3 part_min=vec3(-.5);
uniform vec3 part_size=vec3(1.);
uniform float old_paint=0.;
uniform int component_count=0;
uniform vec4 component_min[64];
uniform vec4 component_max[64];
varying float measured_axis;
varying vec3 p;
varying vec3 normal_part;
void vertex(){
 p=(part_transform*vec4(VERTEX,1)).xyz;normal_part=normalize(mat3(part_transform)*NORMAL);
 measured_axis=float(grain_axis);
 for(int part=0;part<64;part++){
  if(part>=component_count)break;
  if(all(greaterThanEqual(p,component_min[part].xyz))&&all(lessThanEqual(p,component_max[part].xyz))){measured_axis=component_min[part].w;break;}
 }
}
vec3 wood(){
 int axis_index=int(round(measured_axis));
 if(finish_kind==4)axis_index=abs(p.x)>.90?1:0;
 float along=axis_index==1?p.y:(axis_index==2?p.z:p.x);
 float across=axis_index==1?(abs(normal_part.x)>.5?p.z:p.x):(axis_index==2?(abs(normal_part.y)>.5?p.x:p.y):(abs(normal_part.y)>.5?p.z:p.y));
 if(timber_detail&&axis_index!=1&&horizontal_face_grain&&abs(normal_part.y)<.7&&abs(normal_part.z)>.65){
  vec3 tangent=normalize(vec3(normal_part.z,0.,-normal_part.x));
  along=dot(p,tangent);across=p.y;
 }
 vec2 grain_uv=vec2(across*2.2,along*.75);
 float grain=dot(texture(wood_tex,grain_uv).rgb,vec3(.2126,.7152,.0722));
 vec3 colour=base_color.rgb*(1.+(grain-.4)*grain_strength);
 if(timber_detail){
  vec3 axis=axis_index==1?vec3(0,1,0):(axis_index==2?vec3(0,0,1):vec3(1,0,0));
  float end_face=step(.82,abs(dot(normal_part,axis)));
  vec2 cut=axis_index==1?p.xz:(axis_index==2?p.xy:p.zy);
  float rings=sin(length(cut*vec2(1.,1.15))*110.+sin(cut.x*11.)*.7);
  colour=mix(colour,base_color.rgb*(.88+.065*rings),end_face*.72);
  vec3 relative=(p-part_min)/max(part_size,vec3(.001));
  float edge=min(min(relative.x,1.-relative.x),min(relative.y,1.-relative.y));
  float chipped=(1.-smoothstep(.015,.075,edge))*(.4+.6*sin(along*24.)*sin(across*31.));
  colour=mix(colour,base_color.rgb*vec3(.89,.87,.81),clamp(chipped,0.,1.)*.16);
  // Old paint is rubbed at edges; colour and fibres stay subdued, with a dry anime finish.
  colour=mix(colour,base_color.rgb*(.96+.04*grain),old_paint*(1.-clamp(chipped,0.,1.)));
 }
 if(!timber_detail&&normal_part.y>.5){float board=fract((p.z+.46)/.185);float seam=smoothstep(.003,.012,min(board,1.-board));colour*=.90+.10*seam;}
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
 if(finish_kind==4){
  // P02 is one fused atlas. Preserve every paper, green pinboard and blue roof pixel.
  bool panel=abs(p.x)<.90&&p.y>.625&&p.y<1.65;
  bool frame=p.y>.04&&p.y<1.83&&(abs(p.x)>.90||p.y<.625||p.y>1.65);
  bool timber=original.r>original.g*1.08&&original.r>original.b*1.18;
  colour=frame&&!panel&&timber?mix(original,wood(),.65):original;
 }
 ALBEDO=colour;ROUGHNESS=1.;SPECULAR=0.;
}
