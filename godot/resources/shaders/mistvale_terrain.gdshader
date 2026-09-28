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
uniform vec3 grass_low   : source_color = vec3(0.473, 0.570, 0.403); // 0.190 0.285 0.135
uniform vec3 grass_dry   : source_color = vec3(0.584, 0.586, 0.449); // 0.300 0.302 0.170
uniform vec3 soil        : source_color = vec3(0.522, 0.461, 0.396); // 0.235 0.180 0.130
uniform vec3 road_dirt   : source_color = vec3(0.610, 0.566, 0.501); // 0.330 0.280 0.215
uniform vec3 gravel      : source_color = vec3(0.622, 0.610, 0.588); // 0.345 0.330 0.305
uniform vec3 rock        : source_color = vec3(0.549, 0.537, 0.530); // 0.262 0.250 0.243
uniform vec3 cliff       : source_color = vec3(0.501, 0.493, 0.498); // 0.215 0.208 0.212
uniform vec3 town_floor  : source_color = vec3(0.588, 0.577, 0.558); // 0.305 0.292 0.272
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

	// --- Large-scale albedo breakup ----------------------------------------
	// One low-frequency field decides where soil shows through the grass, so
	// the ground changes character over tens of metres instead of every 3 m.
	float macro = fbm(w_pos.xz * 0.012 + vary * 7.0);
	float meso  = fbm(w_pos.xz * 0.055 + 3.1);
	float micro = fbm(w_pos.xz * 0.34);

	// --- Grass -------------------------------------------------------------
	// Drier and greyer as it climbs; the valley floor is the humid green.
	float drying = smoothstep(town_lo, ruins_lo, h);
	vec3 g = mix(grass_low, grass_dry, clamp(drying * 0.85 + macro * 0.35, 0.0, 1.0));

	// Soil breaks through where the macro field is low, and on steeper ground.
	float bare = smoothstep(0.62, 0.30, macro) * 0.75 + smoothstep(0.10, 0.34, steep) * 0.55;
	vec3 base = mix(g, soil, clamp(bare, 0.0, 1.0));

	// --- Town floor --------------------------------------------------------
	// Baked into the vertex stream, because the village is a FOOTPRINT and not
	// a height band: a band paves the whole valley width, including the far
	// ridge, which has no village on it.
	//
	// 0.85 was too much: it paved the entire settlement footprint, and the
	// village came back from the air as one flat tan plateau with houses
	// sitting on it. A village is not a car park — most of the ground between
	// its buildings is still ground.
	base = mix(base, town_floor * (0.92 + meso * 0.16), town * 0.55);

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
	base = mix(base, gravel * (0.88 + micro * 0.24), clamp(bank * 0.95, 0.0, 1.0));
	base = mix(base, wet_dark, clamp(damp * 0.55, 0.0, 1.0));

	// --- Road wear ---------------------------------------------------------
	// The trodden verge painted from the vertex stream. The road SURFACE itself
	// is separate geometry (see mistvale_land.gd); this is the ground around it
	// being worn, scuffed and compacted.
	float scuff = 0.80 + micro * 0.34;
	base = mix(base, road_dirt * scuff, wear * 0.85);

	// --- Kill the CG cleanliness -------------------------------------------
	// A per-pixel tint spread. Without it, large flat areas of one albedo read
	// as a solid fill no matter how good the zone logic is — and the first
	// version's spread was 13%, which at 3 m grid resolution was invisible and
	// left the ground reading as smooth painted plastic in every first-person
	// frame. This is the cheapest texture on the map: it costs four noise
	// lookups that were already being computed.
	base *= 0.86 + micro * 0.26;
	// A second, finer break at a different scale. One noise field at one
	// frequency reads as a pattern; two that do not divide evenly read as
	// ground.
	base *= 0.93 + vnoise(w_pos.xz * 0.71 + 17.0) * 0.16;

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
