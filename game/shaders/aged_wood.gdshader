shader_type spatial;
render_mode diffuse_toon,specular_disabled;
uniform sampler2D painted_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 tint : source_color=vec4(1);
uniform vec3 reference_origin=vec3(0);
uniform float wear_strength=.32;
uniform float vertical_grain=0.0;
varying vec3 p;
float hash(vec2 q){return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 q){vec2 i=floor(q),f=fract(q);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz-reference_origin;}
void fragment(){
 float board=floor((p.z+5.)/.384615);float seed=hash(vec2(board,3.7));
 vec2 uv=mix(vec2(p.x/1.9+seed*1.7,p.z*.31+seed),vec2(p.y*.48,p.x*2.1+p.z*1.7),vertical_grain);
 vec3 col=texture(painted_tex,uv).rgb*tint.rgb;
 col*=.85+seed*.27;
 float worn=step(.55,noise(p.xz*1.7+7.0))*wear_strength;
 float traffic=(1.-smoothstep(.30,.78,abs(p.x)))*step(.72,NORMAL.y);
 col=mix(col,col*vec3(1.12,1.09,1.03),worn*.48+traffic*wear_strength*.28);
 float stains=step(.72,noise(p.xz*2.7+19.0))*wear_strength;
 col*=1.-stains*.16;
 ALBEDO=col;ROUGHNESS=1.0;SPECULAR=0.0;
}
