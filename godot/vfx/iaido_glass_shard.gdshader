shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_opaque, shadows_disabled;

// THE FRACTURE FIELD IS NOT DEFINED HERE.
//
// These panes ARE pieces of the world, so the network drawn inside them is the
// same network the world pass draws over the same picture, at the same pixels.
// `iaido_fracture_field.gdshaderinc` holds the one definition of it.
#include "res://vfx/iaido_fracture_field.gdshaderinc"

// ---------------------------------------------------------------------------
// SEKAI · Iaido reality glass — a pane of the world, not a tinted shape.
//
// WHAT WENT WRONG BEFORE
//
// Every previous version gave each shard a uniform glassy body tint. That is a
// wrong idea dressed up as a right one: a shard that is a single flat colour
// cannot be a piece of anything. Fourteen grey-blue polygons flying past the
// camera read as confetti, and no amount of rim lighting fixes it.
//
// A shard of broken reality has to be a PIECE OF THE PICTURE. So:
//
//   * the vertex UV is the position this vertex had in the shattered plane,
//     in screen half-height units;
//   * the fragment turns that back into a screen UV and samples the FROZEN
//     world captured at the hero frame;
//   * so the building, the ground, the sky and the enemy are all still inside
//     the glass, chopped along the fracture lines and carried along with it;
//   * and because UV is welded to the vertex, the image travels, spins and
//     tilts with the pane, which is the thing that makes it read as material.
//
// At t = 0 of the collapse every shard is exactly where it was cut from, so the
// panes reconstruct the original frame. That is the acceptance test.
//
// The glass read then comes from three things layered on top of the image: a
// thin bright fracture rim, a grazing sheen at the edges, and a lens-like
// refraction that pushes the sampled image outward from the pane's centre.
// ---------------------------------------------------------------------------

// The frozen world, captured ONCE at the hero freeze frame by
// IaidoGlassLayer.capture_world().
uniform sampler2D world_capture : filter_linear, repeat_disable;

// Diagnostic switch, never on in a real performance.
uniform float debug_raw = 0.0;

// The FINE fracture network, baked in the UE5 lab. It is authored in exactly
// the same plane space as `world_capture`, so `uv` below indexes it directly
// and the crack network stays welded to the picture across every shard
// boundary — the whole sheet cracked as one surface, then broke into pieces.
uniform sampler2D crack_mask : filter_linear, repeat_disable;
// Soft proximity to the seam (0 at the seam, 1 in the middle of a micro-cell).
uniform sampler2D edge_mask : filter_linear, repeat_disable;
// Per-micro-cell outward direction, 0.5-centred, so the image inside each
// micro-cell can be displaced away from its own seam.
uniform sampler2D flow_mask : filter_linear, repeat_disable;

// The plane the fracture was laid out on, in screen half-height units.
uniform float capture_half = 1.15;
uniform float capture_aspect = 1.7777;
// This pane's centre in the same units, so the lens push has an origin.
uniform vec2 shard_centre = vec2(0.0, 0.0);

// THE SPLIT'S SAMPLE COMPENSATION.
//
// The pane's GEOMETRY is displaced by its side's share of the separation (the
// glass continues the cut — see IaidoGlassLayer.stage). But its CONTENT must
// stay pinned to the world's displaced SURFACE, not to the frozen screen: the
// capture is a screen image, already carrying the split, so sampling it at the
// vertex's original UV would displace the picture a SECOND time and snap every
// pane's content by one extra separation the moment it takes over the world.
// The layer hands this pane the negative of its own uv displacement, and the
// capture is read through it. The crack masks stay on the unshifted uv — the
// network is welded to the surface, not to the screen.
uniform vec2 split_sample = vec2(0.0);

