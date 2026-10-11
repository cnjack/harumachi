shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform vec4 block_color : source_color = vec4(.80,.78,.72,1.);
uniform vec4 mortar_color : source_color = vec4(.62,.61,.58,1.);
uniform vec4 cap_color : source_color = vec4(.70,.69,.66,1.);
uniform float wall_top=1.4;
uniform float wall_base=0.;
uniform bool plaster=false;
uniform bool footing_only=false;
uniform bool local_weathering=false;
uniform float detail_seed=0.;
uniform int contact_count=0;
uniform vec4 contacts[8];
uniform bool has_plaster_tex=false;
uniform sampler2D plaster_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
varying vec3 wnorm;
varying vec4 stone_tone;
float hash(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
float noise(vec2 p){vec2 a=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(a),hash(a+vec2(1,0)),f.x),mix(hash(a+vec2(0,1)),hash(a+vec2(1)),f.x),f.y);}
void vertex(){wpos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wnorm=normalize((MODEL_MATRIX*vec4(NORMAL,0)).xyz);stone_tone=COLOR;}
void fragment(){
 float u=abs(wnorm.x)>.5?wpos.z:wpos.x;
 float v=max(0.,wpos.y-wall_base);
 float row=floor(v/.2),uu=u/.4+mod(row,2.)*.5;
 vec2 f=vec2(fract(uu),fract(v/.2));
 float mortar=step(.035,f.x)*step(f.x,.965)*step(.07,f.y)*step(f.y,.93);
 vec3 c=mix(mortar_color.rgb,block_color.rgb*(.94+.08*hash(vec2(floor(uu),row))),mortar);
 if(plaster){
  c=vec3(.90,.87,.78)*(.985+.025*noise(vec2(u*.55,v*1.7)));
  if(has_plaster_tex){vec3 painted=texture(plaster_tex,vec2(u,v)/2.4).rgb;c=mix(c,c*(.86+.22*painted),.38);}
 }
 if(footing_only)c=vec3(.70,.69,.64)*stone_tone.rgb*(.96+.055*noise(vec2(u*3.1,v*8.)));
 if(!plaster&&!footing_only&&(wpos.y>wall_top-.08||wnorm.y>.5))c=cap_color.rgb;
 if(local_weathering){
  float patch=noise(vec2(u*.76+detail_seed,2.4));
  // Broken damp patches reach 10--35 cm; the clean upper wall never shares this band.
  float height=.10+.25*noise(vec2(u*1.8+detail_seed,7.));
  float ragged=.012*(noise(vec2(u*22.,v*17.))-.5);
  float low=1.-smoothstep(height-.025,height+.015,v+ragged);
  float damp=low*smoothstep(.43,.66,patch)*.34;
  for(int contact=0;contact<8;contact++){
   if(contact>=contact_count)break;
   vec4 zone=contacts[contact];
   float horizontal=1.-smoothstep(.28,1.,abs(u-zone.x)/zone.y);
   float reach=zone.z+noise(vec2(u*9.+detail_seed,4.))*.035-.0175;
   float vertical=1.-smoothstep(reach-.03,reach+.015,v+ragged);
   damp=max(damp,horizontal*vertical*zone.w);
  }
  float splash=(1.-smoothstep(.025,.17,v))*smoothstep(.68,.84,noise(vec2(u*24.,v*43.+detail_seed)));
  float dust=(1.-smoothstep(.015,.065,v))*(.35+.65*noise(vec2(u*2.2,detail_seed)));
  c=mix(c,c*vec3(.58,.63,.59),damp*.88+splash*.13);
  c=mix(c,vec3(.59,.56,.47),dust*.18);
  // Sparse moss specks accompany the separate tiny fibre tufts, never a green painted strip.
  float shade=abs(wnorm.x)>.5?step(0.,wnorm.x):step(0.,wnorm.z);
  float moss=(1.-smoothstep(.025,.075,v))*smoothstep(.66,.83,patch)*smoothstep(.6,.8,noise(vec2(u*56.,v*62.)))*shade;
  c=mix(c,vec3(.39,.46,.29),moss*.22);
 }
 ALBEDO=c;ROUGHNESS=1.;SPECULAR=0.;
}
