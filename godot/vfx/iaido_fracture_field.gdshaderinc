// ---------------------------------------------------------------------------
// SEKAI · Iaido — THE SHARED FRACTURE FIELD
//
// ONE DEFINITION, TWO SHADERS.
//
// `iaido_world_split.gdshader` (the screen pass that cuts the world in two) and
// `iaido_glass_shard.gdshader` (the panes the surface comes apart into) draw
// the SAME crack network over the SAME picture. Where a pane is still lying
// over live world the two nets have to land on the same pixel, and where a pane
// has come away its contents have to carry the cracks it was cut with. Two
// copies of this arithmetic drift the first time either one is tuned — which is
// how this project has already silently lost a `.tres` timeline and an audio
// cue table. So it lives here and is textually included by both.
//
// NOTHING IN THIS FILE MAY BE TUNED IN ONE SHADER ONLY. Every `iaido_*`
// function below is a contract between the two passes.
//
// FRAME OF REFERENCE — the screen pass's, because it is the one the masks and
// the capture are both authored in:
//
//     rel = (uv - cut_center) * vec2(aspect, 1.0)
//
// so `rel.y` runs -0.5..0.5 across the frame height and ONE UNIT IS THE FULL
// FRAME HEIGHT. Distances authored in pixels ("so many px at 1080p") convert
// with IAIDO_AUTHORED_PX; the screen pass divides by its own `px_s` to get
// there, and the pane pass multiplies `rel` by it directly.
//
// The glass pass reaches this frame from its own plane coordinates
// (`capture_half` = half the frame height, y-up) with
//     rel = vec2(plane.x, -plane.y) / (2.0 * capture_half)
// which is the exact inverse of `plane_to_uv()` in the shard shader.
// ---------------------------------------------------------------------------

// The height the pixel figures below are authored against. Everything that is
// "N pixels" in this ceremony is N pixels of a 1080-tall frame, so the wound
// reads the same at every resolution instead of swelling on small viewports.
const float IAIDO_AUTHORED_PX = 1080.0;

// ---- WHICH REGION CRACKS FIRST ------------------------------------------
//
// A low-frequency field over the SURFACE, not over time. Each region of the
// picture owns a threshold, so raising the stress opens the network a branch at
// a time — a short one here, a longer one there, some never — instead of
// switching a uniform net on. A single reveal front over a uniform Voronoi mask
// is a net, and a net is a texture laid on a picture.
//
// Changing either seed changes the sequence, which is the point: the order is a
// property of where a thing is, not of when the shader got to it.
const vec2 IAIDO_ORDER_ORIGIN = vec2(31.7, 12.3);
const float IAIDO_ORDER_FREQ = 1.05;
// 0.80 makes almost every region ready within the first third of the stress
// ramp, which is a net opening rather than a sequence. 0.66 holds roughly a
// third of the network back until late.
const float IAIDO_READY_SLOPE = 0.66;
const float IAIDO_READY_SOFT = 0.16;

// ---- WHICH CRACK OPENS WIDE ---------------------------------------------
//
// With one uniform weight the whole network arrives at the same strength and
// reads as damage printed over the picture — the forbidden phone-screen
// spiderweb, just with irregular geometry. This field decides which regions of
// the surface actually gave way.
const vec2 IAIDO_WEIGHT_ORIGIN = vec2(5.1, 9.3);
// 1.7 is a slower variation than the network's own cell size, so neighbours in
// the mask ended up carrying almost the same weight and the whole net lit
// together — the stagger existed but it was invisible. 3.4 puts the field at
// roughly the scale of the branches, so regions genuinely differ.
const float IAIDO_WEIGHT_FREQ = 3.4;
// 0.16 is "a little quieter". 0.05 is "this branch has not opened". The brief's
// §14 asks for 4–8 main branches with some places left alone; a floor high
// enough to be visible everywhere is a net.
const float IAIDO_WEIGHT_MIN = 0.05;

