shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

// =============================================================================
// Mistvale road surface — LEVEL ART PASS 02 (§17 ROAD PRODUCTION)
// =============================================================================
//
// WHAT THIS REPLACES: StandardMaterial3D + vertex colour only. That gave a
// large, flat, uniformly-lit pale wedge down every street. Measured: the main
// street read at rgb(161,161,160) — a 1% saturation grey slipway, not a road.
// The vertex stream could only bake one shade sample per vertex, and at
// ROAD_STEP the vertices are metres apart, so every metre of road between them
// was a flat interpolation of the same colour. It was never going to have
// texture; the data was not there to have it with.
//
// WHAT A ROAD ACTUALLY IS, AND WHAT THIS SHADER THEREFORE PUTS IN:
//   - two wheel ruts, compacted and damp, either side of the centre
//   - a dry crown down the middle, where water drains off
//   - grass and soil creeping in from BOTH verges, patchy, never a clean line
//   - fine gravel and aggregate speckle
//   - puddles in the hollows, dark and glossy
//   - wear smeared ALONG the direction of travel, not radially
//
// WHY THE VERTEX COLOUR IS STILL NEEDED: the road's base tint is per-road
// (main street / lane / footpath / mountain track all differ) and its alpha now
// carries `paved`, which decides how much of the above applies at all. A paved
// civic street has ruts and puddles; a mountain footpath has grass in the middle.
//
//   COLOR.rgb  the road's own earth tint (authored per road in mistvale_land.gd)
//   COLOR.a    paved 0..1 — 0 bare earth track, 1 setts/civic paving
//   UV.x       1 UV unit = 6 m ALONG the road
//   UV.y       0..1 ACROSS the road (0 and 1 are the verges)
//
// WHY COMPATIBILITY-SAFE: gl_compatibility (see BLACK_SCREEN_DIAGNOSIS.md). No
// screen texture, no depth texture, no SSAO. ALU plus the vertex stream only.

// --- Palette -----------------------------------------------------------------
// sRGB DISPLAY VALUES. `source_color` makes Godot convert these to linear
// before the shader runs; writing the linear values here converts them twice
// and the road comes back as asphalt. The comment is the linear target.
uniform vec3 rut_colour    : source_color = vec3(0.427, 0.376, 0.310); // 0.152 0.117 0.079
uniform vec3 crown_colour  : source_color = vec3(0.678, 0.612, 0.514); // 0.412 0.330 0.224
uniform vec3 verge_colour  : source_color = vec3(0.463, 0.553, 0.376); // 0.180 0.264 0.115
uniform vec3 soil_colour   : source_color = vec3(0.510, 0.435, 0.353); // 0.222 0.160 0.104
uniform vec3 gravel_colour : source_color = vec3(0.737, 0.686, 0.596); // 0.500 0.430 0.315
uniform vec3 puddle_colour : source_color = vec3(0.365, 0.400, 0.424); // 0.110 0.132 0.149
uniform vec3 sett_colour   : source_color = vec3(0.671, 0.643, 0.596); // 0.404 0.368 0.310

// How far in from the edge the grass owns the surface. A track is mostly grass
// with a worn line through it; a civic street is the opposite.
uniform float verge_width : hint_range(0.0, 0.6) = 0.26;
// Centre-to-edge position of the wheel ruts, in |across| units.
uniform float rut_at : hint_range(0.0, 0.9) = 0.34;
uniform float rut_width : hint_range(0.02, 0.5) = 0.17;

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec4 v_col;
varying vec2 v_uv;

// =============================================================================
// Noise — same family as the terrain shader so the two agree
// =============================================================================

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

float fbm2(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.03) * 0.35;
}

// =============================================================================

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_col = COLOR;
	v_uv = UV;
}

