shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

// =============================================================================
// Mistvale river surface — LEVEL ART PASS 02 (§C1)
// =============================================================================
//
// WHAT THIS REPLACES: nothing. Before this there was no water at all — the
// river was a carved ditch whose bed happened to sit at RIVER_Y, and the
// "river" a player saw was just terrain with a blue-ish vertex colour. The
// masterplan's Bridge landmark was, measurably, a road running through it.
//
// WHY THERE IS NO DEPTH TEXTURE: the project runs gl_compatibility, which has
// no reliable screen-space depth read in a spatial shader. So the depth does
// not come from the framebuffer — it is BAKED INTO THE VERTEX STREAM by
// mistvale_land.gd, which knows the bed height at every water vertex because it
// samples the same field the terrain is built from. That is both cheaper and
// more deterministic than reading depth back.
//
//   COLOR.r  depth   — 0 shallow at the bank, 1 deepest mid-channel
//   COLOR.g  flow    — 1 in the fast channel, 0 in the slack water at the edge
//   UV       uv      — metres / FLOW_TILE, so the pattern never stretches
//
// Flow is rendered by scrolling two normal "layers" at different rates and
// angles. Two layers rather than one because a single scrolling noise field
// reads as a moving texture; two beating against each other read as water.

// sRGB display values — see the palette note in mistvale_terrain.gdshader.
// These were the LINEAR values the water was designed in, sitting inside
// source_color uniforms and therefore darkened a second time on the way in.
// The trailing comment on each line is the linear albedo it produces.
uniform vec3 shallow_colour : source_color = vec3(0.395, 0.480, 0.470); // 0.130 0.198 0.190
uniform vec3 deep_colour    : source_color = vec3(0.223, 0.320, 0.365); // 0.040 0.085 0.112
uniform vec3 foam_colour    : source_color = vec3(0.773, 0.809, 0.809); // 0.560 0.620 0.620

// Metres per texture repeat. Larger = bigger, calmer ripples.
uniform float flow_tile : hint_range(2.0, 64.0) = 13.0;
uniform vec2  flow_speed = vec2(0.055, 0.018);

// How much the surface bends light. Water is not a mirror here — the masterplan
// asks for "believable but not photoreal".
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.45;
uniform float foam_at_bank    : hint_range(0.0, 1.0) = 0.55;

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec4 v_col;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// The ripple field. Returns a height and its gradient, so the normal can be
// tilted without a second, differently-seeded sample — using a different seed
// for the gradient makes the highlights detach from the ripples.
vec3 ripple(vec2 p) {
	float e = 0.35;
	float h  = vnoise(p);
	float hx = vnoise(p + vec2(e, 0.0));
	float hz = vnoise(p + vec2(0.0, e));
	return vec3(h, (hx - h) / e, (hz - h) / e);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_col = COLOR;
}

void fragment() {
	float depth = clamp(v_col.r, 0.0, 1.0);
	float flow  = clamp(v_col.g, 0.0, 1.0);
	float t = TIME;

	// Two layers, opposite drift, beating against each other.
	vec2 uv = w_pos.xz / flow_tile;
	vec3 a = ripple(uv + vec2(flow_speed.x, flow_speed.y) * t);
	vec3 b = ripple(uv * 1.9 + vec2(-flow_speed.y * 1.6, flow_speed.x * 0.7) * t + 11.3);

	vec3 r = a * 0.62 + b * 0.38;
	// Moving water has crests where the two layers agree; that is the foam.
	float crest = clamp((a.x * 0.6 + b.x * 0.4 - 0.52) * 4.0, 0.0, 1.0);
	crest *= 0.35 + flow * 0.65;

	// --- Colour ------------------------------------------------------------
	// Shallow banks go green-brown; the channel goes cold and dark. This
	// gradient is most of what tells the eye the water has a bed under it.
	//
	// The ramp was 0.05..0.85 and the river came back PALE: most of its
	// surface never got past the shallow end, so what the player saw was a
	// uniform light plane whatever the depth. Compressed to 0.02..0.55 — the
	// channel darkens while it is still well short of the deepest bed it has,
	// which is what a river actually looks like from the bank.
	vec3 col = mix(shallow_colour, deep_colour, smoothstep(0.02, 0.55, depth));

	// --- Bank foam ---------------------------------------------------------
	// Water arriving at a bank over gravel is not smooth. Foam where the water
	// is shallow AND the ripple field is cresting.
	float bank = 1.0 - smoothstep(0.0, 0.30, depth);
	float foam = bank * foam_at_bank * smoothstep(0.42, 0.85, a.x * 0.5 + b.x * 0.5);
	foam += crest * 0.22 * flow;
	col = mix(col, foam_colour, clamp(foam, 0.0, 0.75));

	col *= 1.0 - ripple_strength * 0.155 + r.x * ripple_strength * 0.36;
	ALBEDO = col;

	// --- Ripple, through ALBEDO and ROUGHNESS. THERE IS NO NORMAL WRITE. -----
	//
	// This file used to perturb NORMAL with the ripple gradient. It never did
	// anything, and it did worse than nothing: assigning NORMAL in the fragment
	// stage under gl_compatibility takes the surface OFF the directional light
	// and leaves it on the sky ambient alone. So since the day this was
	// written, the river has been lit by blue ambient and nothing else — which
	// is exactly what it looked like: a flat pale plane with no sun on it at
	// any angle, at any time of day. See mistvale_terrain.gdshader for the
	// three-step measurement that established the constraint.
	//
	// The ripple therefore has to show through the two channels this renderer
	// does honour. A crest is lighter and glossier, a trough darker and duller,
	// and because the two ripple layers drift at different rates the pattern
	// still MOVES — which is the whole job.
	//
	// The grazing term is now built from the camera's world position rather
	// than from a slice of VIEW_MATRIX multiplied against a world-space normal.
	// The old expression mixed spaces and only looked right because the water
	// was unlit.
	vec3 to_eye = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - w_pos);
	float horizon = 1.0 - clamp(abs(to_eye.y), 0.0, 1.0);

	// Water is smooth where it is deep and still, dull where it is shallow and
	// broken, and both are more mirror-like at a glancing angle.
	ROUGHNESS = mix(0.34, 0.06, smoothstep(0.2, 0.8, depth)) + crest * 0.20;
	ROUGHNESS += clamp((r.x - 0.5) * 0.6, -0.18, 0.18);
	ROUGHNESS = clamp(ROUGHNESS - horizon * 0.05, 0.03, 0.65);

	// SPECULAR WAS 0.65 AND THAT WAS A WHITE SHEET.
	//
	// `specular_schlick_ggx` with specular 0.65 on a surface at roughness 0.05
	// is a mirror, and under gl_compatibility there is no environment to
	// reflect — so what it reflects is the ambient term, amplified. Measured on
	// the r2 walk at d=240 (on the bridge, looking down the river): the water
	// at grazing angle came back as a near-white plane and the river vanished
	// entirely, on the one frame in the whole walk where the river is the
	// subject. A river should be dark and legible at every angle; a specular
	// highlight is a garnish, not the dish.
	SPECULAR = clamp(0.40 - horizon * 0.24 + crest * 0.10 + r.x * 0.06, 0.06, 0.5);
	METALLIC = 0.0;
}