// ---- HOW FAR OUT THE FRONT REACHES --------------------------------------
//
// THE FRONT HAS TO ACTUALLY TRAVEL.
//
// This was 640, and the frame's half-height is 540 authored pixels — so by a
// fracture of 0.85 the front had already passed the far corner and the entire
// picture was inside it. `iaido_grown()` returned 1 everywhere, `lit` differed
// from place to place only through the weight field, and the network appeared
// as a completed net that then merely got brighter. §12–14 ask for a main cut
// with branches that GROW OUTWARD from it, and a front that reaches the edge
// before the mid-point of its own ramp cannot express that.
//
// At 300 the front was still travelling when the shatter takes over, so the
// outer corners were genuinely clean until the world came apart. 裂缝大一点
// moved it to 360: the network now reads across rather more than half the frame
// height instead of stopping in the middle distance, while the corners still
// have something left to lose when the collapse runs.
// FINAL LOCK PART G — THE FRONT IS A BAND OUT OF THE WOUND, NOT A WASH OVER THE
// FRAME.
//
// This is the term that decides how much of the picture the glass claims, and
// therefore — because what the stream eats is exactly what the panes cover —
// how much of the picture goes black. 360 put a fully-eaten band ±148 authored
// px either side of the cut, which at 720p is a 197px near-black wedge: the
// reviewer's 世界裂口像 Overlay, arrived at through the EAT rather than through
// the slot. 190 halved it and still read as a band.
//
// At 90 with a 0.50 core the fully-eaten strip is ±45 authored px and it is
// gone by 91 — a seam that hugs the wound, ~60 real px wide at 720p. The
// corners stay structurally intact until the click, which is what §PRE-CLICK
// asks for, and the shatter front (480) is what takes them afterwards.
const float IAIDO_FRONT_PER_FRACTURE = 90.0;
// The shatter finishes the job: the collapse front has to reach the corners or
// the collapse leaves four untouched triangles in the frame.
const float IAIDO_FRONT_PER_SHATTER = 480.0;
// 0.78 made the inner four fifths of the front fully grown, so the front behaved
// as a hard-edged band and the only gradient in the picture was its last few
// pixels. 0.50 gives the falloff half the reach to work with, so the fracture
// density genuinely falls away from the cut instead of stopping at a line.
const float IAIDO_FRONT_CORE = 0.50;
const float IAIDO_FRONT_TAIL = 1.0;

// ---- HOW NARROWLY THE GLASS HUGS THE WOUND ------------------------------
//
// THE STRESS GATE AND THE GLASS GATE ARE NOT THE SAME QUESTION, AND CONFLATING
// THEM IS WHAT PUT A 60px NEAR-BLACK BAND ALONG THE CUT.
//
// `iaido_grown()` above is the STRESS gate: how far the fracture NETWORK has
// spread across the surface. The network is thin seams plus a few pixels of
// displacement, it is secondary detail, and it is allowed — wanted — to reach
// the whole front. Nothing is removed from the world for it.
//
// `iaido_claimed()` below is the GLASS gate: how much of the surface the panes
// have taken over. The panes are FILLED regions with an alpha and the world is
// DELETED underneath them, so their reach is not a detail — it is how much of
// the picture goes. Driving that gate off the whole front ate a band of
// ±(front * 0.50) = ±45 authored px either side of the cut (the earlier 360
// made it ±148), which at 720p is a 60px near-black wedge: the reviewer's
// 世界裂口像 Overlay, arrived at through the EAT rather than through the slot.
//
// The claim is a COLLAR. At fracture 1 the front is 90, so the wall of the
// wound is fully glass out to 4.5 authored px and the last of it is gone by
// 14.4 — a thin skin hugging the slot the break actually opened, which is the
// only place a pane genuinely REPLACES world rather than merely covers it.
//
// IT IS SIZED AGAINST THE SLOT, NOT AGAINST THE FRONT. The slit the break
// opens is `gap_ratio` of the separation, so at the PASS 4 values that is
// 6.6 authored px of hole; the collar has to be the hole plus a couple of
// pixels of transition on either side and not one pixel more, or the frame
// acquires a band around a slit and the eye reads the band. 0.16 of 90 is
// 14.4 authored px ≈ 9.6 real px at 720p, which is the hole plus the broken
// edge band and nothing else.
//
// The collapse is the exception and it is expressed separately, because a
// surface coming apart IS all of its pieces at once and pretending otherwise
// would leave four intact corners in the frame.
const float IAIDO_CLAIM_CORE = 0.05;
const float IAIDO_CLAIM_TAIL = 0.16;