// --- crack propagation ---------------------------------------------------
// THE THREE NUMBERS THE WORLD PASS IS DRAWN WITH, PASSED IN RATHER THAN
// RECOMPUTED. §H: after the world is cut there are only a few stress lines,
// and the cracks then grow OUTWARD from the wound.
//
// These used to be `crack_front` / `crack_reveal`, driven from this layer's own
// `span(time, glass_start, glass_stream_end)` ramps. That was a second clock for
// a thing that already had one, and it showed: the glass was crackling out on a
// fast ease while the world was still on a slow one, so a region could be weak
// in one layer and strong in the other at the same instant. Now the director
// reads `IaidoTuning.fracture_at()` / `shatter_at()` / `stream_at()` — the same
// values it pushes to the world pass — and hands them here.
uniform float fracture = 0.0;    // 0..1 stress crack reach
uniform float shatter = 0.0;     // 0..1 surface failure
uniform float dissolve = 0.0;    // cracks fading on restore
uniform float stream = 0.0;      // how far along the slash the front has run
// The cut's normal, in the shared field's frame. See the include.
uniform vec2 plane_cut_normal = vec2(0.5, 0.8660254);
// How far the picture slides inside a micro-cell once it has cracked. In plane
// units. This is what makes the network read as material failure rather than
// as a texture drawn on top of the image.
uniform float micro_shift = 0.012;
// THE SEAM IS SECONDARY DETAIL, AND THESE TWO NUMBERS ARE THE WHOLE REASON.
//
// §1: the drawn crack line is allowed to exist and is NOT allowed to carry the
// read. These panes composite OVER a world pass that has already drawn this
// exact network at these exact pixels, so a strong seam here doubles a seam
// that is already there — which is how a hero frame ends up looking like a
// phone screen with a spiderweb painted on it. Halved, and the displacement
// (`micro_shift` above, and the world pass's `refract_px`) takes over the job:
// a seam that moves the picture behind it is damage, a seam that only darkens
// it is ink.
uniform float crack_darken = 0.26;
uniform float crack_glint = 0.10;

uniform float opacity = 0.0;
// Body alpha is high on purpose. The brief for this pass is that the player can
// see the building and the ground INSIDE each shard, which only works if the
// captured image is what you are mostly looking at. The glass read comes from
// the rim and the sheen, not from making the body see-through.
uniform float body_alpha = 0.92;
uniform vec3 edge_tint = vec3(0.86, 0.93, 1.0);
// The rim was 0.85 and it made every pane read as a white-edged card. The
// boundary of a piece of broken world is glass, not a border: it should be
// legible and nothing more.
uniform float edge_gain = 0.22;
uniform float fresnel_gain = 0.12;
// The lens strength. At 0.030 each pane displaced its own copy of the picture
// by up to ~19px, and 18 panes each misplacing the image by a different amount
// composites to a mosaic — the exact opposite of §M's requirement that the
// pieces read as ONE surface. A pane of glass is a very weak lens; this is now
// a few pixels at the outer edge of each piece.
uniform float refraction = 0.009;
// A little per-shard desaturation, so the panes read as glass over the image
// rather than as stickers of it. Kept small: the content is the point.
uniform float glass_tint = 0.06;

varying vec2 orig_plane;
varying float rim_v;
varying float fresnel_v;

void vertex() {
	// UV is not a texture coordinate here. It is the vertex's ORIGINAL position
	// on the shattered plane, which is why the world image stays welded to the
	// pane no matter how the pane moves.
	orig_plane = UV;
	rim_v = COLOR.r;

	// Computed per vertex and interpolated: robust in unshaded mode, where the
	// fragment normal is not guaranteed.
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - world_pos);
	fresnel_v = pow(1.0 - abs(dot(world_normal, to_camera)), 3.0);
}

// plane units -> normalised screen uv (y flipped: the plane's +y is up).
vec2 plane_to_uv(vec2 p) {
	return vec2(
		0.5 + p.x / (2.0 * capture_half * capture_aspect),
		0.5 - p.y / (2.0 * capture_half)
	);
}

