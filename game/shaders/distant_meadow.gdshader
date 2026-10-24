shader_type spatial;
render_mode diffuse_toon,specular_disabled;
#include "res://shaders/meadow_colour.gdshaderinc"
varying vec3 meadow_world;
void vertex(){meadow_world=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 ALBEDO=meadow_colour(meadow_world.xz);ROUGHNESS=1.;
}
