shader_type canvas_item;
render_mode unshaded;

// THE FRACTURE FIELD IS NOT DEFINED HERE.
//
// The network this pass draws is the same network the panes are cut with, and
// the two have to agree pixel for pixel. `iaido_fracture_field.gdshaderinc`
// holds the one definition; `iaido_glass_shard.gdshader` includes it too.
#include "res://vfx/iaido_fracture_field.gdshaderinc"

// ---------------------------------------------------------------------------
// SEKAI · Iaido reality crack (V7)
// ---------------------------------------------------------------------------
// THE ONE RULE
//
// After the blade has passed, this shader is NOT ALLOWED TO DRAW A LINE.
//
// V1 opened a 50px lit blue beam. V2 narrowed it to 23px and shaded it with a
// symmetric ramp — textbook cylinder shading — which over a flat arena read as a
// navy rod lying diagonally across the picture. V3 got the width down to 16px,
// made the fill asymmetric, and then drew a shadowed cross-section band plus a
// lit ivory lip along the entire length of the cut for the whole of the void
// hold. A continuous, evenly weighted, perfectly straight line across the whole
// frame is a UI separator, and it does not matter what colour it is.
//
// V7 IS ABOUT A DIFFERENT FAILURE, AND IT IS THE ONE THAT SURVIVED ALL OF THOSE.
//
// At the end of V6 the wound was the right width, the halves were displaced, the
// displacement carried the read, and the user still said:
//
//     完整画面 + 一条裂纹贴图
//
// — a whole picture with a crack texture on it. They were right, and the reason
// was not in this shader's edges at all. It was in three structural decisions:
//
//   1. THE GAP STILL SHOWED THE WORLD. The opening was filled with the frozen
//      frame sampled at an opposing parallax, on the theory that "the back of
//      reality" should be a dark, further-away, wrong copy of the same picture.
//      It reads as neither a hole nor a place. A crack you can still see the
//      world through is a crack in a texture.
//
//      WHAT IS IN THE OPENING NOW IS NOT SAMPLED FROM THE WORLD AT ALL. It is
//      the void's own structure, three noise fields drifting at three different
//      rates. Differential motion is what the eye reads as depth, and it is the
//      only way to get depth out of something that is not made of anything.
//
//   2. THERE WAS NO BROKEN EDGE. The band at the wound bent the world by 0.55px
//      and mixed it at 0.22 — a fifth of a pixel of effective movement, which is
//      to say the surface on either side of the cut was provably flat. A break
//      ends in a band of material that has CHANGED STATE: a near-black inner
//      edge, a few pixels of the world genuinely bending toward the wound, and —
//      only along a quarter of its length — a cold catch of light.
//
//   3. THE TWO HALVES WERE MIRROR IMAGES. Same magnitude, same axis, same plane,
//      opposite sign. No physical break does that, and the symmetry is what the
//      eye reads as "digital" — the PPT slide. Side A now takes 45% of the
//      travel and side B takes 55%, and the two images are tilted a few
//      hundredths of a degree relative to each other.
//
// THE CRACK NETWORK IS SECONDARY DETAIL, BY CONSTRUCTION.
//
// A uniform net switching on over an intact picture is a texture, and the mask
// this reads is a uniform Voronoi net, so a single reveal front makes one. Each
// region of the surface now owns a THRESHOLD from a low-frequency field, so as
// the stress rises the branches open one at a time — a short one here, a longer
// one there, some never — which is a sequence, not a switch. The drawn seam is
// halved at the same time and the DISPLACEMENT across each seam is raised,
// because a seam that moves the picture behind it is damage and a seam that only
// darkens it is ink.
//
// ORDER OF OPERATIONS MATTERS HERE. The wound geometry is computed BEFORE the
// world is sampled, because the edge band has to bend the sample and `open_px`
// does not depend on the sample. In V6 the geometry was built after the read and
// the bend had to be applied as a second, mixed sample — which is why it could
// never be more than a tint.
//
// WHAT THIS SHADER STILL DOES NOT DO
//
// The fracture topology is a BAKE, not a shader trick — see
// `ue5_lab/scripts/build_reality_fracture.py`. The current bake is a uniform
// 202-cell Voronoi with no primary cut and no branch hierarchy, and no amount of
// reveal order fixes that. `docs/UE5_VFX_LAB.md` carries the spec.
// ---------------------------------------------------------------------------

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// The UE5-baked reality fracture, in the same screen space as `screen_tex`.
uniform sampler2D crack_mask : filter_linear, repeat_disable;
uniform sampler2D edge_mask : filter_linear, repeat_disable;
uniform sampler2D flow_mask : filter_linear, repeat_disable;

uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform vec2 cut_center = vec2(0.5, 0.5);
uniform float cut_angle = -30.0;        // degrees, screen space
uniform float time = 0.0;
// The void's own clock. The director stalls it during the time stop, so the
// thing behind reality stops drifting at the same instant the world does. Read
// off wall time it kept moving through the pause and the stop did not land.
uniform float void_clock = 0.0;

uniform float focus = 0.0;              // how far the world has been drained
// HOW FAR THE DRAIN HAS SPREAD FROM THE KOIGUCHI, 0..1 of the frame.
//
// Colour does not switch off: it leaves the world from the mouth of the
// scabbard and spreads until the whole frame has gone. Passed separately from
// `focus` because the two are different questions — `focus` is HOW MUCH colour
// is gone where the drain has arrived, `grey_spread` is HOW FAR it has got.
uniform float grey_spread = 0.0;
uniform float void_open = 0.0;          // 0..1 presence of the wound
// The opening, in pixels @1080p. Always authored as `separation_px * gap_ratio`
// — never independently. See IaidoTuning's phase G.
uniform float gap_px = 0.0;
uniform float separation_px = 0.0;      // how far EACH half slid
uniform float depth_parallax = 0.010;
uniform float restore_pull = 0.0;
uniform float slide_px = 0.0;           // gravity slide, only after shatter
uniform float ivory_flash = 0.0;        // 30ms sheath-lock kiss
uniform float blade_flash = 0.0;        // the only line allowed: the blade
uniform float void_life = 1.0;
uniform float void_speed = 0.10;        // void drifts; the world does not

// ---- the two halves do not move alike ------------------------------------
// 0..1, ramping with the split. Drives the differential rotation only; the
// displacement itself is already proportional to `separation_px`.
uniform float split_amount = 0.0;
// Fraction of the travel that side A takes. Side B takes the rest, so the two
// images misregister by 2 x `separation_px` however this is set — it changes the
// BALANCE, not the amount.
uniform float split_bias = 0.45;
// Fraction of the separation that becomes along-cut slide. Shared with the
// pane offset in IaidoGlassLayer (tuning.split_shear) — if the two disagree,
// the glass and the world disagree about where the halves sit.
uniform float split_shear = 0.50;
uniform float split_rotation_a_deg = 0.05;
uniform float split_rotation_b_deg = -0.08;

uniform vec3 void_back_color = vec3(0.008, 0.027, 0.067);
uniform vec3 void_deep_color = vec3(0.024, 0.078, 0.165);
uniform vec3 void_lip_color = vec3(0.043, 0.165, 0.290);
uniform vec3 void_core_color = vec3(0.560, 0.740, 0.850);
uniform float void_edge_width_px = 3.0; // independent chipping of the two faces

// ---- the broken edge band ------------------------------------------------
uniform float edge_band_px = 6.0;       // width of the changed material
uniform float edge_refract_px = 3.5;    // how far the world bends toward it
uniform float edge_spec_strength = 0.22;
uniform float edge_spec_low = 0.56;     // fraction of the length that catches
uniform float edge_spec_high = 0.72;    // light, via a field along the slash
uniform vec3 edge_spec_color = vec3(0.72, 0.86, 0.96);

// ---- world drain ---------------------------------------------------------
// THE WORLD UNDER THE GLASS HAS TO GO, AND IT HAS TO GO WHERE THE GLASS IS.
//
// The shards are carrying the frame that was frozen in the hero hold. By the
// time they move the camera has settled and the FOV has opened, so the live
// world behind them no longer lines up with what is inside them: left visible,
// the panes read as a screenshot floated over the scene.
//
// So the world is CONSUMED exactly where the fracture front has already passed,
// and nowhere else. The two fronts are the same front — one event seen twice —
// which is what turns the collapse into the surface PEELING OFF something deep
// rather than a layer added on top of it.
//
// `stream` is how far along the slash that front has travelled, 0..1.
uniform float stream = 0.0;
// `devour` finishes the job at the end of the ceremony, after the blade is
// home: the far corners the stream never reached are eaten and the emptiness
// closes over the frame.
uniform float world_drain = 0.0;
uniform vec3 drained_world_color = vec3(0.014, 0.022, 0.046);
uniform vec3 drained_world_deep = vec3(0.004, 0.006, 0.016);
uniform float drain_crack_fade = 1.0;

uniform float fracture = 0.0;           // 0..1 stress crack reach
uniform float shatter = 0.0;            // 0..1 surface failure
uniform float dissolve = 0.0;           // cracks fading on restore
uniform float refract_px = 5.0;
uniform float shatter_px = 26.0;