void fragment() {
	// across: 0 at the centre line, 1 at the verge. Symmetric — a road is
	// worn the same way on both sides.
	float across = abs(v_uv.y * 2.0 - 1.0);
	// metres along, from the UV the builder authored (1 unit = 6 m)
	float along = v_uv.x * 6.0;

	vec3 tint = v_col.rgb;
	float paved = clamp(v_col.a, 0.0, 1.0);

	// --- The three bands that make a road read as a road -------------------
	// Ruts: compacted, darker, and they hold water, so they are also smoother.
	float rut = smoothstep(rut_width, 0.04, abs(across - rut_at));
	// Crown: the dry, drained, slightly gravelly middle.
	float crown = smoothstep(rut_at + 0.10, 0.06, across);
	// Verge: the outer band, where the road loses to the ground around it.
	float verge = smoothstep(1.0 - verge_width, 0.995, across);

	// --- Wear smeared ALONG the road ---------------------------------------
	// The frequency in `along` is ~25x lower than in `across` on purpose:
	// traffic, rain and feet all move down the road, so the streaks have to be
	// stretched along it. Isotropic noise here reads as mould, not as wear.
	float smear = fbm2(vec2(along * 0.085, across * 5.2));
	float smear2 = vnoise(vec2(along * 0.031 + 11.0, across * 2.1));
	// Fine aggregate speckle: per-decimetre, and the thing that stops a road
	// being a smooth painted plane at eye height.
	float grit = vnoise(vec2(along * 2.1, across * 21.0));

	// --- Base ---------------------------------------------------------------
	vec3 base = tint;
	// Large-scale dry/muddy field: where the road is wet clay and where it has
	// dried to dust. One field, tens of metres across.
	//
	// LEVEL: the first version's spread averaged 0.84-1.18 and the road came
	// back at lum 84 against 90 for the ground beside it, i.e. darker than the
	// grass it runs through, which is the wrong read for a worn earth surface.
	// Centred on 1.0 and given less swing.
	base *= 1.01 + smear2 * 0.20;
	// Crown lifts and dries; ruts darken and pack. Both mixes are held well
	// under 1.0 — at 0.6 the crown turned a paved street into a neutral grey
	// slab and undid exactly the saturation this file exists to add.
	base = mix(base, crown_colour * (0.90 + grit * 0.22), crown * (0.26 + paved * 0.16));
	base = mix(base, rut_colour, rut * (0.48 - paved * 0.12));
	// Aggregate: fine light speckle concentrated on the crown and the ruts,
	// i.e. wherever traffic actually runs.
	float traffic = max(crown, rut);
	base = mix(base, gravel_colour, smoothstep(0.62, 0.95, grit) * traffic * 0.30);

	// --- Setts: a paved road is a SURFACE, not dirt with a tint -------------
	// A civic street has to be legibly different from a lane at eye height, and
	// §17 asks for it in material, not just in width. Cobble cells with mortar
	// gaps and a per-stone shade jitter: four ALU ops, no texture, and it is
	// the difference between "paved" and "pale".
	vec2 sc = vec2(along * 1.35, across * 6.5);
	vec2 cell = floor(sc);
	vec2 cf = fract(sc);
	float edge = min(min(cf.x, cf.y), min(1.0 - cf.x, 1.0 - cf.y));
	float mortar = 1.0 - smoothstep(0.03, 0.13, edge);
	float stone_shade = 0.86 + hash12(cell + 3.7) * 0.26;
	vec3 sett = sett_colour * stone_shade;
	sett = mix(sett, rut_colour * 0.80, mortar * 0.75);
	sett = mix(sett, gravel_colour, smoothstep(0.70, 0.96, grit) * 0.35);
	base = mix(base, sett, paved * (0.62 - traffic * 0.18));

	// --- Grass and soil creeping in from the verges -------------------------
	// THIS IS THE EDGE THAT GIVES IT AWAY WHEN IT IS MISSING. A road ribbon
	// ends on a mathematically clean line against the terrain, and no road on
	// earth does that. The intrusion is patchy and thresholded so it reads as
	// plants and scattered soil, not as a gradient.
	float creep = smoothstep(0.34, 0.72, fbm2(vec2(along * 0.42, across * 3.1)));
	float green = clamp(verge * creep * (1.0 - paved * 0.75), 0.0, 1.0);
	base = mix(base, verge_colour * (0.86 + grit * 0.28), green * 0.85);
	// Bare soil between the grass tufts and the worn surface.
	float bare = clamp(verge * (1.0 - creep) * 0.8, 0.0, 1.0);
	base = mix(base, soil_colour * (0.88 + grit * 0.22), bare * 0.7);

	// --- Puddles ------------------------------------------------------------
	// Only in the hollows (the ruts and the low side), and only on ground that
	// is not paved — setts drain, a clay track does not.
	float hollow = fbm2(vec2(along * 0.045 + 4.0, across * 1.7));
	float wet = smoothstep(0.60, 0.80, hollow) * (0.35 + rut * 0.65) * (1.0 - paved * 0.70);
	base = mix(base, puddle_colour, wet * 0.9);

	// --- Kill the CG cleanliness --------------------------------------------
	base *= 0.93 + grit * 0.16;
	base *= 0.96 + smear * 0.09;

	ALBEDO = base;

	// Roughness and specular follow the material, which is most of what sells
	// wet stone versus dry dust at a glance.
	float rough = 0.97;
	rough = mix(rough, 0.74, rut);               // packed damp
	rough = mix(rough, 0.90, crown);             // dry loose grit
	rough = mix(rough, 0.80, paved);             // worn stone, not soil
	rough = mix(rough, 0.16, wet);               // standing water
	float spec = 0.12;
	spec = mix(spec, 0.30, rut);
	spec = mix(spec, 0.24, paved);
	spec = mix(spec, 0.80, wet);
	ROUGHNESS = rough;
	SPECULAR = spec;
}
