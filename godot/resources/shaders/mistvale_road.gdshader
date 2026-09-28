shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

// =============================================================================
// Mistvale road surface — LEVEL ART PASS 03 (§6–§8 PATH AS REAL SURFACE)
// =============================================================================
//
// WHAT THIS REPLACES: LEVEL ART PASS 02's road, which had correct ZONE LOGIC
// (ruts, crown, verge, creep, puddles) wrapped around one fatal element — a
// SETT PATTERN THAT DREW GRAPH PAPER.
//
// PASS 02 used `floor()` cells plus a min-of-fract orthogonal "edge" distance.
// That is a lattice: perfectly straight, constant-width, exact-pitch, and it
// covered the full width of the widest road on the map at 0.75 x 0.55 m. The
// main street is paved = 0.85, so the paving blend came out around 0.53 across
// the entire carriageway. Measured from the p19 walk sheet: at d=50 and d=370
// the bottom two thirds of the frame was lattice, and at d=470 the street
// running up to the north gate was lattice. It was the single most obvious CG
// artefact in the region — ahead of the trees, ahead of the buildings.
//
// WHAT CHANGED IN PASS 03:
//
//   1. STONES ARE ROUNDED, JITTERED AND STAGGERED, not a lattice. See
//      stone_layer() — the gap between two stones is an irregular pocket, not
//      a drawn line. Two layers at unrelated scales so the eye finds no pitch.
//   2. PAVING IS PATCHY AND IS A MINORITY OF THE SURFACE. A worn town street is
//      packed earth with stones surfacing through it, not a laid floor. The
//      paving is gated by a metres-scale field, so long stretches are earth.
//   3. THE PATTERN FADES WITH DISTANCE via fwidth, so a cobble is only drawn
//      where a pixel is smaller than a cobble. This both kills the shimmer and
//      stops a distant street reading as a grid.
//   4. THE GAPS ARE FILLED WITH THE ROAD'S OWN EARTH, not a dark line.
//
// WHAT A ROAD ACTUALLY IS, AND WHAT IS STILL IN HERE:
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
uniform vec3 verge_colour  : source_color = vec3(0.440, 0.610, 0.350); // 0.163 0.330 0.103
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
// Stones from the centre to the verge on a paved street. 11 at the main
// street's 3.6 m half-width is a ~0.33 m sett, which is the size a person
// actually steps on. PASS 02's 6.5 gave 0.55 m flagstones.
uniform float sett_across : hint_range(4.0, 24.0) = 11.0;
uniform float sett_along : hint_range(1.0, 6.0) = 2.4;
// Metres of road a single pixel may span before the sett pattern is dropped.
// Below this the stones are resolved; above it they would shimmer, and a
// distant street must not read as a grid.
uniform float sett_pixel_fade : hint_range(0.05, 0.6) = 0.22;
// NO `detail_normal` UNIFORM. The road's detail field is an albedo occlusion,
// not a normal — assigning NORMAL in the fragment stage takes the surface off
// the directional light under gl_compatibility. See mistvale_terrain.gdshader
// for the three-step measurement that established it.

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
// Stones
// =============================================================================
//
// ROUNDED, JITTERED, STAGGERED — deliberately NOT `floor()` plus min-of-fract.
//
// A jitter of ±0.62 of half a cell is larger than the cell margin on purpose:
// it lets a stone reach across into its neighbour's territory, so the
// remaining gaps are irregular pockets. Combined with a radial distance test
// and a per-stone radius, the result has no straight lines and no constant
// pitch — which is the entire difference between "a road with stones in it"
// and "graph paper".
//
// Returns 0 in the gap, 1 on the surface of a stone.
float stone_layer(vec2 p, float seed) {
	vec2 cell = floor(p);
	vec2 cf = fract(p);
	vec2 jit = vec2(hash12(cell + seed), hash12(cell + seed + 41.7)) - 0.5;
	float rad = 0.42 + hash12(cell + seed + 17.3) * 0.24;
	vec2 d = (cf - 0.5 - jit * 0.62) / rad;
	return 1.0 - smoothstep(0.62, 1.0, length(d));
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

	// --- Anti-alias gate ----------------------------------------------------
	// How many metres of road one pixel covers, along the road. A sett is a
	// third of a metre: past roughly that, drawing one is drawing noise.
	float mpp = fwidth(along);
	float resolved = 1.0 - smoothstep(sett_pixel_fade * 0.45, sett_pixel_fade, mpp);

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
	base *= 1.01 + smear2 * 0.20;
	// Crown lifts and dries; ruts darken and pack. Both mixes are held well
	// under 1.0 — at 0.6 the crown turned a paved street into a neutral grey
	// slab and undid exactly the saturation this file exists to add.
	base = mix(base, crown_colour * (0.90 + grit * 0.22), crown * (0.24 + paved * 0.14));
	base = mix(base, rut_colour, rut * (0.44 - paved * 0.10));

	// Aggregate: fine light speckle concentrated on the crown and the ruts,
	// i.e. wherever traffic actually runs.
	float traffic = max(crown, rut);
	base = mix(base, gravel_colour, smoothstep(0.62, 0.95, grit) * traffic * 0.26);

	// --- Stones worn into the earth ----------------------------------------
	// Two layers whose scales do not divide into each other, so there is no
	// single pitch for the eye to find.
	float s_coarse = stone_layer(vec2(along * sett_along, across * sett_across), 0.0);
	float s_fine = stone_layer(vec2(along * sett_along * 2.13 + 7.0,
	                                across * sett_across * 2.07 + 21.0), 5.5);
	float stones = clamp(s_coarse * 0.90 + s_fine * 0.30, 0.0, 1.0);

	// WHERE THE PAVING SURVIVES.
	// A street is not uniformly laid, and this is the difference between a
	// road and a floor covering. One metres-scale field decides which parts of
	// the carriageway still carry their stones and which have been worn back
	// to packed earth. Weighted so that even on the main street the earth is
	// the majority of the surface.
	float survives = smoothstep(0.30, 0.62, fbm2(vec2(along * 0.105 + 21.0, across * 0.85)));
	float pave = paved * survives * resolved * (1.0 - traffic * 0.30);
	// Per-stone shade, so a course is never one flat colour — but a SMALL
	// shade. At +/-15% the first PASS 03 render of the market square came back
	// as a patchwork quilt: the slabs separated into light and dark tiles and
	// the eye read them as loose, badly laid flags rather than as worn paving.
	// Paving ages toward one value with a hue wobble; it does not check.
	float stone_shade = 0.93 + hash12(floor(vec2(along * sett_along, across * sett_across)) + 8.3) * 0.13;
	vec3 sett = sett_colour * stone_shade;
	// THE GAPS ARE THE ROAD'S OWN EARTH, NOT A DRAWN LINE. PASS 02 mixed the
	// gaps 75% toward rut_colour * 0.80, which is nearly black — that is what
	// made the lattice legible as a drawing rather than as a surface.
	sett = mix(tint * 0.96, sett, stones);
	sett = mix(sett, gravel_colour, smoothstep(0.70, 0.96, grit) * 0.26);
	base = mix(base, sett, pave * 0.48);

	// LOOSE STONES SURFACING THROUGH THE EARTH.
	// Present on every road, paved or not: these are the stones that were
	// never walked away, and they are most of what tells the eye the surface
	// is mineral rather than painted.
	float loose = smoothstep(0.78, 0.99, s_fine) * (1.0 - pave * 0.5);
	base = mix(base, gravel_colour * (0.80 + grit * 0.30), loose * resolved * (0.11 + paved * 0.09));

	// --- Grass and soil creeping in from the verges -------------------------
	// THIS IS THE EDGE THAT GIVES IT AWAY WHEN IT IS MISSING. A road ribbon
	// ends on a mathematically clean line against the terrain, and no road on
	// earth does that. The intrusion is patchy and thresholded so it reads as
	// plants and scattered soil, not as a gradient.
	//
	// PASS 03 widens the intrusion: the recession of the grass is itself
	// irregular, so the boundary wanders in and out by a metre or two.
	float edge_wander = 0.055 + fbm2(vec2(along * 0.24 + 3.0, across * 1.4)) * 0.10;
	float creep = smoothstep(0.30, 0.70, fbm2(vec2(along * 0.42, across * 3.1)));
	float green = clamp(smoothstep(1.0 - edge_wander, 0.999, across) * creep * (1.0 - paved * 0.72), 0.0, 1.0);
	base = mix(base, verge_colour * (0.86 + grit * 0.28), green * 0.85);
	// Bare soil between the grass tufts and the worn surface.
	float bare = clamp(smoothstep(1.0 - edge_wander * 1.9, 0.999, across) * (1.0 - creep) * 0.8, 0.0, 1.0);
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
	// Small height variation, faked in albedo: a road is never one plane, and
	// the low-frequency term below is the cheapest read of "the ground under
	// this is not flat" that survives at compatibility settings.
	float undulate = vnoise(vec2(along * 0.19 + 31.0, across * 0.9));
	base *= 0.955 + undulate * 0.10;

	ALBEDO = base;
	// NO NORMAL WRITE HERE — see mistvale_terrain.gdshader for the measurement.
	// Assigning NORMAL in the fragment stage removes the surface from the
	// directional light entirely under gl_compatibility; the detail field is
	// used as an albedo occlusion instead, just below.
	base *= 0.94 + (vnoise(w_pos.xz * 2.85) * 0.6 + vnoise(w_pos.xz * 7.10) * 0.4) * 0.12;
	ALBEDO = base;

	// Roughness and specular follow the material, which is most of what sells
	// wet stone versus dry dust at a glance.
	float rough = 0.97;
	rough = mix(rough, 0.74, rut);               // packed damp
	rough = mix(rough, 0.90, crown);             // dry loose grit
	rough = mix(rough, 0.80, paved * survives);  // worn stone, not soil
	rough = mix(rough, 0.16, wet);               // standing water
	float spec = 0.12;
	spec = mix(spec, 0.30, rut);
	spec = mix(spec, 0.24, paved * survives);
	spec = mix(spec, 0.80, wet);
	ROUGHNESS = rough;
	SPECULAR = spec;
}
