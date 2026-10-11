shader_type spatial;
render_mode blend_mix,depth_draw_never,diffuse_toon,specular_disabled,cull_disabled;
// Selected B palette is applied by MaterialChoiceProfile; use the same real water surface.
#include "res://shaders/lakeside_water_surface.gdshaderinc"
