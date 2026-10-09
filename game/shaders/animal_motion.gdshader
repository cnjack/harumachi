shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color=vec4(1.0);
uniform bool has_texture=false;
uniform int animal_kind=0;
uniform float body_height=.35;
uniform float phase=0.0;
uniform float head_yaw=0.0;
uniform float peck=0.0;
varying vec3 local_position;
void vertex() {
	local_position=VERTEX;
	float h=max(body_height,.01);
	float head=smoothstep(h*.62,h*.77,VERTEX.y);
	vec3 pivot=vec3(0,h*.64,0);
	vec3 v=VERTEX-pivot;
	float turn=head_yaw*head;
	if(animal_kind==0){
		float angle=peck*head*.65;
		VERTEX.y=pivot.y+cos(angle)*v.y-sin(angle)*v.z;
		VERTEX.z=pivot.z+sin(angle)*v.y+cos(angle)*v.z;
	}else if(animal_kind==1){
		VERTEX.x=cos(turn)*v.x+sin(turn)*v.z;
		VERTEX.z=-sin(turn)*v.x+cos(turn)*v.z;
		float ears=smoothstep(h*.86,h*.97,VERTEX.y);
		float flick=pow(max(0.0,sin(phase*.74)),18.0)*sin(phase*17.0);
		VERTEX.x+=flick*ears*h*.025;
	}
	// Only the torso expands. Paw and wall contact vertices remain in place.
	float chest=smoothstep(h*.16,h*.36,local_position.y)*(1.0-smoothstep(h*.62,h*.80,local_position.y));
	float breath=sin(phase*(1.5+float(animal_kind)*.2));
	VERTEX.y+=chest*h*.012*breath;
	VERTEX.x+=local_position.x*chest*.008*breath;
}
void fragment(){
	vec4 source=albedo_color*(has_texture?texture(albedo_tex,UV):vec4(1));
	if(source.a<.1)discard;
	ALBEDO=source.rgb;ROUGHNESS=1.0;
}