uniform float wave_strength = 0.0;
uniform float wave_a = 0.0;
uniform float wave_b = 0.0;
uniform float wave_c = 0.0;
uniform float wave_suck = 0.0;
uniform vec2 sheath_uv = vec2(0.22, 0.80);

const vec3 IVORY = vec3(0.97, 0.95, 0.86);
// Half the diagonal of a 1080p frame in the authored pixels `ad` is measured
// in. The world drain front travels this far to swallow the whole frame.
const float FRAME_REACH_PX = 1120.0;

// hash21 / vnoise / fbm now live in iaido_fracture_field.gdshaderinc, because
// the pane pass draws the same field and a second copy would drift.


// ---------------------------------------------------------------------------
// Reverse compression shells.
//
// Radius decays late (exponent < 1) so a shell stays inside the frame for most
// of its short life and then collapses hard into the sheath mouth. The
// accelerating rhythm the design asks for comes from the shells being staged
// with decreasing durations, not from hiding them off-frame.
// Returns (inward pull, visible crest).
// ---------------------------------------------------------------------------
vec2 ring_profile(float len, float progress) {
	float radius = pow(1.0 - clamp(progress, 0.0, 1.0), 0.55) * 0.95 + 0.02;
	float ring = exp(-pow((len - radius) * 26.0, 2.0));
	float wake = exp(-pow((len - radius * 1.42) * 11.0, 2.0)) * 0.42;
	return vec2(ring + wake, ring);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = resolution.x / max(resolution.y, 1.0);
	float px = 1.0 / max(resolution.y, 1.0);          // one pixel, aspect units
	// Pixel amounts are authored against 1080p so the wound reads the same at
	// any resolution instead of swelling on small viewports.
	float sx = max(resolution.y, 1.0) / 1080.0;
	// One authored pixel, expressed in aspect units. Everything that has to be
	// "so many pixels wide" multiplies by this, and distances that need to be
	// compared against pixel figures divide by it.
	float px_s = sx * px;
	vec2 asp = vec2(aspect, 1.0);
	vec2 to_uv = 1.0 / asp;

	float a = radians(cut_angle);
	vec2 tangent = vec2(cos(a), sin(a));
	vec2 nrm = vec2(-sin(a), cos(a));

	// ---- the cut frame -----------------------------------------------------
	//
	// Every quantity the wound, the crack field, the edge band and the drain
	// share, computed once and at the top. `ad` is the signed distance from the
	// cut in AUTHORED pixels, which is the unit every width in this file is
	// authored in.
	vec2 rel = (uv - cut_center) * asp;
	float along = dot(rel, tangent);
	float d = dot(rel, nrm);
	float ad = abs(d) / px_s;
	float side = d >= 0.0 ? 1.0 : -1.0;
	// 0 at the end of the slash the blade entered, 1 at the end it left.
	float along_half = abs(tangent.x) * aspect * 0.5 + abs(tangent.y) * 0.5;
	float travel = clamp((along / max(along_half, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
	float vt = void_clock * void_speed;

	// ---- reverse compression (pre-cut) -------------------------------------
	// Refraction alone is invisible over flat colour, so the front also paints
	// a density edge that adapts to whatever is behind it. The final "suck"
	// drains everything into the sheath mouth at once.
	vec2 from_sheath = (uv - sheath_uv) * asp;
	float len_s = length(from_sheath);
	vec2 dir_s = from_sheath / max(len_s, 1e-4);
	vec2 rp1 = ring_profile(len_s, wave_a);
	vec2 rp2 = ring_profile(len_s, wave_b);
	vec2 rp3 = ring_profile(len_s, wave_c);
	float pull_sum = rp1.x + rp2.x * 0.76 + rp3.x * 0.55;
	float crest = (rp1.y + rp2.y * 0.80 + rp3.y * 0.60) * wave_strength;
	float trough = ((rp1.x - rp1.y) + (rp2.x - rp2.y) * 0.80 + (rp3.x - rp3.y) * 0.60) * wave_strength;
	float suck = exp(-len_s * 5.5) * wave_suck;
	vec2 pull = dir_s * (pull_sum * wave_strength * 0.045 + suck * 0.10);

	// ---- THE WOUND GEOMETRY ------------------------------------------------
	//
	// HOISTED ABOVE THE WORLD SAMPLE, AND THAT IS THE POINT.
	//
	// The edge band bends the world on its way past, so the band has to be
	// known before `screen_tex` is read. In V6 this block sat after the read,
	// which meant the bend could only be applied as a second sample mixed back
	// over the first — and a mix of two nearly identical samples is a tint, not
	// a displacement. No amount of tuning it up would have made the surface
	// look bent, because arithmetically it never was.
	//
	// There is still no drawn edge here. No shadowed cross-section, no lit lip,
	// no band of any kind: the opening is bounded only by its own content and by
	// the refraction outside it.
	float half_gap_px = 0.5 * gap_px;

	// RAGGED, NOT RULED.
	//
	// V4's chipping was a single ±2px wobble on a uniformly dark band, and over
	// a bright arena that composites to a black bar — the thing §B forbids,
	// arrived at from the other direction. Three changes fix the read:
	//
	//   * multi-scale chipping, so there are long shallow bays AND occasional
	//     deep bites rather than one even wobble;
	//   * a `kiss`: stretches where the two faces actually touch again. A break
	//     that has not fully opened does not have a clean slot down its middle;
	//   * separate profiles per face, so the two sides disagree with each other
	//     the way a real break does. Mirroring one profile is what makes a wound
	//     look die-cut.
	float jag_a = ((iaido_fbm(vec2(along * 21.0, 11.0)) - 0.5)
		+ (iaido_fbm(vec2(along * 63.0, 23.0)) - 0.5) * 0.55) * 2.0;
	float jag_b = ((iaido_fbm(vec2(along * 21.0, 71.0)) - 0.5)
		+ (iaido_fbm(vec2(along * 63.0, 83.0)) - 0.5) * 0.55) * 2.0;
	float chatter = (iaido_fbm(vec2(along * 190.0, 3.0)) - 0.5) * 2.0;
	float jag = (side >= 0.0 ? jag_a : jag_b) * void_edge_width_px * 1.9 + chatter * 2.4;
	float kiss = smoothstep(0.60, 0.80, iaido_fbm(vec2(along * 7.5, 41.0)));
	float open_px = max(half_gap_px * clamp(1.0 + jag * 0.105, 0.30, 2.10), 0.45);
	open_px *= 1.0 - kiss * 0.92;

	float in_void = (1.0 - smoothstep(open_px - 0.75, open_px + 0.75, ad)) * void_open;

	// Where in the opening this sample sits: 0 at the near face, 1 at the far
	// one. Deliberately asymmetric — a symmetric ramp is how you shade a
	// cylinder, and a shaded cylinder lying across the frame is a rod.
	//
	// The cross-section profile itself is applied further down, next to the
	// void it belongs to.
	float across = clamp(0.5 + 0.5 * (d / px_s) / max(open_px, 1e-5), 0.0, 1.0);

	// ---- THE TWO HALVES STOP LINING UP -------------------------------------
	//
	// Each half is translated rigidly along the cut normal, one way on each
	// side. Every building edge, horizon, floor line, sky boundary and
	// silhouette that crosses the wound steps sideways. That step is the entire
	// effect. It cannot be read as an overlay, because it is made of the world
	// itself.
	//
	// THE BIAS AND THE SHEAR.
	//
	// `amp` is 2 x the share, so the two images still misregister by exactly
	// 2 x `separation_px` — 0.90 on one side and 1.10 on the other, rather than
	// 1.00 and 1.00. The difference is invisible on its own and it is the
	// difference between a break and a slide transition.
	float amp = 2.0 * mix(1.0 - split_bias, split_bias, step(0.0, side));
	vec2 move = nrm * side * separation_px * amp * sx * px;
	// THE SHEAR COMPONENT.
	//
	// A displacement purely along the normal is ~87% vertical at a -30 degree
	// cut, and a mostly-vertical displacement only shows on HORIZONTAL edges.
	// The first V4 review put the wound through sky and bare floor, where there
	// are none, and a 13px step measured 5.8% of the frame in a pixel diff while
	// being invisible in the still. A real break is not a pure mode-I opening —
	// it shears — and adding the along-cut component is what makes every
	// VERTICAL silhouette (pillar edge, wall corner, enemy) misregister too.
	float shear = split_shear;
	move += tangent * side * separation_px * amp * shear * sx * px;
	if (side < 0.0) {
		move += vec2(-0.16, 1.0) * slide_px * sx * px;
	}
	move += nrm * side * restore_pull * sx * px;

	// ---- THE BROKEN EDGE ---------------------------------------------------
	//
	// A break does not end at its outline; it ends in a band of material that
	// has changed state. Without one, the boundary of the wound is the boundary
	// of a shape, and the eye has no reason to read it as anything other than a
	// cut-out.
	//
	//   band      1 at the lip of the hole, 0 at `edge_band_px` away, squared so
	//             the change is concentrated where a bevel would be.
	//   bend      the world bends TOWARD the wound by up to `edge_refract_px`.
	//             This is the part that proves the surface is not flat: at 3.5px
	//             it visibly pulls the picture into the cut over a 6px band, and
	//             it is a real displacement of the sample rather than a tint.
	float band = 1.0 - smoothstep(open_px, open_px + edge_band_px * sx, ad);
	float band_tight = band * band;
	vec2 edge_bend = nrm * side * band_tight * edge_refract_px * sx * px_s;

	// ---- the fracture network ----------------------------------------------
	//
	// The network appears at the cut first, at the ENTRY end of the slash
	// first, and reaches the far corner last. Both the world and the glass read
	// the same mask and the same order, so at detach they agree.
	float seam = texture(crack_mask, uv).r;
	float prox = texture(edge_mask, uv).r;
	vec2 flow = texture(flow_mask, uv).rg * 2.0 - 1.0;

	// NOT ALL AT ONCE.
	//
	// A single reveal front opens every seam inside it on the same frame, which
	// is a net switching on. The mask this reads is a uniform Voronoi net — 202
	// cells, evenly spread, no hierarchy — so a net is exactly what it looked
	// like. Each region of the surface owns a THRESHOLD from a low-frequency
	// field: as the stress rises, the branches open one at a time, and which one
	// comes first is a property of where it is rather than of when the shader
	// got to it.
	//
	// ALL FOUR NUMBERS COME FROM THE SHARED FIELD, NOT FROM HERE. `iaido_stress`
	// / `iaido_order` / `iaido_ready` are the same calls the pane shader makes
	// with the same arguments, which is what makes the two nets coincide where a
	// pane is still lying over live world. See
	// `iaido_fracture_field.gdshaderinc`.
	float stress = iaido_stress(fracture, shatter);
	float order = iaido_order(rel);
	float ready = iaido_ready(order, stress);

	// THE HEAD RUNS PAST THE END OF THE LINE — see the shared field for why.
	float lead = stream * IAIDO_LEAD_OVERSHOOT;
	float arrived = iaido_arrived(stream, travel);

	float front = iaido_front(fracture, shatter);
	// HOW FAR OUT OF THE WOUND THE GLASS HAS GROWN. 玻璃从裂痕蔓延.
	//
	// The front is a DISTANCE FROM THE CUT, not a position along it. The panes
	// exist only inside it (`IaidoTuning.grown_at()`), so this same number has
	// to gate the EAT below as well — otherwise the world would be consumed
	// across the whole frame while the glass only covered a band of it, and the
	// ceremony would spend the glass phase looking through a hole at nothing.
	// The contract is old and unchanged: what the stream eats is exactly what
	// the panes claim. Only the shape of the front changed, from a sweep along
	// the slash to a band growing out of it.
	float grown_reach = iaido_grown(front, ad);
	float grown = grown_reach * arrived * ready;
	// NOT EVERY SEAM OPENS EQUALLY — see the shared field. A low-frequency field
	// decides which regions of the surface actually gave way, so some seams open
	// wide and others barely show.
	float weight = iaido_weight(rel);
	float lit = iaido_lit(fracture, shatter, grown, dissolve, weight);
	float crack = clamp(seam * lit, 0.0, 1.0);
	// Each micro-cell's picture slides outward from its own centre, so the
	// seams genuinely tear instead of just being darkened. THIS is the crack:
	// the displacement is the damage and the seam below only deepens it.
	vec2 push = flow * prox * lit * refract_px * px_s;

	// ---- the sample --------------------------------------------------------
	vec2 source = uv + (pull + push + edge_bend - move) * to_uv;

	// THE TWO IMAGES ARE NOT QUITE PARALLEL.
	//
	// A few hundredths of a degree of differential rotation, applied about the
	// cut centre so it costs nothing at the wound and grows toward the edges of
	// the frame. Nobody will identify it. It is there so the two halves are not
	// provably the same picture translated along one axis, which is the read
	// that says "slide transition".
	//
	// The image turns by `rot`; the sample therefore turns by `-rot`.
	float rot = split_amount * radians(side >= 0.0 ? split_rotation_a_deg : split_rotation_b_deg);
	if (abs(rot) > 0.0000001) {
		float cr = cos(rot);
		float sr = sin(rot);
		vec2 off = (source - cut_center) * asp;
		off = vec2(off.x * cr + off.y * sr, off.x * -sr + off.y * cr);
		source = cut_center + off * to_uv;
	}

	// A little perspective so the cut face reads as having thickness.
	float depth = side < 0.0 ? depth_parallax : -depth_parallax * 0.7;
	source = cut_center + (source - cut_center) * (1.0 + depth * step(0.001, separation_px));
	source = clamp(source, vec2(0.0015), vec2(0.9985));

	vec3 world = texture(screen_tex, source).rgb;
	// Chromatic split across the fracture: only cracks that visibly bend the
	// image behind them read as transparent material rather than as markers.
	if (crack > 0.02) {
		vec2 chroma = push * to_uv * 0.55;
		vec2 s2 = clamp(source + chroma, vec2(0.0015), vec2(0.9985));
		vec2 s3 = clamp(source - chroma, vec2(0.0015), vec2(0.9985));
		world = vec3(texture(screen_tex, s2).r, world.g, texture(screen_tex, s3).b);
	}

	// ---- THE VOID IS NOT MADE OF THE WORLD ---------------------------------
	//
	// THE CORRECTION V7 EXISTS FOR.
	//
	// V4 through V6 filled this opening with the frozen frame sampled at a
	// smaller, opposing parallax. The intent was "the back of reality": a dark,
	// further-away, wrong version of the same picture, so the gap would read as
	// somewhere rather than as a fill. What it read as was the world continuing
	// behind a dark line — because it WAS the world, continuing behind a dark
	// line — and that is why the whole effect could be described, accurately, as
	// 完整画面 + 一条裂纹贴图.
	//
	// A hole does not have a picture in it. What is behind this one is built
	// only from the void's own components: three fields of noise at three
	// frequencies, drifting at three different rates. The differential motion is
	// the whole trick — the eye reads layers moving at different speeds as
	// layers at different distances, and it is the only way to get depth out of
	// something that contains nothing.
	//
	// `void_life` gates the whole thing so it can be switched off; `wall` is how
	// deep into the opening this sample sits.
	float d1 = iaido_fbm(vec2(along * 1.60 + vt * 0.13, across * 1.45 - vt * 0.09));
	float d2 = iaido_fbm(vec2(along * 3.70 - vt * 0.22, across * 2.95 + vt * 0.17));
	float d3 = iaido_fbm(vec2(along * 8.30 + vt * 0.34, across * 6.90 - vt * 0.26));
	vec3 depth_field = void_back_color;
	depth_field = mix(depth_field, void_deep_color * 0.80, d1 * 0.58);
	depth_field = mix(depth_field, void_deep_color * 1.30, d2 * 0.34);
	depth_field += void_lip_color * d3 * 0.14 * void_life;
	// The near face is the darkest thing in the frame and the far side of the
	// opening resolves out of it, so the gap has a floor rather than a fill.
	//
	// THE CROSS-SECTION WAS TOO STEEP FOR THE WIDTH IT HAS.
	//
	// `pow(across, 1.55)` describes a chasm seen at a wide angle: near-black at
	// both faces, resolving to the far field only across the middle. At the
	// width this wound actually opens — about twelve authored pixels, eight at
	// 720p — that profile left the near field occupying almost the whole slot
	// and the far field a couple of pixels in its centre. The result was that
	// the hole read as a BLACK LINE, which is the one thing §1 forbids the
	// primary effect to be, arrived at without any black line being drawn.
	//
	// The peak is unchanged; only its distribution is. Below 1 the profile is
	// closer to flat, so the depth reaches near the lips and the slot reads as
	// depth instead of as a crack in a print.
	float wall = pow(across, 0.78);
	vec3 void_col = mix(void_back_color * 0.44, depth_field, smoothstep(0.06, 0.70, wall));
	void_col += void_core_color * pow(d3, 8.0) * 0.45 * void_life * wall * wall;

	// ---- the world is consumed, not dimmed ---------------------------------
	//
	// THE WORLD IS NOT DIMMED HERE, IT IS EATEN.
	//
	// An earlier version mixed the world toward a dark colour. That is a
	// brightness control: every silhouette, every edge, every bit of the arena
	// is still in frame, just quieter, and the eye reads it as someone turning
	// the lights down. It looked like a mistake because it was one.
	//
	// TWO FRONTS, ONE ABSENCE.
	//
	//   `stream`  eats exactly what the fracture front has already turned over,
	//             and it follows the SAME wedge. The panes arrive and the world
	//             behind them is already gone, so the glass is not sitting on a
	//             picture — it IS the part of the surface that came away.
	//   `devour`  finishes the job at the end of the ceremony, after the blade
	//             is home. It is a front out of the wound in every direction at
	//             once, so the corners the wedge never reached are taken too.
	float eaten = 0.0;
	// THE DEVOUR. Only evaluated when it is actually running: `reach` carries a
	// per-point wobble, and wobble is signed, so computing this unconditionally
	// leaves the front sitting tens of pixels the WRONG side of the wound at
	// world_drain = 0 and eats a ragged band along the cut line for the whole
	// ceremony. That was a real regression — the band is what a stray dark
	// streak along the slash direction looks like.
	if (world_drain > 0.001) {
		float wobble = (iaido_fbm(vec2(along * 5.2, 17.0)) - 0.5) * 0.085
			+ (iaido_fbm(vec2(along * 21.0, 61.0)) - 0.5) * 0.030;
		float reach = (world_drain * 1.06 + wobble) * FRAME_REACH_PX;
		float eaten_edge_px = 26.0 * sx;
		eaten = 1.0 - smoothstep(reach - eaten_edge_px, reach + eaten_edge_px, ad);
	}
	if (stream > 0.001) {
		// The same wedge the glass reads, and its boundary is the PANE'S OWN
		// opaque boundary (lead − IAIDO_ARRIVED_BACK): a point may stop
		// existing only once the glass that replaces it is fully opaque. The
		// tail keeps the change arriving as a stream rather than a wipe.
		// ...AND ONLY WHERE THE GLASS HAS GROWN TO. `grown_reach` is the same
		// term the pane's opacity is multiplied by in `IaidoGlassLayer.stage()`,
		// so the corners the front has not reached keep their world. They are
		// taken later, by the devour, which is a front out of the wound in every
		// direction at once and does not need the slash to point anywhere.
		float wedge = 1.0 - smoothstep(
			lead + IAIDO_EAT_BEGIN, lead + IAIDO_EAT_BEGIN + IAIDO_EAT_TAIL, travel);
		eaten = max(eaten, wedge * grown_reach);
	}
	// THE VOID IS NOT PERMANENT.
	//
	// `stream` saturates and STAYS saturated — it is "how far the front has
	// travelled", and travelling is not something a front un-does. So the wedge
	// above holds `eaten` at 1 for the entire rest of the ceremony, and the
	// restore could not bring the world back: the ceremony ended on an empty
	// frame with the sword floating in it. Measured at t=9.89, the last frame of
	// the timeline.
	//
	// `dissolve` is the restore's own clock, and it is already what the cracks
	// and the vitrification read to know they are being reversed (lines with
	// `1.0 - dissolve` above). Gating the emptiness with the same term is the
	// whole fix, and it is the right one: reality closing back over the wound
	// means nothing the stream ate may be permanent.
	eaten *= 1.0 - dissolve;
	if (eaten > 0.001) {
		// What is behind the front. Deliberately built ONLY from the void's own
		// components — the moment any of it is taken from the world it stops
		// being an absence and goes back to being a dark copy.
		vec3 empty = mix(drained_world_color, drained_world_deep, 0.16 + 0.84 * d1);
		// The far wall of the opening, resolving only well inside it.
		empty += void_lip_color * (0.09 + 0.30 * d2) * void_life;
		empty += void_core_color * pow(d1, 7.0) * 0.18 * void_life;
		world = mix(world, empty, eaten);
	}

	// ---- the surface turns to glass as the front passes --------------------
	//
	// A cold sheen and a small lift, on exactly the same wedge the world is
	// being eaten on. The two are one event: the reason the pane can leave is
	// that the surface has stopped being world and started being glass. Without
	// this the change reads as a hole opening next to a pane rather than as the
	// pane being the thing that came away.
	float vitrified = arrived * grown_reach * clamp(fracture * 1.25, 0.0, 1.0) * (1.0 - dissolve);

	// ---- composite ---------------------------------------------------------
	vec3 col = mix(world, void_col, in_void);

	// The material change, on the same wedge. Kept small: this is the surface
	// becoming glass, not the frame getting a light put on it.
	col = mix(col, col * vec3(0.93, 0.97, 1.07) + vec3(0.020, 0.030, 0.052), vitrified * 0.40);

	// ---- the edge band, on the world side ----------------------------------
	//
	// Only the SPECULAR half lives here: the near-black inner edge is drawn by
	// the void's own `smoothstep(0.06, 0.70, wall)` ramp, and the refraction is
	// already in the sample. What is left is the catch of light.
	//
	// NOT ALONG THE WHOLE LENGTH. An evenly lit edge is a neon slash and a neon
	// slash is a UI element; the field along the slash lights roughly a quarter
	// of it, in irregular stretches, and the rest stays dark.
	float seg = iaido_fbm(vec2(along * 1.35, 88.0));
	float lit_seg = smoothstep(edge_spec_low, edge_spec_high, seg);
	col += edge_spec_color * band_tight * lit_seg * edge_spec_strength
		* void_open * (1.0 - in_void) * (1.0 - dissolve);

	// ---- the seam is secondary detail --------------------------------------
	//
	// §1: the drawn crack line is allowed to exist and is NOT allowed to carry
	// the read. V6 had a dark core removing up to 0.80 of the surface's value
	// along every boundary plus a lit shoulder on top, which over a uniform net
	// is a texture laid on a picture. Halved, and the displacement above was
	// raised to take over the job.
	//
	// Which one dominates is still decided by the surface behind it — a bright
	// line over a white floor is invisible, and this arena is mostly white floor.
	//
	// 裂缝大一点. The two thresholds were opened (0.60/0.14 -> 0.52/0.10) so the
	// seams are drawn WIDER without being drawn stronger: `crack` itself is
	// untouched and comes from the same mask, the shared field and the same
	// displacement as before. Widening is the honest reading of "make the cracks
	// bigger" — the alternative, raising the strength, is 更多特效 by another
	// name and it would put the network back in front of the displacement.
	float luma_col = dot(col, vec3(0.299, 0.587, 0.114));
	float bright_bg = smoothstep(0.30, 0.85, luma_col);
	float crack_core = smoothstep(0.52, 0.96, crack);
	float crack_shoulder = smoothstep(0.10, 0.46, crack) * (1.0 - crack_core);
	// The network belongs to the surface that is leaving, so it goes with it.
	// A crack drawn over an empty void is a net hanging in nothing.
	float crack_alive = (1.0 - in_void) * (1.0 - eaten * drain_crack_fade);
	col = mix(col, col * 0.46, crack_core * (0.20 + 0.24 * bright_bg) * crack_alive);
	col = mix(col, vec3(0.93, 0.95, 0.92), crack_shoulder * (0.16 - 0.11 * bright_bg) * crack_alive);

	// Surface failure is not tessellated in the shader. `shatter` widened `push`
	// above and deepened `crack`, and the pieces that actually come apart are
	// the real shard meshes on the layer above — one tessellation, from the UE5
	// bake, used by both. Two unrelated patterns was the bug.

	// The compression front. Refraction alone vanishes over flat colour, so the
	// pressure edge is painted too — but a white ring on a white floor reads as
	// a magic circle. The band adapts: dark over bright surfaces, lit over dark.
	float luma_here = dot(col, vec3(0.299, 0.587, 0.114));
	float crest_dark = smoothstep(0.28, 0.78, luma_here);
	float crest_lit = smoothstep(0.72, 0.18, luma_here);
	col -= vec3(0.095, 0.115, 0.150) * crest * crest_dark * 1.15;
	col += vec3(0.360, 0.450, 0.600) * crest * crest_lit * 0.65;
	col -= vec3(0.045, 0.055, 0.072) * trough * 0.55;
	col -= vec3(0.070, 0.085, 0.115) * suck * crest_dark * 0.55;

	// ---- THE COLOUR LEAVES FROM THE KOIGUCHI OUTWARD ------------------------
	//
	// The grey is not a state the world is switched into, it is something the
	// SWORD does. Colour drains out of the world starting at the mouth of the
	// scabbard and spreading until the whole frame has gone, and that spread
	// runs for the entire two seconds of the charge. A uniform desaturation is
	// a filter, and a filter has no cause — it only means the camera changed.
	// Anchoring the change to a point in the world makes the hold visibly DO
	// something, which is the entire job of that hold.
	//
	// The result is not black and white. A pure luma mix is a camera setting; a
	// cold, slightly lifted grey is a material. The void is excluded on both
	// counts so the two are never confused for each other.
	//
	// `focus` is HOW MUCH colour is gone where the drain has arrived;
	// `grey_spread` is HOW FAR it has got. They are separate questions.
	float grey_len = length((uv - sheath_uv) * asp);
	float grey_reach = grey_spread * 2.60;
	float grey_feather = mix(0.75, 0.45, clamp(grey_spread, 0.0, 1.0));
	float grey_field = 1.0 - smoothstep(grey_reach - grey_feather, grey_reach, grey_len);
	float drained = clamp(focus * grey_field, 0.0, 1.0);

	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 grey_glass = vec3(gray) * vec3(0.90, 0.95, 1.04) + vec3(0.014, 0.019, 0.030);
	col = mix(col, grey_glass, drained * 0.96 * (1.0 - in_void));
	// The contrast lift and the frame pressure stay global: they are the
	// ceremony closing in, not the drain arriving.
	col = (col - 0.5) * (1.0 + focus * 0.06) + 0.5;

	vec2 vig = uv * 2.0 - 1.0;
	col *= 1.0 - smoothstep(0.45, 1.7, dot(vig, vig)) * focus * 0.18;

	// THE ONLY LINE THIS SHADER IS ALLOWED TO DRAW.
	//
	// The blade's own passage: 1-3px wide at 1080p, alive for 30ms, gone before
	// the next frame. Everything after it has to come from the world moving.
	col += IVORY * blade_flash * (1.0 - smoothstep(0.0, 2.0 * sx * px, ad));
	// The sheath-lock kiss, centre weighted so it is a beat and not a wash.
	col += IVORY * ivory_flash * (1.0 - smoothstep(0.0, 0.55, length(vig)));

	COLOR = vec4(col, 1.0);
}
