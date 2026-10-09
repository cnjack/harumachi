shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;
uniform float animation_time = -1.0;
global uniform float wind_strength;
global uniform vec2 wind_direction;
uniform float wind_scale = 1.0;
uniform float height_scale = 1.0;
global uniform vec4 grass_push;
uniform vec3 root_col : source_color = vec3(0.10,0.26,0.09);
uniform vec3 fresh_col : source_color = vec3(0.56,0.78,0.23);
uniform vec3 deep_col : source_color = vec3(0.18,0.48,0.21);
uniform float brightness = 1.0;
uniform float dry_amount = 0.03;
varying float blade_height;
varying float blade_random;
varying float wind_band;
varying vec3 world_pos;
void vertex() {
    float clock_value = animation_time >= 0.0 ? animation_time : TIME;
    VERTEX.y *= height_scale;
    blade_height = UV.y;
    blade_random = COLOR.r;
    vec3 p = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    float band = pow(sin(dot(p.xz,normalize(wind_direction))*2.2-clock_value*1.8)*.5+.5,2.0);
    float flutter = sin(clock_value*4.0+COLOR.g*6.283+p.x*1.8);
    float bend = (.12+band*.34+flutter*.06)*wind_strength*wind_scale*UV.y*UV.y;
    vec3 disp = vec3(normalize(wind_direction).x,0,normalize(wind_direction).y)*bend*.20;
    vec3 away = p-grass_push.xyz;
    away.y=0.0;
    float distance_value = length(away);
    float push = (1.0-smoothstep(grass_push.w*.25,grass_push.w,distance_value))*UV.y;
    disp += away/max(distance_value,.001)*push*.19;
    disp.y -= length(disp.xz)*.42;
    VERTEX += (inverse(MODEL_MATRIX)*vec4(disp,0.0)).xyz;
    world_pos = p+disp;
    wind_band = band;
    NORMAL = vec3(0,1,0);
}
void fragment() {
    float patch = sin(world_pos.x*1.3+world_pos.z*.4)*cos(world_pos.z*1.1-world_pos.x*.4)*.5+.5;
    vec3 tip = mix(deep_col,fresh_col,smoothstep(.18,.85,patch));
    vec3 color = mix(root_col,tip,pow(blade_height,.58));
    color *= .94+blade_random*.12;
    color += vec3(.035,.045,.012)*wind_band*blade_height;
    ALBEDO = color*brightness;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
