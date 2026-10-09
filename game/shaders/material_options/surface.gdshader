shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;
#include "res://shaders/lakeside_shape.gdshaderinc"
uniform bool landscape_contours=false;
uniform vec3 terrain_origin=vec3(700,0,0);
uniform int surface_kind = 0; // dirt, sand, wood, stone, grass soil
uniform vec4 base_color : source_color = vec4(.67,.53,.33,1);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_paint = false;
uniform float tile = 2.6;
varying vec3 wp;
float hash(vec2 q) { return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 q) { vec2 i=floor(q),f=fract(q);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y); }
vec2 stone_cell(vec2 p) {
    vec2 i=floor(p),f=fract(p);float nearest=99.;float second=99.;float identity=0.;
    for(int x=-1;x<=1;x++)for(int y=-1;y<=1;y++) {
        vec2 n=vec2(float(x),float(y));vec2 point=n+.20+.60*vec2(hash(i+n),hash(i+n+17.));
        float distance_value=length(point-f);
        if(distance_value<nearest){second=nearest;nearest=distance_value;identity=hash(i+n+3.7);}else second=min(second,distance_value);
    }
    return vec2(second-nearest,identity);
}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
    vec2 p=wp.xz;vec2 uv=p/tile;vec3 col=base_color.rgb;
    float macro=floor(noise(p*.65)*3.)/3.;col*=.94+macro*.10;
    if(use_paint)col=texture(albedo_tex,uv).rgb*base_color.rgb;
    if(surface_kind==0){if(!use_paint)col*=.96+floor(noise(p*2.7)*4.)*.012;}
    else if(surface_kind==1){if(!use_paint)col*=.96+step(.4,sin(p.x*5.+sin(p.y*1.7)))*.035;}
    else if(surface_kind==2){
        vec2 wood_uv=vec2(p.x*.8,p.y/tile);
        if(use_paint)col=texture(albedo_tex,wood_uv).rgb*base_color.rgb;
        float board=fract(p.x/.21);float seam=1.-smoothstep(.012,.025,min(board,1.-board));
        col*=1.-seam*.27;
        if(!use_paint)col*=.95+floor(noise(vec2(p.x*45.,p.y*1.3))*4.)*.022;
    } else if(surface_kind==3){
        vec2 stone=stone_cell(p/.78);float seam=1.-smoothstep(.012,.038,stone.x);
        col*=.91+stone.y*.16;col=mix(col,vec3(.31,.30,.27),seam*.43);
    } else {col*=.91+macro*.20;}
    if(landscape_contours){
        float shore=water_distance(wp.xz-terrain_origin.xz);
        float exposed=1.0-smoothstep(-.35,.7,shore);
        vec3 bed=mix(vec3(.34,.31,.23),vec3(.49,.45,.33),floor(noise(p*3.7)*3.)/3.);
        col=mix(col,bed,exposed);
    }
    ALBEDO=col;ROUGHNESS=1.;SPECULAR=0.;
}
