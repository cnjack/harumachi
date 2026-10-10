shader_type spatial;
render_mode diffuse_toon,specular_disabled;
uniform sampler2D albedo_tex:source_color,filter_linear_mipmap_anisotropic;
uniform sampler2D grain_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D weave_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform mat4 part_transform;
uniform vec4 albedo_color:source_color=vec4(1);
uniform int building_kind=0; // community, bakery, general store
varying vec3 p;
void vertex(){p=(part_transform*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec4 c=texture(albedo_tex,UV)*albedo_color;
 float timber=step(c.g*1.12,c.r)*step(c.b*1.06,c.g);
 float grain=dot(texture(grain_tex,vec2(p.x*.7,p.y*.65+p.z*.15)).rgb,vec3(.3,.59,.11));
 c.rgb*=1.+timber*(grain-.5)*.18;
 bool canvas_zone=p.z>2.5&&p.y>2.28&&p.y<3.12;
 float yellow=step(c.b*1.7,min(c.r,c.g));
 float green=step(c.r*1.08,c.g)*step(c.b*1.02,c.g);
 float pale=step(.64,min(min(c.r,c.g),c.b));
 float cloth=(building_kind==1?yellow:max(green,pale))*float(canvas_zone&&building_kind>0);
 float weave=dot(texture(weave_tex,p.xz*3.).rgb,vec3(.3,.59,.11));
 c.rgb*=1.+cloth*(weave-.6)*.16;
 ALBEDO=c.rgb;ROUGHNESS=1.;
}
