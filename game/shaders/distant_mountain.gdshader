shader_type spatial;
render_mode unshaded,fog_disabled,cull_disabled;
uniform vec4 haze_color:source_color=vec4(.72,.82,.93,1.0);
uniform float distance_layer=0.0;
uniform float night_amount=0.0;
uniform float dusk_amount=0.0;
uniform vec3 sun_direction=vec3(.5,.7,.3);
uniform float ridge_x_center=0.0;
uniform float ridge_x_radius=3.5;
uniform float ridge_y_bottom=0.0;
varying vec3 ridge_normal;
varying float ridge_height;
void vertex(){
 // Reuse the complete cliff volume with a broad raised centre and buried
 // shoulders. Its original flat cliff ceiling otherwise reads as a wall.
 float across=(VERTEX.x-ridge_x_center)/max(ridge_x_radius,.001);
 float shoulder=pow(max(0.0,1.0-across*across),.72);
 VERTEX.y=ridge_y_bottom+(VERTEX.y-ridge_y_bottom)*(.12+.88*shoulder);
 ridge_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 ridge_height=(MODEL_MATRIX*vec4(VERTEX,1.0)).y;
 // Preserve perspective and real silhouette; pin depth behind the walkable
 // scene. Godot Forward+ uses reverse Z, Compatibility uses -1 near / +1 far.
 POSITION=PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(VERTEX,1.0);
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 POSITION.z=POSITION.w*.9999998;
 #else
 POSITION.z=POSITION.w*.0000001;
 #endif
}
void fragment(){
 float lit=smoothstep(.32,.40,dot(normalize(ridge_normal),normalize(sun_direction)));
 vec3 blue=mix(vec3(.23,.35,.39),vec3(.34,.46,.49),lit);
 blue=mix(blue,vec3(.50,.43,.57),dusk_amount*.35);
 blue=mix(blue,vec3(.075,.12,.22),night_amount*.82);
 float haze=.42+distance_layer*.16+(1.0-smoothstep(-12.0,45.0,ridge_height))*.15;
 vec3 atmosphere=mix(haze_color.rgb,vec3(.065,.12,.24),night_amount*.78);
 ALBEDO=mix(blue,atmosphere,haze);
}
