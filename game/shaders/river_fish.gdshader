shader_type spatial;
render_mode diffuse_toon,specular_disabled,cull_disabled;
uniform vec4 body_color:source_color=vec4(.41,.48,.37,1.0);
uniform float phase=0.0;
uniform float night_amount=0.0;
void vertex(){
 float tail=smoothstep(.015,.095,-VERTEX.x);
 VERTEX.z+=sin(TIME*7.0+phase+VERTEX.x*11.0)*.014*tail;
}
void fragment(){
 ALBEDO=body_color.rgb*mix(1.0,.58,night_amount);
 ROUGHNESS=1.0;
}
