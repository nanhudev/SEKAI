shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

// =============================================================================
// Mistvale region terrain — LEVEL ART PASS 02 (§A2 / §A3)
// =============================================================================
//
// WHAT THIS REPLACES: a vertex-coloured StandardMaterial3D. That gave one flat
// grey-green sheet everywhere, which is the single biggest reason the region
// read as a greybox even though the height field was already real.
//
// HOW IT DECIDES WHAT THE GROUND IS: from the surface itself, per pixel —
// its steepness and its height — plus two things baked into the vertex colour
// that the mesh builder knows and the shader cannot infer:
//
//   COLOR.r  wear        — pack/road paint strength (MistvaleHeights.path_factor)
//   COLOR.g  settlement  — settled footprint (MistvaleHeights.settlement_factor)
//   COLOR.b  vary        — a large-scale variation seed so two meadows are not
//                          the same meadow
//
// WHY COMPATIBILITY-SAFE: the project runs gl_compatibility (see the black
// screen diagnosis — Forward+ black-screens on this GPU). So: no screen
// texture, no depth texture, no SSAO/SSIL reads, no compute. Everything here is
// ALU + the vertex stream.
//
// WHY NO TEXTURES: procedural value noise costs a few hundred ALU per pixel and
// needs zero imports, zero .import churn and zero texture memory. At the
// distances this terrain is viewed from, tiling and mip shimmer are a bigger
// risk than noise cost. Textures can replace the noise functions later without
// touching the zone logic.

// --- Palette -----------------------------------------------------------------
// Albedo, not final art. Per masterplan §13: warm, lived-in settlement low on
// the valley; progressively colder and more desaturated toward the ruins.
//
// THESE ARE sRGB DISPLAY VALUES, AND THAT IS THE WHOLE POINT OF THE NUMBERS.
// `source_color` means Godot converts each uniform from sRGB to linear before
// the shader sees it. The first version of this file held the LINEAR values the
// palette was designed in (grass_low was vec3(0.190, 0.285, 0.135)) inside
// source_color uniforms, so every colour was converted a second time and the
// ground came back at a linear albedo of 0.03-0.05. The measured symptom: the
// trees, lit by the same sun in the same frame, were bright green, and the
// ground under them was black. It is not a lighting bug, it is arithmetic.
//
// The comment beside each line is the linear albedo it is meant to produce.
// ART DIRECTION: STYLIZED NEXT-GEN ANIME FANTASY — COLOR GROUPING.
//
// The PASS 02/03 palette was designed to be "restrained", and restraint was
// implemented as DESATURATION. Every value below sat within a few percent of
// neutral, so the measured Hero Frame at d=470 was a single mass of grey-green
// / grey-brown / grey-blue and the eye had nothing to group. Read at 25% (the
// thumbnail test, see PART K) that frame was one field of noise — no road, no
// grass mass, no rock, no town.
//
// The rule now: SATURATION SEPARATES THE MASSES, VALUE AND TEXTURE SEPARATE
// THE PIXELS. Grass is a real green, soil and road are real warm earth, stone
// is a neutral with a slight hue bias, the town floor is genuinely PALE. What
// stays restrained is the RANGE — nothing here is a saturated hue — and the
// amount of per-pixel variation, which is what actually made the old ground
// read as dirty rather than as designed.
//
// Each colour keeps the sRGB-display / linear-albedo comment pair, because the
// double-conversion bug recorded above is one edit away at all times.
uniform vec3 grass_low   : source_color = vec3(0.440, 0.620, 0.350); // 0.163 0.342 0.100  fresh muted green
uniform vec3 grass_dry   : source_color = vec3(0.660, 0.630, 0.400); // 0.393 0.355 0.133  warm straw
uniform vec3 soil        : source_color = vec3(0.545, 0.455, 0.365); // 0.258 0.175 0.110  warm earth
uniform vec3 road_dirt   : source_color = vec3(0.645, 0.560, 0.455); // 0.374 0.274 0.175  packed warm dust
uniform vec3 gravel      : source_color = vec3(0.650, 0.645, 0.630); // 0.380 0.374 0.355  cool pale wash
uniform vec3 rock        : source_color = vec3(0.565, 0.552, 0.530); // 0.278 0.264 0.242  warm neutral stone
uniform vec3 cliff       : source_color = vec3(0.492, 0.492, 0.508); // 0.207 0.207 0.222  cool neutral stone
uniform vec3 town_floor  : source_color = vec3(0.660, 0.645, 0.610); // 0.393 0.374 0.330  PALE town paving
uniform vec3 ruins_floor : source_color = vec3(0.537, 0.558, 0.577); // 0.250 0.272 0.292
uniform vec3 wet_dark    : source_color = vec3(0.373, 0.378, 0.381); // 0.115 0.118 0.120

