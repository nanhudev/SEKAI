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

// x = nearest, y = second, zw = owning cell centre (in cell space)
vec4 voronoi(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 centre = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash21(ip + g), hash21(ip + g + 17.31));
			o = 0.5 + 0.40 * sin(o * 6.2831 + vec2(1.7, 4.2));
			float d = length(g + o - fp);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				centre = ip + g + o;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec4(f1, f2, centre);
}

// Reverse compression: air being dragged back into the sheath mouth.
// Content is pulled inward, with a soft trailing wake so it reads as
// refraction rather than a magic circle.
vec2 ring_pull(vec2 dir, float len, float progress, float strength) {
	if (strength <= 0.001) {
		return vec2(0.0);
	}
	float radius = pow(1.0 - clamp(progress, 0.0, 1.0), 1.55) * 0.95 + 0.02;
	float ring = exp(-pow((len - radius) * 26.0, 2.0));
	float wake = exp(-pow((len - radius * 1.42) * 11.0, 2.0)) * 0.42;
	return dir * (ring + wake) * strength * 0.020;
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
	vec2 pull = ring_pull(dir_s, len_s, wave_a, wave_strength)
			+ ring_pull(dir_s, len_s, wave_b, wave_strength * 0.76)
			+ ring_pull(dir_s, len_s, wave_c, wave_strength * 0.55);

	// ---- glass layers 1 + 2: stress cracks and their refraction -----------
	// Large plates (a handful of primary shards), hairline cracks between
	// them, spreading out from the cut. Deliberately NOT a spiderweb overlay.
	vec2 cell_p = uv * asp * 5.5 + vec2(3.1, 1.7);
	vec4 v1 = voronoi(cell_p);
	float thickness = 0.0045 + 0.014 * vnoise(uv * asp * 26.0);
	float crack_a = 1.0 - smoothstep(0.0, thickness, v1.y - v1.x);
	// Some branches simply stop. Glass does not crack in a perfect web.
	float stops = step(0.30, hash21(v1.zw * 7.3));
	crack_a *= mix(0.15, 1.0, stops);
	vec4 v2 = voronoi(uv * asp * 12.0 + vec2(11.7, 5.3));
	float crack_b = (1.0 - smoothstep(0.0, 0.0035, v2.y - v2.x)) * 0.40;

	float ad0 = abs(dot((uv - cut_center) * asp, nrm));
	float gate = smoothstep(0.0, 0.06, fracture + shatter);
	float front = fracture * 0.85 + shatter * 1.60;
	float reach = 1.0 - smoothstep(0.0, 0.30, ad0 - front);
	float proximity = 1.0 - smoothstep(0.08, 0.70, ad0);
	float crack = clamp(crack_a * 0.9 + crack_b, 0.0, 1.0) * reach * proximity * gate * (1.0 - dissolve);
	vec2 push = normalize(cell_p - v1.zw + vec2(1e-4)) * crack * refract_px * sx * px;

	// ---- separation of the two halves -------------------------------------
	float d = dot((uv - cut_center) * asp, nrm);
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
	float ad = ad0 + micro * void_edge_width_px * sx * px;
	float half_gap = 0.5 * gap_px * sx * px + 0.64 * separation_px * sx * px;
	float in_void = (1.0 - smoothstep(half_gap - px, half_gap + px, ad)) * void_open;

	float t = clamp(ad / max(half_gap, 1e-5), 0.0, 1.0);
	vec3 void_col = mix(void_mid_color, void_edge_color, smoothstep(0.18, 1.0, t));
	float core = 1.0 - smoothstep(0.0, void_core_width, t);
	void_col = mix(void_col, void_core_color, pow(core, 3.0) * 0.50);

	// Slow fog drifting inward (toward the cut line), never outward.
	vec2 fog_p = vec2(dot((uv - cut_center) * asp, tangent) * 2.2, t * 3.4 + time * 0.10);
	float fog = fbm(fog_p * vec2(1.0, 1.4) + vec2(time * 0.045, 0.0));
	void_col += vec3(0.020, 0.040, 0.072) * fog * 0.55 * void_life;
	float specks = pow(fbm(fog_p * 4.1 + vec2(time * 0.03, time * 0.02)), 9.0);
	void_col += vec3(0.30, 0.44, 0.64) * specks * 0.45 * void_life;
	void_col += ghost * vec3(0.040, 0.070, 0.115) * void_life * 0.45;

	// ---- world-side cut face: ivory rim + dark ink fibres ------------------
	float rim_band = 1.0 - smoothstep(half_gap, half_gap + rim_px * sx * px, ad);
	float ink_band = 1.0 - smoothstep(half_gap + rim_px * sx * px, half_gap + rim_px * 4.0 * sx * px, ad);
	world = mix(world, world * 0.35, ink_band * void_open * 0.50);
	world = mix(world, IVORY, rim_band * void_open * 0.38);

	// ---- composite ---------------------------------------------------------
	vec3 col = mix(world, void_col, in_void);

	// Cracks read as thin bright glass edges plus a faint refraction sheen.
	col = mix(col, vec3(0.90, 0.93, 0.88), crack * 0.50 * (1.0 - in_void));
	col += vec3(0.06, 0.09, 0.12) * crack * 0.30 * (1.0 - in_void);

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
