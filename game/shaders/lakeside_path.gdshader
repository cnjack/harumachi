shader_type spatial;
render_mode blend_mix,depth_prepass_alpha,diffuse_toon,specular_disabled;
uniform sampler2D albedo_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform float wear_strength=.30;
varying vec3 wp;
float hash(vec2 q){return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 q){vec2 i=floor(q),f=fract(q);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec3 col=texture(albedo_tex,wp.xz/3.2).rgb;
 float broad=noise(wp.xz*.31+17.);float scuff=step(.58,noise(wp.xz*1.3+3.));
 float centre=1.-smoothstep(.08,.43,abs(UV.x-.5));
 col*=1.+(broad-.5)*wear_strength*.48;
 col=mix(col,col*vec3(1.05,1.02,.96),centre*wear_strength*.55);
 col*=1.-scuff*wear_strength*.12;
 ALBEDO=col;ROUGHNESS=1.;SPECULAR=0.;
 float edge=min(UV.x,1.-UV.x);
 float ragged=noise(wp.xz*4.1)*.045+noise(wp.xz*11.3)*.015;
 ALPHA=smoothstep(.01,.10,edge-ragged+.025);
}