// --- Zone thresholds ---------------------------------------------------------
// Slopes in "1 - normal.y" units, NOT degrees. 0.30 is about 46 deg, which is
// where rock starts showing through; 0.62 is about 73 deg, bare cliff.
uniform float rock_lo  : hint_range(0.0, 1.0) = 0.30;
uniform float rock_hi  : hint_range(0.0, 1.0) = 0.62;

uniform float water_y  : hint_range(-50.0, 50.0) = 6.0;
// The town reads as a warm paved shelf from this height band south of here.
uniform float town_lo  : hint_range(-50.0, 150.0) = 17.0;
// Above this the ground belongs to the ruins: cold, pale, no grass.
uniform float ruins_lo : hint_range(0.0, 250.0) = 120.0;

// --- Detail normal — REMOVED --------------------------------------------------
// There is no strength uniform for the detail field, because there is no normal
// write. See the long note at the detail block in fragment(): assigning NORMAL
// in the fragment stage removes the surface from the directional light under
// gl_compatibility, verified with a no-perturbation control. The detail field is
// used as an albedo occlusion instead.

// --- Vertex streams ----------------------------------------------------------
varying vec3 w_pos;
varying vec3 w_nrm;
// vec4, not vec3: COLOR is a vec4 in the spatial vertex stage and assigning it
// to a vec3 varying is a compile error, not a silent truncation.
varying vec4 v_col;

// =============================================================================
// Noise
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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// Two octaves only. At the frequencies this is used at — the 1-6 m band — four
// octaves put the finest one below 0.3 m, which is finer than a pixel at any
// distance past a few metres and turns the ground into shimmer instead of
// texture. Two octaves stays resolvable.
float fbm2(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.03) * 0.35;
}

// Irregular rounded slabs. Same construction as the road shader's stone_layer,
// and for the same reason: `floor()` plus min-of-fract draws a lattice, and a
// lattice on the ground is the "程序生成" tell this whole pass exists to
// remove. See mistvale_road.gdshader for the full argument.
//
// Used here for the SETTLEMENT ground — the one place on the map where the
// ground itself is supposed to be man-made.
float slab_layer(vec2 p, float seed) {
	vec2 cell = floor(p);
	vec2 cf = fract(p);
	vec2 jit = vec2(hash12(cell + seed), hash12(cell + seed + 41.7)) - 0.5;
	float rad = 0.44 + hash12(cell + seed + 17.3) * 0.22;
	vec2 d = (cf - 0.5 - jit * 0.60) / rad;
	return 1.0 - smoothstep(0.64, 1.0, length(d));
}

// =============================================================================
// Vertex
// =============================================================================

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_col = COLOR;
}

// =============================================================================
// Fragment
// =============================================================================

