shader_type canvas_item;
render_mode unshaded;

// ---------------------------------------------------------------------------
// SEKAI · Iaido world split.
//
// Reality is not "two UI images sliding". A diagonal cut opens a real VOID GAP
// between the two halves. The gap is deep navy -> indigo -> a tiny blue-white
// core, with slow inward fog, impossible mirrored parallax and sparse motes.
// The two halves then separate along the cut normal, and the world surface
// finally fails like glass: stress cracks, refraction, then physical shards.
//
// Two things here are deliberately authored to survive a flat test arena:
//  1. The reverse compression front carries a bright crest over a dark trough.
//     Pure refraction is invisible over flat colour, so the pressure edge has
//     to be painted, not just sampled.
//  2. Cracks GROW out of the cut line as wandering branches with tapering
//     tips. A Voronoi f2-f1 field reads as a tidy hex web, which is exactly
//     what glass does not look like.
// ---------------------------------------------------------------------------

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform vec2 cut_center = vec2(0.5, 0.5);
uniform float cut_angle = -30.0;      // degrees, screen space
uniform float time = 0.0;

uniform float focus = 0.0;            // world drain: desaturation + contrast
uniform float void_open = 0.0;        // 0..1 presence of the cut
uniform float gap_px = 0.0;           // void gap thickness in pixels
uniform float separation_px = 0.0;    // how far the halves pulled apart
uniform float depth_parallax = 0.006; // subtle perspective between the halves
uniform float restore_pull = 0.0;     // reverse-suck on restore
uniform float slide_px = 0.0;         // gravity slide, only after shatter
uniform float ivory_flash = 0.0;      // 20-40ms sheath-lock flash (never white-out)
uniform float void_life = 1.0;

uniform vec3 void_edge_color = vec3(0.020, 0.043, 0.110);
uniform vec3 void_mid_color = vec3(0.086, 0.125, 0.320);
uniform vec3 void_core_color = vec3(0.760, 0.870, 0.950);
uniform float void_core_width = 0.16;
uniform float void_edge_width_px = 2.2;

uniform float fracture = 0.0;         // layer 1 stress cracks spreading out
uniform float shatter = 0.0;          // layer 3 full collapse displacement
uniform float dissolve = 0.0;         // cracks fading on restore
uniform float refract_px = 6.0;
uniform float rim_px = 3.5;

uniform float wave_strength = 0.0;
uniform float wave_a = 0.0;
uniform float wave_b = 0.0;
uniform float wave_c = 0.0;
uniform vec2 sheath_uv = vec2(0.22, 0.80);

const vec3 IVORY = vec3(0.97, 0.95, 0.85);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		s += vnoise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return s;
}

// Reverse compression: air being dragged back into the sheath mouth.
// Returns (inward pull, visible crest). The crest is what the eye actually
// reads: a bright density edge with a dark trough trailing behind it on the
// outside, the way a pressure front photographs against a plain wall.
vec2 ring_profile(float len, float progress) {
	// Radius decays late (exponent < 1) so the shell stays inside the visible
	// frame for most of its life. A hard ease-in dropped it through the whole
	// screen in the last 15% of the shell, which read as nothing at all.
	// The compression still accelerates, but through the envelope and the
	// crest brightness rather than by hiding the ring off-frame.
	float radius = pow(1.0 - clamp(progress, 0.0, 1.0), 0.55) * 0.95 + 0.02;
	float ring = exp(-pow((len - radius) * 26.0, 2.0));
	float wake = exp(-pow((len - radius * 1.42) * 11.0, 2.0)) * 0.42;
	return vec2(ring + wake, ring);
}

// One crack branch growing outward from the cut line.
// It wanders more the further it travels, and thins toward its tip instead of
// stopping dead, so the bundle never reads as a printed pattern.
float crack_branch(vec2 p, vec2 origin, vec2 dir, float len, float seed, float width) {
	float along = dot(p - origin, dir);
	if (along < 0.0 || along > len) {
		return 0.0;
	}
	float wander = (vnoise(vec2(along * 4.2 + seed * 9.0, seed)) - 0.5) * (0.018 + along * 0.30);
	vec2 q = origin + dir * along + vec2(-dir.y, dir.x) * wander;
	float d = length(p - q);
	float taper = 1.0 - 0.72 * (along / max(len, 1e-3));
	float body = 1.0 - smoothstep(0.0, width * taper, d);
	body *= 1.0 - smoothstep(len * 0.55, len, along);
	return body;
}

