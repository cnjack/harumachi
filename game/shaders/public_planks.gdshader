shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D grain_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec3 room_origin=vec3(0);
uniform vec4 tint:source_color=vec4(.75,.63,.48,1);
uniform float board_width=.30;
uniform float board_length=1.8;
uniform bool along_x=false;
varying vec3 local_position;
float ph(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){local_position=(MODEL_MATRIX*vec4(VERTEX,1)).xyz-room_origin;}
void fragment(){
 vec2 p=along_x?local_position.zx:local_position.xz;
 float row=floor(p.x/board_width);float offset=ph(vec2(row,6))*board_length;
 float col=floor((p.y+offset)/board_length);
 vec2 cell=vec2(row,col);vec2 f=vec2(fract(p.x/board_width),fract((p.y+offset)/board_length));
 vec2 grain_uv=vec2(f.x*.19+ph(cell)*.81,f.y+ph(cell+2.));
 vec3 grain=texture(grain_tex,grain_uv).rgb;
 float seam=min(min(f.x,1.-f.x)*board_width,min(f.y,1.-f.y)*board_length);
 float aa=max(fwidth(p.x),fwidth(p.y))*.6;
 float gap=smoothstep(.002-aa,.002+aa,seam);
 vec3 colour=mix(grain*tint.rgb*.66,grain*tint.rgb*(.92+.12*ph(cell+8.)),gap);
 float worn=step(.94,ph(cell+5.))*smoothstep(.05,.4,f.y)*(1.-smoothstep(.7,.95,f.y));
 colour=mix(colour,colour*vec3(1.06,1.05,1.03),worn*.4);
 ALBEDO=colour;ROUGHNESS=1.;
}
