// Opt-in POC: material detail changes reflectance, not the source silhouette.
#include "res://shaders/furniture_reflection.gdshaderinc"
varying float poc_roughness;
varying float poc_f0;

#include "res://shaders/material_poc_bump.gdshaderinc"

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.);
	// Two broad diffuse bands remain independent of the roughness map.
	float band = mix(.24, 1., smoothstep(.09, .19, facing));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band / 3.14159265;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * furniture_ggx(NORMAL, VIEW, LIGHT, poc_roughness, poc_f0);
}
