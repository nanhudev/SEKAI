shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;
//
// THE SOFT BAND — clouds, a water wall, the far side of a folding world.
//
// -----------------------------------------------------------------------------
// THREE PROTOTYPES WEAR THIS ONE MATERIAL, ON PURPOSE
// -----------------------------------------------------------------------------
//
//   07 星坠 / 10 锁链拖星  clouds that part and clouds that drift
//   05 海啸但水不动        the water wall that does NOT move
//   11 天地合页            the far page of the world
//
// They are the same problem: a very large, mostly-flat surface that has to read
// as DEPTH without ever having a hard edge, seen from the inside and the outside,
// at distances from 30m to 2km. A tiled texture would show its repeats at 2km and
// a mesh would need geometry nobody is going to model for a prototype.
//
// So it is procedural value noise at three scales, and the effect drives `tint`,
// `alpha`, `scale`, and `drift`.
//
// -----------------------------------------------------------------------------
// `alpha` IS WHAT MAKES IT WORK, AND IT IS THE THING TO GET WRONG
// -----------------------------------------------------------------------------
//
// A water wall at alpha 1.0 is a blue wall. At 0.35 with a bright rim it is a
// mass of water seen through its own spray. The effect sets it; the default here
// is low, because every one of the three wants something you can almost see
// through more than something you can see.

uniform vec3 tint : source_color = vec3(0.72, 0.78, 0.88);
uniform vec3 tint_deep : source_color = vec3(0.34, 0.42, 0.56);
uniform float alpha : hint_range(0.0, 1.0) = 0.35;
uniform float scale : hint_range(0.2, 60.0) = 6.0;
uniform float contrast : hint_range(0.0, 4.0) = 1.2;
uniform vec2 drift = vec2(0.0, 0.0);
// A horizon lift: 0 = flat billboard, 1 = dense at the bottom of the quad and
// thin at the top, which is what makes a cloud band sit in the sky.
uniform float bottom_weight : hint_range(0.0, 1.0) = 0.0;
// An additive rim so a wall of water has a visible near edge without a line.
uniform float rim : hint_range(0.0, 4.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(1.0, 1.0, 1.0);
// A fade at the band's own V=0 edge — for a sheet whose inner edge sits ON a
// hinge and must not be visible lying across the ground it is about to fold away
// from. Without this, a folded sky page at rest is an opaque sheet on the floor.
uniform float inner_fade : hint_range(0.0, 0.5) = 0.0;

varying vec2 band_uv;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}


void vertex() {
	band_uv = UV;
	// No `POSITION` write — see the note in `vfx_sky_dome.gdshader`. The band is
	// placed in the world and rendered where the effect put it.
}


void fragment() {
	vec2 p = band_uv * scale + drift;
	float n = fbm(p);
	float n2 = fbm(p * 3.1 + 7.0);
	float density = clamp((n * 0.75 + n2 * 0.35) * contrast, 0.0, 1.0);
	if (bottom_weight > 0.0) {
		density *= mix(1.0, clamp(band_uv.y, 0.0, 1.0), bottom_weight);
	}
	vec3 col = mix(tint_deep, tint, density);
	if (rim > 0.0) {
		float edge = 1.0 - smoothstep(0.0, 0.10, min(min(band_uv.x, 1.0 - band_uv.x),
			min(band_uv.y, 1.0 - band_uv.y)));
		col += rim_color * edge * rim;
	}
	float a = alpha * clamp(density * 1.6, 0.0, 1.0);
	if (inner_fade > 0.0) {
		a *= smoothstep(0.0, inner_fade, band_uv.y);
	}
	ALBEDO = col;
	EMISSION = col;
	ALPHA = a;
}