// ---- HOW HARD IT OPENS --------------------------------------------------
const float IAIDO_STRESS_PER_FRACTURE = 1.20;
const float IAIDO_LIT_PER_FRACTURE = 1.15;
const float IAIDO_LIT_PER_SHATTER = 0.85;

// ---- THE HEAD RUNS PAST THE END OF THE LINE -----------------------------
//
// `travel` stops at 1.0, so a front compared against `stream` directly reaches
// the far end of the slash only in the limit: the last few percent of the line
// sits permanently half-arrived, and what that looks like is a strip of live
// world along one corner that the glass never claims. The overshoot is small
// and it is the difference between a front that finishes and one that nearly
// does.
//
// `IaidoTuning.stream_arrived()` is the GDScript mirror of this and must carry
// the same overshoot. `tests/iaido_integration.gd` asserts the two agree.
const float IAIDO_LEAD_OVERSHOOT = 1.14;
const float IAIDO_ARRIVED_BACK = 0.10;
const float IAIDO_ARRIVED_FRONT = 0.06;

// ---- THE ORDER INSIDE ONE PIXEL: GLASS FIRST, ABSENCE SECOND -------------
//
// The pane arrives on `arrived`: a point is fully covered only when the front
// has passed it by IAIDO_ARRIVED_BACK (0.10). The world is eaten on the wedge
// below. When the wedge ran AHEAD of that boundary — it began at lead − 0.14,
// then lead + 0.07, both of which eat points the front has not yet passed —
// every pixel the front crossed went world → dark → glass: a dark blink
// travelling down the slash, and then a second bright world (the panes)
// fading in over it. Measured, not guessed: with the wedge at lead + 0.07 the
// ceremony's mean luma still dipped 155 → 117 as the front swept the frame.
//
// So the world's eaten boundary is EXACTLY the pane's opaque boundary
// (lead − IAIDO_ARRIVED_BACK): a point stops existing on the frame the moment
// the glass that replaces it is fully opaque, and not one instant sooner. The
// tail softens the boundary so the change is a stream, not a wipe. At
// stream = 1 the lead is 1.14, so the wedge still covers travel 1.0 and the
// corners the panes never claim are eaten as before.
const float IAIDO_EAT_BEGIN = -0.10;   // = -IAIDO_ARRIVED_BACK, by contract
const float IAIDO_EAT_TAIL = 0.06;


float iaido_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float iaido_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = iaido_hash21(i);
	float b = iaido_hash21(i + vec2(1.0, 0.0));
	float c = iaido_hash21(i + vec2(0.0, 1.0));
	float d = iaido_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float iaido_fbm(vec2 p) {
	float s = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		s += iaido_vnoise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return s;
}


// ---- the three numbers both passes must agree on -------------------------

// How far past the surface's own strength the event is.
float iaido_stress(float fracture, float shatter) {
	return clamp(fracture * IAIDO_STRESS_PER_FRACTURE + shatter, 0.0, 1.0);
}

// This region's threshold, 0..1. High = gives way late.
float iaido_order(vec2 rel) {
	return 1.0 - iaido_fbm(rel * IAIDO_ORDER_FREQ + IAIDO_ORDER_ORIGIN);
}

