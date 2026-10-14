shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, specular_disabled;

// ---------------------------------------------------------------------------
// SEKAI · 缚星链 ULTIMATE · THE HOLE (原位破口)
// ---------------------------------------------------------------------------
//
// The sheet has to be taken FROM somewhere, and that somewhere is the picture's
// proof that the skill is not an effect layer: the world behind the sheet is
// gone, and what is in its place is not dark scenery.
//
// ---------------------------------------------------------------------------
// WHY THIS IS A SEPARATE MATERIAL AND NOT PART OF THE SHEET
// ---------------------------------------------------------------------------
//
// They are the same mesh. Two MeshInstance3D share one ArrayMesh: one stays at
// the anchor frame with THIS material, the other is carried away by the shader
// with the captured world on it. Which means the hole's outline is the sheet's
// outline by construction — it cannot drift, and retuning the sheet's lobes
// retunes the wound with it. There is no second silhouette to keep in sync.
//
// ---------------------------------------------------------------------------
// WHAT IS IN THE OPENING
// ---------------------------------------------------------------------------
//
// The iaido line already established the answer for a wound in the world and it
// applies unchanged: NOTHING SAMPLED FROM THE WORLD. The iaido void is three
// noise fields drifting at three different rates, because differential motion is
// what the eye reads as depth and it is the only way to get depth out of
// something that is not made of anything.
//
// The same three fields are here, colder and slower, because this opening is not
// a cut through reality — it is a MISSING PIECE of it, and a missing piece should
// look less like a place and more like an absence.
//
// ---------------------------------------------------------------------------
// THE THING THIS FILE USED TO BE, AND WHY IT WAS DELETED
// ---------------------------------------------------------------------------
//
// V1 opened the wound where `r` was GREATER than the film's contracted rim. Since
// the film covered the whole frame and then contracted, "greater than the rim"
// meant "everywhere around it" — a black border with the world in a window. The
// user named it: 黑色不规则 Iris / Screen Mask, and asked for it to be deleted
// rather than improved.
//
// The fix is not a number, it is the removal of the comparison. There is no film
// rim here any more, because with the film gone the WHOLE plate is the wound and
// the plate is exactly as big as the piece that was taken. What is left in the
// fragment stage is the two real events below and nothing else.
//
// ---------------------------------------------------------------------------
// THE TWO EVENTS THIS MATERIAL CARRIES
// ---------------------------------------------------------------------------
//
//   REVEAL  the hole appears only where the sheet has already let go. It shares
//           the sheet's peel coordinate, so the wound opens behind the film
//           rather than switching on underneath it.
//   CLOSE   the world heals back from the rim inward, so the last thing on
//           screen is the world and not an effect. The bright edge travels in
//           with the front, which is what makes it a healing edge rather than a
//           fade.

uniform float clock = 0.0;
uniform float sheet_radius = 2.2;

// The sheet's own peel, so the two materials cannot disagree about where the
// separation front is.
uniform float peel = 0.0;

// 0 = open, 1 = healed. Driven by the tuning's `hole_close_at`.
uniform float close = 0.0;
// How strong the boundary is while the wound is fresh. Fades with `close`.
uniform float edge = 1.0;
// A last cold light in the opening while the core is still holding it open.
uniform float glow = 0.0;

varying float v_r;
varying vec2 v_q;
varying float v_front;

// A cheap value field. Three of these at different scales and speeds are the
// whole interior — see the note above on why nothing here is sampled.
float field(vec2 p, float t) {
	vec2 q = p * 3.7 + vec2(t * 0.31, -t * 0.19);
	return sin(q.x + sin(q.y * 1.7)) * 0.5 + 0.5;
}