void fragment() {
	vec3 n = normalize(w_nrm);
	float steep = clamp(1.0 - n.y, 0.0, 1.0);
	float h = w_pos.y;

	float wear = clamp(v_col.r, 0.0, 1.0);
	float town = clamp(v_col.g, 0.0, 1.0);
	float vary = v_col.b;

	// --- Scale stack --------------------------------------------------------
	// THE PASS 02 BUG WAS A MISSING SCALE BAND, NOT A WEAK ONE.
	//
	// It had `macro` at 0.012 (an 83 m period) and `micro` at 0.34 (a 3 m
	// period) and NOTHING IN BETWEEN. Everything the eye actually reads
	// between 4 and 40 m — the scale at which a field falls off, at which a
	// patch of bare earth sits in a meadow, at which litter gathers in a
	// hollow — was absent. So every hectare of the valley averaged to the same
	// colour, and the ground came back as one flat sheet of paint with soft
	// mounds in it. That, not the mesh, is what "程序生成 Greybox" means at
	// eye height: not lack of detail, lack of STRUCTURE.
	//
	// Five bands, each roughly 3-4x the frequency of the one above, so no two
	// of them beat against each other at a visible pitch.
	float landmark = fbm(w_pos.xz * 0.0062 + vary * 9.0);   // ~160 m  valley character
	float field    = fbm(w_pos.xz * 0.0271 + 3.1);          // ~37 m   field to field
	float patch    = fbm(w_pos.xz * 0.0854 + vary * 9.0);   // ~12 m   THE MISSING BAND
	float clump    = fbm2(w_pos.xz * 0.263 + 5.7);          // ~3.8 m  tufts, litter
	float litter   = fbm2(w_pos.xz * 0.86 + 13.0);          // ~1.2 m  near field

	// --- Grass -------------------------------------------------------------
	// Drier and greyer as it climbs; the valley floor is the humid green.
	//
	// The mix is driven by a COMBINATION, not by one field: altitude sets the
	// trend, and the field/patch pair sets where within that trend a given
	// slope is greener. That is what makes two fields at the same height look
	// like two fields instead of one painted surface.
	float drying = smoothstep(town_lo, ruins_lo, h);
	float green_mix = clamp(
		drying * 0.62
		+ (landmark - 0.5) * 0.55
		+ (field - 0.5) * 0.95
		+ (patch - 0.5) * 0.60, 0.0, 1.0);
	vec3 g = mix(grass_low, grass_dry, green_mix);

	// --- Soil breaks through -----------------------------------------------
	// THREE causes at three scales, because bare earth on a hillside has
	// three: slope shedding its cover, a thin or worn patch at field scale,
	// and scuffing at foot scale. PASS 02 had only the first two and both were
	// low frequency, so the ground was uniformly grass or uniformly soil over
	// tens of metres — the "solid fill" read its own comment complained about.
	float bare = clamp(
		  smoothstep(0.56, 0.26, field) * 0.60
		+ smoothstep(0.58, 0.36, patch) * 0.34
		+ smoothstep(0.74, 0.95, litter) * 0.18
		+ smoothstep(0.09, 0.30, steep) * 0.55,
		0.0, 1.0);
	vec3 base = mix(g, soil, bare);

	// --- Town floor --------------------------------------------------------
	// Baked into the vertex stream, because the village is a FOOTPRINT and not
	// a height band: a band paves the whole valley width, including the far
	// ridge, which has no village on it.
	//
	// 0.85 was too much: it paved the entire settlement footprint, and the
	// village came back from the air as one flat tan plateau with houses
	// sitting on it. A village is not a car park — most of the ground between
	// its buildings is still ground.
	//
	// PASS 03: 0.55 was STILL too much, and it is why the upper town — the
	// hero test zone — measured as a uniform khaki shelf in every first-person
	// frame. 0.34, and modulated by the patch field, so the paving, the
	// trodden earth and the surviving grass between the houses become three
	// different materials instead of one.
	float trodden = clamp(patch * 0.80 + field * 0.50, 0.0, 1.0);
	// PAVING IN THE TRODDEN PLACES, GRASS SURVIVING BETWEEN THEM.
	//
	// A settlement whose ground is one uniform colour reads as a car park no
	// matter how good the buildings standing on it are. Measured on the first
	// PASS 03 render at d=470: the upper town came back as one continuous
	// khaki shelf, and the fact that the buildings were fine did not help it
	// at all. Splitting the footprint into beaten ground and surviving grass by
	// a single thresholded field is what makes the space between the houses
	// look USED rather than swept.
	float beaten = smoothstep(0.38, 0.78, trodden);
	base = mix(base, town_floor * (0.84 + patch * 0.30), town * beaten * 0.52);
	base = mix(base, g * 1.02, town * (1.0 - beaten) * 0.42);

	// --- Settlement ground: WORN PAVING, not a colour -----------------------
	// The upper town is the hero test zone, and after the two mixes above its
	// ground still measured as one flat khaki shelf at eye height — because a
	// flat colour is a flat colour however carefully it is mixed. What a real
	// town square has, and what this adds, is the paving itself: irregular
	// slabs, mostly worn through to the earth between them, with grass in the
	// seams.
	//
	// This is the only place on the map where the ground is man-made, so it is
	// the only place that gets a slab pattern — which is also what keeps the
	// open valley from looking tiled.
	float mpp = fwidth(w_pos.x);
	float resolved = 1.0 - smoothstep(0.10, 0.34, mpp);
	float slab_a = slab_layer(w_pos.xz * 1.25, 0.0);
	float slab_b = slab_layer(w_pos.xz * 2.90 + 31.0, 4.25);
	float paving = clamp(slab_a * 0.86 + slab_b * 0.28, 0.0, 1.0);
	// Patchy, and gated on the trodden field: a square has paving where people
	// walk and earth where they do not.
	float paving_mask = town * beaten * resolved * smoothstep(0.30, 0.68, patch);
	// Same lesson as the road's setts: paving ages toward ONE value with a hue
	// wobble. At a +/-17% per-slab spread the first render of this read as a
	// quilt of separate tiles instead of as a worn floor.
	vec3 paved = town_floor * (0.90 + hash12(floor(w_pos.xz * 1.25) + 2.3) * 0.14);
	// The seams are the ground's own earth, so the slabs sit IN it rather than
	// on it.
	paved = mix(soil * 0.97, paved, paving);
	base = mix(base, paved, paving_mask * 0.44);

	// --- Ruins -------------------------------------------------------------
	float ruined = smoothstep(ruins_lo, ruins_lo + 26.0, h);
	base = mix(base, ruins_floor, ruined * 0.8);

	// --- Rock and cliff ----------------------------------------------------
	// Triplanar so a vertical wall does not get stretched smeared detail.
	float tri_y = abs(n.y);
	float tri_x = abs(n.x);
	float tri_z = abs(n.z);
	float tri_sum = tri_x + tri_y + tri_z;
	tri_x /= tri_sum; tri_y /= tri_sum; tri_z /= tri_sum;
	float rock_n =
		  vnoise(w_pos.zy * 0.13) * tri_x
		+ vnoise(w_pos.xz * 0.13) * tri_y
		+ vnoise(w_pos.xy * 0.13) * tri_z;

	vec3 stone = mix(rock, cliff, smoothstep(rock_lo, rock_hi, steep));
	stone *= 0.86 + rock_n * 0.30;
	base = mix(base, stone, smoothstep(rock_lo * 0.72, rock_hi * 0.88, steep));

	// --- River bank --------------------------------------------------------
	// Gravel and scoured stone right at the waterline, then a wet darkening
	// that reaches a little above it. This is what makes a river look like it
	// has been running there rather than a blue plane dropped on a ditch.
	float bank = 1.0 - smoothstep(0.0, 3.6, h - water_y);
	float damp = 1.0 - smoothstep(0.0, 1.5, h - water_y);
	base = mix(base, gravel * (0.88 + litter * 0.30 + clump * 0.16), clamp(bank * 0.95, 0.0, 1.0));
	base = mix(base, wet_dark, clamp(damp * 0.55, 0.0, 1.0));

	// --- Road wear ---------------------------------------------------------
	// The trodden verge painted from the vertex stream. The road SURFACE itself
	// is separate geometry (see mistvale_land.gd); this is the ground around it
	// being worn, scuffed and compacted.
	float scuff = 0.78 + clump * 0.30 + litter * 0.20;
	base = mix(base, road_dirt * scuff, wear * 0.85);

	// --- Kill the CG cleanliness -------------------------------------------
	// HOW FAR ONE PIXEL STRETCHES, so the fine bands can be dropped before
	// they alias. Without this, `litter` at a 1.2 m period is sub-pixel past
	// roughly 25 m and the distance becomes a shimmering field of crawling
	// dots — a worse artefact than the flatness it was added to fix, and one
	// that a still frame hides completely. (`mpp` is measured above, where the
	// settlement paving needed the same number.)
	float near_detail = 1.0 - smoothstep(0.25, 0.90, mpp);

	// Mid scale: the band that does the work at gameplay distance, and the one
	// whose absence made the ground read as a solid fill. The amplitude is 20%
	// rather than 14% because the first PASS 03 render at d=460 still came back
	// as a uniform olive sheet: at this albedo a +/-7% break is invisible.
	base *= 0.78 + clump * 0.40;
	// Near field only.
	base *= mix(1.0, 0.90 + litter * 0.20, near_detail);
	// A HUE break, not just a brightness break — but a SMALL one.
	//
	// The first PASS 03 attempt used +/-4.5% on the red and blue channels and
	// the ground came back with visible mauve patches across the whole upper
	// town. The arithmetic is obvious in hindsight: this surface is already
	// desaturated grey-khaki, so a few percent of channel offset is not a
	// subtle warmth change, it is a COLOUR CAST, and a cast is the one thing
	// that reads as a shader bug rather than as ground. +/-1.6% moves the
	// reading without naming a colour.
	base *= mix(vec3(1.016, 1.000, 0.982), vec3(0.984, 1.000, 1.018), patch);

	// --- Detail normal: the thing that was actually missing -----------------
	//
	// EVERYTHING ABOVE IS ALBEDO, AND ALBEDO ALONE CANNOT STOP A SURFACE
	// READING AS PRINTED PLASTIC.
	//
	// The eye reads form from the CHANGE IN A SURFACE'S RESPONSE TO LIGHT
	// across it. A perfectly smooth normal returns the same response
	// everywhere, so no amount of albedo work makes it look like a surface —
	// which is exactly the trap PASS 02 and the first PASS 03 attempt fell
	// into. The terrain has always had relief at 100 m (the height field) and a
	// 3 m mesh, and NOTHING BETWEEN, so at eye height the ground was a lit
	// plane with a texture printed on it.
	//
	// A procedural detail height field, differentiated and applied as a NORMAL
	// perturbation. Three noise taps for the height plus four more for the
	// gradient, no texture, no import, no tiling, no mip chain — and it scales
	// itself down with distance through `near_detail`, so the far hillside does
	// not crawl.
	//
	// ---------------------------- IT DOES NOT WORK ---------------------------
	//
	// THE NORMAL WRITE BELOW IS COMMENTED OUT BECAUSE IT CANNOT BE DONE IN THIS
	// RENDERER. Measured, in three steps, all on the same d=470 hero frame and
	// all reading the same ground patch:
	//
	//   * `NORMAL = normalize(VIEW_MATRIX * vec4(w_shaded, 0.0))` (view space)
	//     -> ground rgb(104,107,94) becomes rgb(53,74,88): half the luminance,
	//     and blue.
	//   * The same expression in WORLD space -> rgb(49,68,80). Also blue.
	//   * `NORMAL = normalize(VIEW_MATRIX * vec4(w_nrm, 0.0))` — the SAME round
	//     trip with NO perturbation applied at all -> rgb(53,74,88),
	//     BYTE-IDENTICAL to the perturbed version.
	//
	// The third result is the one that settles it: removing the perturbation
	// changes nothing, so the perturbation was never reaching the lighting.
	// Assigning to NORMAL in the fragment stage does not modify the normal here
	// — it takes the surface OFF the directional light entirely and leaves it
	// on the ambient term. The ambient is blue, so the whole map turns blue.
	// It is not a space-convention mistake; both conventions fail identically.
	//
	// THIS ALSO MEANS mistvale_water.gdshader's ripple normals have never done
	// anything, and the river has been ambient-lit since it was written.
	//
	// So the detail lives in the ALBEDO, where it demonstrably works: the same
	// height field is used as a cheap occlusion instead of as a normal. Less
	// than a normal would have bought, and it is what this renderer has.
	float e = 0.10;
	vec2 dp = w_pos.xz;
	float dh = vnoise(dp * 1.40) * 0.62 + vnoise(dp * 3.60) * 0.38;
	// The hollows between the lumps are darker. Without this the detail would
	// be invisible: albedo variation on its own is what the rest of this file
	// already does.
	base *= 0.88 + dh * 0.24;

	ALBEDO = base;

	// Roughness follows what the material is: wet mud is glassy, grass is not,
	// bare rock is in between and dusty.
	float rough = 0.95;
	rough = mix(rough, 0.88, clamp(bare, 0.0, 1.0));
	rough = mix(rough, 0.82, smoothstep(rock_lo * 0.72, rock_hi * 0.88, steep));
	rough = mix(rough, 0.80, wear);
	rough = mix(rough, 0.30, clamp(damp * 0.9, 0.0, 1.0));
	ROUGHNESS = rough;

	// The wet band and the packed road both catch a little more specular light;
	// this is most of what sells "the stone here is wet" at a glance.
	SPECULAR = mix(0.35, 0.75, clamp(damp * 0.9 + wear * 0.25, 0.0, 1.0));
}