// 1 once the stress has passed this region's threshold.
float iaido_ready(float order, float stress) {
	return smoothstep(
		order * IAIDO_READY_SLOPE,
		order * IAIDO_READY_SLOPE + IAIDO_READY_SOFT,
		stress);
}

// How far the fracture front has reached, in authored pixels from the cut.
float iaido_front(float fracture, float shatter) {
	return max(
		fracture * IAIDO_FRONT_PER_FRACTURE + shatter * IAIDO_FRONT_PER_SHATTER,
		0.001);
}

// 1 inside the front, 0 beyond it. `ad` is distance from the cut, in authored
// pixels.
//
// THE STRESS GATE — see IAIDO_CLAIM_CORE. This one is allowed to be wide.
float iaido_grown(float front, float ad) {
	return 1.0 - smoothstep(
		front * IAIDO_FRONT_CORE, front + IAIDO_FRONT_TAIL, ad);
}

// 1 where the panes have taken the surface over, 0 where it is still world.
//
// THE GLASS GATE — see IAIDO_CLAIM_CORE. This one must not be wide: it is the
// boundary of a filled region whose alpha replaces the picture, and whatever
// it reaches is deleted from the world and painted over.
float iaido_claimed(float front, float ad) {
	return 1.0 - smoothstep(
		front * IAIDO_CLAIM_CORE, front * IAIDO_CLAIM_TAIL, ad);
}

// 1 once the collapse has the frame, 0 through the whole of the hold.
//
// Opens the glass gate for every pane at once. This is not a net switching on:
// a surface coming apart is all of its pieces at once, and what the pieces
// expose is the void behind them.
float iaido_unleashed(float shatter) {
	return smoothstep(0.02, 0.34, shatter);
}

// How wide this region's seams open, 0..1. Never zero: at full stress every
// threshold has been passed and nothing may stay permanently sealed.
float iaido_weight(vec2 rel) {
	return mix(
		IAIDO_WEIGHT_MIN,
		1.0,
		smoothstep(0.18, 0.80,
			iaido_fbm(rel * IAIDO_WEIGHT_FREQ + IAIDO_WEIGHT_ORIGIN)));
}

// The one number the network is drawn with. `grown` must already include
// `arrived` and `ready` — this only applies the rigour and the dissolve.
float iaido_lit(
	float fracture, float shatter, float grown, float dissolve, float weight
) {
	return clamp(
			fracture * IAIDO_LIT_PER_FRACTURE + shatter * IAIDO_LIT_PER_SHATTER,
			0.0, 1.0)
		* grown * (1.0 - dissolve) * weight;
}


// ---- where on the slash -------------------------------------------------

// The along-cut tangent for a cut normal. The screen pass derives both from
// `cut_angle`; the pane pass only ever receives the normal, so it recovers the
// tangent the way the pair is actually related rather than by a second authored
// constant that could disagree.
vec2 iaido_tangent(vec2 nrm) {
	return vec2(nrm.y, -nrm.x);
}

// 0 at the end of the slash the blade entered, 1 at the end it left.
float iaido_travel(vec2 rel, vec2 tangent, float aspect) {
	float along = dot(rel, tangent);
	float along_half = abs(tangent.x) * aspect * 0.5 + abs(tangent.y) * 0.5;
	return clamp(along / max(along_half, 0.001) * 0.5 + 0.5, 0.0, 1.0);
}

// 1 once the front has passed `travel`, 0 before it. Mirrors
// `IaidoTuning.stream_at()` + `stream_arrived()` exactly.
float iaido_arrived(float stream, float travel) {
	float lead = stream * IAIDO_LEAD_OVERSHOOT;
	return 1.0 - smoothstep(
		lead - IAIDO_ARRIVED_BACK, lead + IAIDO_ARRIVED_FRONT, travel);
}