void vertex() {
	// `COLOR.r`, AND NOT `COLOR.w`. `ChainRealitySheet._vert` writes
	// [ring fraction, boundary distance, peel, 1.0], so the fourth component is a
	// constant 1.0 — and reading it made every vertex of the wound claim to be ON
	// its own rim. That turned the rim fade, the healing front and the boundary
	// line into one uniform wash with no front in it at all.
	float r = COLOR.r;
	v_r = r;
	v_q = VERTEX.xy;
	float p = clamp(VERTEX.y / sheet_radius * 0.5 + 0.5, 0.0, 1.0);
	// THE SEPARATION FRONT, OVER THE WHOLE PLATE.
	//
	// V1 mapped this onto the middle band of the plate, because the plate was
	// nine metres across and the frame only ever saw `p` 0.225 to 0.775 of it —
	// a front spending four fifths of its travel off screen arrives as a switch
	// rather than as a sweep. THAT REASONING IS GONE WITH THE SIZE: the plate is
	// now a patch that fits inside the frame, its own height spans `p` 0.095 to
	// 0.905 (the outline dips to 0.81 of nominal on its short lobes), and the
	// front can therefore run the whole of it with a little overhang at each end
	// so the first and last moments of the peel are not two dead frames.
	float front = mix(0.02, 1.02, peel);
	v_front = 1.0 - smoothstep(front - 0.06, front + 0.02, p);
	// The wound does not bend. Only the film that left does.
}

void fragment() {
	float r = v_r;

	// ---- THE INTERIOR -----------------------------------------------------
	float a = field(v_q, clock);
	float b = field(v_q * 2.31 + vec2(11.0, 4.0), clock * 1.37);
	float c = field(v_q * 5.13 - vec2(3.0, 9.0), clock * 2.11);
	float depth = a * 0.5 + b * 0.32 + c * 0.18;

	vec3 col = mix(vec3(0.0025, 0.0035, 0.0055), vec3(0.0075, 0.0105, 0.0170), depth);
	// The interior is never a hard zero. A pure black patch in a lit scene is a
	// hole in the render, and the eye reads a render error faster than it reads a
	// void — but "not zero" and "navy blue" are two different claims, and the
	// first version of this was the second one: at 1280x720 the field under the
	// film measured (12, 28, 58) sRGB, a blue you could name, with a mottle you
	// could read as water. The user's word for what should be left behind is 黑屏.
	//
	// So the depth is still here — three fields at three rates, which is the only
	// thing that makes an absence read as having depth at all — but it now moves
	// the colour by a few thousandths of linear light instead of tripling it, and
	// the hue is neutral-cold rather than blue. Measured back: (9, 13, 19) to
	// (22, 27, 33), which is black with a floor to it.
	col += vec3(0.020, 0.030, 0.048) * pow(depth, 3.0) * 0.35;
	col += vec3(0.05, 0.10, 0.17) * glow * (1.0 - r) * 0.30;

	// ---- THE WOUND IS THE WHOLE PLATE, AND THAT IS THE FIX -----------------
	//
	// V1 DREW THE VOID ONLY WHERE `r` WAS OUTSIDE THE FILM'S CONTRACTED RIM:
	//
	//     float outside = smoothstep(contract - 0.012, contract + 0.012, r);
	//
	// which is an ANNULUS. Every pixel outside the contracted film was void, and
	// the film was a smaller shape sitting inside the frame — so the picture was a
	// black border around a window showing the world. That annulus is the iris.
	// The user's instruction about it is not a preference: DELETE THE BLACK IRIS.
	//
	// With the film gone, EVERY PART OF THE PLATE IT LEFT IS VOID, and the plate
	// is exactly as big as the film was. So there is no rim of the film to compare
	// against and nothing to be outside of: the two things still happening here
	// are the two events, and they are the only two masks left.
	//
	//   THE PEEL FRONT   the wound opens from the bottom up, behind the film's own
	//                    lower edge letting go, so the black arrives as a
	//                    travelling front rather than as a shape switching on.
	//   THE HEAL FRONT   `close` walks inward from the rim, so the world is handed
	//                    back from the edges of the wound rather than fading up
	//                    through it.
	float open_now = v_front;
	float front = 1.0 - close;
	float open_mask = 1.0 - smoothstep(front - 0.10, front + 0.02, r);

	// The edge itself: a thin cold line standing on the boundary — the rim of the
	// wound while it is fresh, and the travelling front as it heals. This is the
	// line that says the missing piece was TORN OUT rather than left out.
	float band = (1.0 - smoothstep(0.0, 0.055, abs(r - front))) * (1.0 - close * 0.35);
	col += vec3(0.62, 0.80, 1.00) * band * edge * 0.55;

	float alpha = open_mask * open_now;
	col *= 1.0 - close * 0.30;

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
