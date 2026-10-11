shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D wood_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform mat4 part_transform;
varying vec3 p;
void vertex(){p=(part_transform*vec4(VERTEX,1)).xyz;}
void fragment(){
 // Exact same old-arrow exclusion as direction_support; planting and masonry keep original UVs.
 if(p.y>1.28&&(abs(p.x+.174)>.105||abs(p.z+.119)>.12))discard;
 vec3 original=texture(albedo_tex,UV).rgb;
 bool post=abs(p.x+.174)<.105&&abs(p.z+.119)<.12&&p.y>.14;
 bool timber=original.r>original.g*1.08&&original.r>original.b*1.18;
 float fibre=dot(texture(wood_tex,vec2((p.x+p.z)*2.2,p.y*.75)).rgb,vec3(.2126,.7152,.0722));
 vec3 cedar=vec3(.60,.44,.29)*(1.+(fibre-.4)*.68);
 ALBEDO=post&&timber?mix(original,cedar,.62):original;
 ROUGHNESS=1.;SPECULAR=0.;
}
