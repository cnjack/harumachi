// Matches LakesideLayout; terrain, water, collisions and maps share these contours.
float river_z(float x) {
    float t=clamp((x-28.0)/46.0,0.0,1.0);
    float anchor=smoothstep(4.0,13.0,abs(x));
    float meander=(1.7*sin(x*.11)+.5*sin(x*.24-.6))*anchor*(1.0-smoothstep(28.0,48.0,x));
    return 17.0+meander+8.0*sin(t*3.14159265)*smoothstep(28.0,40.0,x)+t;
}
float river_half(float x) {
    float anchor=smoothstep(4.0,13.0,abs(x));
    return 3.0+.75*sin(clamp((x-28.0)/46.0,0.0,1.0)*3.14159265)+(.38*sin(x*.17)+.22*cos(x*.07))*anchor;
}
float lake_radius(float a) { return 1.0+.095*sin(a*3.0)+.055*cos(a*5.0)+.035*sin(a*7.0); }
float water_distance(vec2 q) {
    vec2 v=(q-vec2(101,18))/vec2(32,23);
    float lake=(length(v)-lake_radius(atan(v.y,v.x)))*23.0;
    float river=abs(q.y-river_z(q.x))-river_half(q.x);
    if(q.x>74.0)river=length(q-vec2(74,18))-3.0;
    return min(lake,river);
}
float water_depth_at(vec2 q) {
    float lake_weight=smoothstep(74.0,92.0,q.x);
    return .14+(1.05+1.25*lake_weight)*smoothstep(0.0,3.2+10.0*lake_weight,max(0.0,-water_distance(q)));
}
vec2 flow_direction(vec2 q) {
    float slope=(river_z(q.x+.12)-river_z(q.x-.12))/.24;
    return normalize(vec2(1,slope));
}