// Stress field: nine primary branches plus six finer ones. Both sets start on
// the cut line and run outward, so the fracture always reads as "this world
// broke along the sword", never as a full-screen texture.
float crack_field(vec2 p, vec2 nrm, vec2 tangent, float front, float seed) {
	float acc = 0.0;
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		float h1 = hash21(vec2(fi * 1.37, seed));
		float h2 = hash21(vec2(fi * 2.71, seed + 5.0));
		float h3 = hash21(vec2(fi * 4.13, seed + 11.0));
		vec2 origin = tangent * ((h1 - 0.5) * 2.6);
		vec2 dir = nrm * (h2 > 0.5 ? 1.0 : -1.0);
		dir = normalize(dir + tangent * (h3 - 0.5) * 0.55);
		float len = front * (0.32 + h3 * 0.88);
		acc = max(acc, crack_branch(p, origin, dir, len, h1 * 37.0, 0.0029));
	}
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		float h1 = hash21(vec2(fi * 6.19 + 41.0, seed));
		float h2 = hash21(vec2(fi * 3.53 + 7.0, seed + 3.0));
		vec2 origin = tangent * ((h1 - 0.5) * 3.0);
		vec2 dir = normalize(nrm * (h2 > 0.5 ? 1.0 : -1.0) + tangent * (h1 - 0.5) * 0.9);
		float len = front * (0.18 + h1 * 0.52);
		acc = max(acc, crack_branch(p, origin, dir, len, h2 * 61.0, 0.0016));
	}
	return acc;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = resolution.x / max(resolution.y, 1.0);
	float px = 1.0 / max(resolution.y, 1.0);          // one pixel, aspect units
	// Pixel amounts are authored against 1080p so the crack reads the same at
	// any resolution instead of swelling on small viewports.
	float sx = max(resolution.y, 1.0) / 1080.0;
	vec2 asp = vec2(aspect, 1.0);
	vec2 to_uv = 1.0 / asp;

	float a = radians(cut_angle);
	vec2 tangent = vec2(cos(a), sin(a));
	vec2 nrm = vec2(-sin(a), cos(a));

	// ---- reverse wave (pre-cut, three staggered layers) -------------------
	vec2 from_sheath = (uv - sheath_uv) * asp;
	float len_s = length(from_sheath);
	vec2 dir_s = from_sheath / max(len_s, 1e-4);
	vec2 rp1 = ring_profile(len_s, wave_a);
	vec2 rp2 = ring_profile(len_s, wave_b);
	vec2 rp3 = ring_profile(len_s, wave_c);
	float pull_sum = rp1.x + rp2.x * 0.76 + rp3.x * 0.55;
	float crest = (rp1.y + rp2.y * 0.80 + rp3.y * 0.60) * wave_strength;
	float trough = ((rp1.x - rp1.y) + (rp2.x - rp2.y) * 0.80 + (rp3.x - rp3.y) * 0.60) * wave_strength;
	vec2 pull = dir_s * pull_sum * wave_strength * 0.038;

	// ---- glass layers 1 + 2: stress cracks and their refraction -----------
	// Coordinates relative to the cut, so the branches can be authored along
	// the blade instead of laid over the screen.
	vec2 rel = (uv - cut_center) * asp;
	float front = fracture * 0.85 + shatter * 1.60;
	float gate = smoothstep(0.0, 0.06, fracture + shatter);
	// Cracks stay near the wound: they spread from the cut, not everywhere.
	float proximity = 1.0 - smoothstep(0.10, 0.85, abs(dot(rel, nrm)));
	float crack = crack_field(rel, nrm, tangent, max(front, 0.001), 17.0 + 0.0);
	crack = clamp(crack * 1.25, 0.0, 1.0) * gate * proximity * (1.0 - dissolve);
	vec2 push = nrm * crack * refract_px * sx * px;

	// ---- separation of the two halves -------------------------------------
	float d = dot(rel, nrm);
	float side = d >= 0.0 ? 1.0 : -1.0;
	// Mostly along the cut normal, biased tangentially so the upper piece
	// drifts up/right and the lower piece drifts down/left.
	vec2 upper_dir = normalize(-nrm + tangent * 1.2);
	vec2 sep_dir = upper_dir;
	if (side >= 0.0) {
		sep_dir = -upper_dir;
	}
	vec2 move = sep_dir * separation_px * sx * px;
	if (side < 0.0) {
		move += vec2(-0.16, 1.0) * slide_px * sx * px;
	}
	move += nrm * side * restore_pull * sx * px;

	vec2 source = uv + (pull + push) * to_uv - move * to_uv;
	// Very slight perspective so the cut face reads as having thickness.
	float depth = side < 0.0 ? depth_parallax : -depth_parallax * 0.7;
	source = cut_center + (source - cut_center) * (1.0 + depth * step(0.001, separation_px));
	source = clamp(source, vec2(0.0015), vec2(0.9985));

	vec3 world = texture(screen_tex, source).rgb;

	// ---- mirrored "impossible parallax" echo used inside the void ---------
	vec2 mirror_uv = clamp(uv - nrm * to_uv * (2.0 * d) + tangent * to_uv * 0.035, vec2(0.002), vec2(0.998));
	vec3 ghost = texture(screen_tex, mirror_uv).rgb;

	// ---- void gap ----------------------------------------------------------
	// The void is bounded by where the two halves actually ARE, not by a fixed
	// stripe: the initial crack opens the slit, then the separation itself
	// keeps widening it so the blue emptiness is gradually revealed.
	float micro = (fbm(uv * asp * 110.0) - 0.5) * 2.0;
	float ad = abs(dot(rel, nrm)) + micro * void_edge_width_px * sx * px;
	float half_gap = 0.5 * gap_px * sx * px + 0.64 * separation_px * sx * px;
	float in_void = (1.0 - smoothstep(half_gap - px, half_gap + px, ad)) * void_open;

	float t = clamp(ad / max(half_gap, 1e-5), 0.0, 1.0);
	vec3 void_col = mix(void_mid_color, void_edge_color, smoothstep(0.18, 1.0, t));
	// The blue-white core is a fixed hairline in PIXELS, not a share of the
	// gap. Scale it with the gap and a narrow slit becomes a solid glowing
	// rope, which is the one thing the void must never look like: the wound
	// should read as deep navy emptiness with a hairline of light down the
	// middle, not as a lit tube.
	float core_w = max(void_core_width * 14.0 * sx * px, 1e-6);
	float core = 1.0 - smoothstep(0.0, core_w, ad);
	void_col = mix(void_col, void_core_color, pow(core, 1.6) * 0.74);

	// Inside the wound: depth, not a flat fill. Slow fog drifts inward (toward
	// the cut line, never outward), sparse motes hang in it, and a mirrored
	// echo of the world gives the parallax of somewhere that is not here.
	//
	// The echo is kept faint on purpose. This arena is bright, so blending the
	// world back in at any strength turned the wound into a lit blue tube; the
	// void has to stay clearly darker than the world it replaced.
	vec2 fog_p = vec2(dot(rel, tangent) * 1.7, t * 2.6 + time * 0.085);
	float fog = fbm(fog_p * vec2(1.0, 1.5) + vec2(time * 0.04, 0.0));
	float fog2 = fbm(fog_p * 3.1 - vec2(time * 0.03, time * 0.05));
	void_col += vec3(0.055, 0.095, 0.165) * fog * 0.90 * void_life * in_void;
	void_col += vec3(0.030, 0.050, 0.090) * fog2 * 0.45 * void_life * in_void;
	float specks = pow(fbm(fog_p * 5.0 + vec2(time * 0.02, time * 0.03)), 8.0);
	void_col += vec3(0.50, 0.66, 0.90) * specks * 0.60 * void_life * in_void;
	void_col = mix(void_col, void_col * 0.72 + ghost * 0.28, 0.12 * void_life);
	void_col += ghost * vec3(0.030, 0.052, 0.090) * void_life * 0.22;

	// ---- world-side cut face: ivory rim + dark ink fibres ------------------
	float rim_band = 1.0 - smoothstep(half_gap, half_gap + rim_px * sx * px, ad);
	float ink_band = 1.0 - smoothstep(half_gap + rim_px * sx * px, half_gap + rim_px * 4.0 * sx * px, ad);
	world = mix(world, world * 0.35, ink_band * void_open * 0.50);
	world = mix(world, IVORY, rim_band * void_open * 0.38);

	// ---- composite ---------------------------------------------------------
	vec3 col = mix(world, void_col, in_void);

	// Cracks read as a dark seam with a lit edge beside it: that pairing is
	// what sells broken glass far more than a bright line on its own. Which
	// half dominates depends on what is behind it — a lit line over a white
	// floor is simply invisible, and this arena is mostly white floor.
	float luma_c = dot(col, vec3(0.299, 0.587, 0.114));
	float dark_gain = smoothstep(0.30, 0.85, luma_c);
	float crack_core = smoothstep(0.55, 1.0, crack);
	float crack_edge = smoothstep(0.20, 0.70, crack);
	col = mix(col, col * 0.26, crack_core * (0.40 + 0.42 * dark_gain) * (1.0 - in_void));
	col = mix(col, vec3(0.93, 0.95, 0.92), crack_edge * (0.34 - 0.26 * dark_gain) * (1.0 - in_void));

	// The compression front. Refraction alone vanishes over flat colour, so the
	// pressure edge has to be painted too — but a white ring on a white floor
	// would just read as a magic circle. The band adapts to what it crosses:
	// a dark density band over bright surfaces, a lit crest over dark ones,
	// which is how a shock front actually photographs.
	float luma_here = dot(col, vec3(0.299, 0.587, 0.114));
	float crest_dark = smoothstep(0.28, 0.78, luma_here);
	float crest_lit = smoothstep(0.72, 0.18, luma_here);
	col -= vec3(0.110, 0.130, 0.170) * crest * crest_dark * 1.25;
	col += vec3(0.400, 0.500, 0.660) * crest * crest_lit * 0.75;
	col -= vec3(0.055, 0.065, 0.085) * trough * 0.60;

	// World drain: desaturate and lift contrast, void stays cold and alive.
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(gray), focus * 0.73 * (1.0 - in_void));
	col = (col - 0.5) * (1.0 + focus * 0.06) + 0.5;

	vec2 vig = uv * 2.0 - 1.0;
	col *= 1.0 - smoothstep(0.45, 1.7, dot(vig, vig)) * focus * 0.18;

	// Sheath lock flash: a 20-40ms ivory kiss, never a white screen.
	col += IVORY * ivory_flash;

	COLOR = vec4(col, 1.0);
}
