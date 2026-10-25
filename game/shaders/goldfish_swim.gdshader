shader_type canvas_item;
uniform float swim_phase = 0.0;
uniform float effort = 1.0;
uniform float bend = 0.0;
varying vec4 fish_tint;
void vertex() {
	fish_tint = COLOR;
	// Extra transparent room lets the tail move outside the original sprite box.
	VERTEX *= vec2(1.16, 1.40);
}
void fragment() {
	vec2 uv = (UV - .5) * vec2(1.16, 1.40) + .5;
	float tail = 1.0 - smoothstep(.18, .72, uv.x);
	float stroke = sin(swim_phase + uv.x * 6.0);
	uv.y += tail * (stroke * (.025 + .040 * effort) + bend * (.8 - uv.x));
	// The head stays anchored while the body and trailing fins flex.
	uv.x += tail * sin(swim_phase + 1.1) * .008 * effort;
	vec4 fish = texture(TEXTURE, clamp(uv, vec2(0.), vec2(1.)));
	if (any(lessThan(uv, vec2(0.))) || any(greaterThan(uv, vec2(1.)))) { fish.a = 0.; }
	COLOR = fish * fish_tint;
}