void fragment() {
	// Back to a screen UV. y is flipped because the capture is a screen image
	// and the plane's +y is up.
	vec2 uv = plane_to_uv(orig_plane);

	// Diagnostic: show the capture exactly as sampled, with none of the glass
	// treatment. Driven by SEKAI_RAW_CAPTURE. If the panes assemble into the
	// frozen frame under this switch, the mapping is right and anything wrong
	// in the normal path is treatment, not geometry.
	if (debug_raw > 0.5) {
		ALBEDO = texture(world_capture, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
		ALPHA = opacity;
	} else {

	// --- how cracked is this fragment? -----------------------------------
	//
	// THE SAME FIELD THE WORLD PASS USES, FROM THE SAME DEFINITION.
	//
	// `rel` puts this fragment into the screen pass's frame:
	// `plane_to_uv()` above is the inverse of this conversion, so a point at
	// plane coordinate p lands on the same screen pixel here as there. Every
	// call below is the same call the world pass makes, with the same numbers.
	// Where a pane is still lying over live world the two nets coincide instead
	// of doubling; where a pane has come away it carries the cracks it was cut
	// with, which is the whole reason a pane reads as a piece of the surface
	// rather than as a sticker of it.
	vec2 rel = vec2(orig_plane.x, -orig_plane.y) / (2.0 * capture_half);
	// `plane_cut_normal` is the screen pass's own `nrm`, already in this frame.
	float ad = abs(dot(rel, plane_cut_normal)) * IAIDO_AUTHORED_PX;

	float stress = iaido_stress(fracture, shatter);
	float order = iaido_order(rel);
	float ready = iaido_ready(order, stress);

	vec2 tangent = iaido_tangent(plane_cut_normal);
	float travel = iaido_travel(rel, tangent, capture_aspect);
	float arrived = iaido_arrived(stream, travel);

	float front = iaido_front(fracture, shatter);
	// `grown` stays the STRESS number: it decides how much of the crack network
	// this pane carries, and the network is allowed to reach the whole front.
	float grown = iaido_grown(front, ad) * arrived * ready;
	// `claim` is the GLASS number, and it is what the ALPHA below is gated on.
	// A pane may only be opaque where the world underneath it has actually been
	// taken; anywhere else it is a card lying over live picture, and a mosaic of
	// cards over an intact frame is the exact read this pass exists to avoid.
	// The world's eat calls the SAME function, so the pane and the hole it fills
	// are the same shape by construction rather than by tuning.
	float claim = max(iaido_claimed(front, ad), iaido_unleashed(shatter));
	float weight = iaido_weight(rel);
	float lit = iaido_lit(fracture, shatter, grown, dissolve, weight);

	float seam = texture(crack_mask, uv).r;
	float prox = texture(edge_mask, uv).r;
	vec2 flow = texture(flow_mask, uv).rg * 2.0 - 1.0;

	// Refraction: a pane of glass is a weak lens, so the image inside it is
	// pushed outward from the pane's own centre, more so at grazing angles.
	vec2 from_centre = orig_plane - shard_centre;
	vec2 push = from_centre * refraction * (0.35 + fresnel_v);

	// The picture physically slides inside a cracked micro-cell, away from its
	// own seam. Without this the network is an overlay; with it, the surface has
	// come apart. `slide` is in plane units, so it is converted like `uv`.
	vec2 slide = flow * prox * lit * micro_shift;
	vec2 slide_uv = vec2(
		slide.x / (2.0 * capture_half * capture_aspect),
		-slide.y / (2.0 * capture_half)
	);

	vec3 world = texture(world_capture, clamp(uv + split_sample + push + slide_uv, vec2(0.0), vec2(1.0))).rgb;
	// A trace of chromatic split at the very edges of the pane, where the glass
	// is thickest. Small enough never to read as an outline.
	if (fresnel_v > 0.01) {
		vec2 chroma = push * fresnel_v * 0.7;
		world = vec3(
			texture(world_capture, clamp(uv + split_sample + push + chroma, vec2(0.0), vec2(1.0))).r,
			world.g,
			texture(world_capture, clamp(uv + split_sample + push - chroma, vec2(0.0), vec2(1.0))).b
		);
	}

	// Glass over the image, not a tint replacing it.
	float luma = dot(world, vec3(0.299, 0.587, 0.114));
	vec3 body = mix(world, vec3(luma), glass_tint);

	// The fine network: the image loses a little light along each seam, and the
	// tightest pixel of the seam catches a thin glint. No bright line is drawn
	// anywhere else — this is glass, not an outline.
	float seam_lit = seam * lit;
	body *= 1.0 - crack_darken * seam_lit;
	body += edge_tint * pow(seam, 3.0) * lit * crack_glint;

	// THE PANE'S BOUNDARY IS A FRACTURE, SO IT OBEYS THE FRACTURE'S CLOCK.
	//
	// This was `edge_tint * rim * edge_gain`, with no clock on it at all. The
	// panes tile the whole frame, so that drew a bright border around every one
	// of them from the first frame they existed — evenly lit, everywhere, over a
	// complete picture. It is the same fault as drawing the seam with no
	// threshold, one scale up, and it is what made the fracture stage read as a
	// net laid over the image rather than a surface coming apart.
	//
	// A piece of broken world has a far quieter edge than that. Most of the
	// pane border is just a THINNING of the glass — a slight loss of light right
	// at the join, plus the grazing sheen that is already there. It only becomes
	// a lit line where the crack language has actually arrived, and `lit`
	// carries the stagger, the front and the per-region weight, so the network
	// opens a branch at a time instead of switching on as a whole.
	float rim = smoothstep(0.42, 1.0, rim_v);
	float rim_glass = rim * (1.0 - lit);
	float rim_break = rim * lit;
	vec3 edge = edge_tint * rim_break * edge_gain
		+ vec3(0.62, 0.70, 0.82) * rim_glass * edge_gain * 0.30;
	body *= 1.0 - rim_glass * 0.10;
	vec3 sheen = edge_tint * fresnel_v * fresnel_gain;

	ALBEDO = body + edge + sheen;
	ALPHA = clamp(
		body_alpha + rim_break * 0.14 + fresnel_v * 0.10 + seam_lit * 0.10,
		0.0, 1.0) * opacity * claim;
	}
}
