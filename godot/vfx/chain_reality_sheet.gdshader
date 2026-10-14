shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, specular_disabled;

// ---------------------------------------------------------------------------
// SEKAI · 缚星链 ULTIMATE · THE REALITY SHEET (现实膜)
// ---------------------------------------------------------------------------
//
// 一张被强行从世界上拽下来的、二维化的现实表皮.
//
// This is the pass the whole skill rests on, and the brief is unusually precise
// about the three ways it is allowed to fail (§三 PHASE 4 and §四.3):
//
//   不要做成方形屏幕切片 / 不要做成一块硬玻璃板 / 不要让它是纯 shader 贴片.
//
// ---------------------------------------------------------------------------
// 1 · WHERE THE PICTURE COMES FROM, AND WHY THAT IS THE WHOLE TRICK
// ---------------------------------------------------------------------------
//
// The sheet is not textured with noise and it is not a transparent pane. Every
// pixel of it is THE WORLD ITSELF, sampled at the screen position that pixel had
// BEFORE the sheet was torn off.
//
// That position is baked into the mesh, in each vertex's `UV2`, at the instant of
// the rip, from the frozen capture camera's own projection. So the sample cannot
// follow the sheet as it moves.
//
// The consequence is the whole read, and it is worth stating plainly: as the
// sheet deforms and is dragged toward the player, the image on it stays LOCKED to
// the material, because the UV is a property of the vertex and not of the screen.
// The picture stretches exactly where the sheet stretches. That is what a
// torn-off film does, and it is the one thing that cannot be done with a
// rectangle, because a rectangle has no material to stretch.
//
// (The UV is baked rather than projected in here on purpose. A projection needs
// the camera's matrix, its Y convention and its aspect to survive a trip across
// the engine boundary; a baked UV needs nothing, and cannot be wrong in a way
// that is hard to see.)
//
// ---------------------------------------------------------------------------
// 2 · WHY IT IS A FUNCTION AND NOT A STACK OF TEXTURES
// ---------------------------------------------------------------------------
//
// `sheet_offset` is the entire deformation of the surface: warp, ripples, rim
// curl, the peel, and the five cuts. Three properties follow from writing it as a
// function rather than as a stack of samples:
//
//   · the NORMALS ARE REAL. They are the cross product of two finite differences
//     of the same function, so the sheet shades as the sculpted thing it is
//     instead of as a flat card with a lighting trick on it.
//   · THE RIM TOUCHES ITSELF. The curl is part of the same displacement as the
//     body, so the edge bends back toward the viewer continuously — there is no
//     seam where "the shape" stops and "the effect" starts.
//   · THE CUTS OPEN THE GEOMETRY, not a texture. A gap in this shader moves the
//     surface apart; a gap drawn with an alpha mask over a flat card is a decal,
//     and §四.2 lists 纯 shader 平面贴片 as a thing not to make.
//
// ---------------------------------------------------------------------------
// 3 · THE MANGA LANGUAGE, AND THE LIMIT ON IT
// ---------------------------------------------------------------------------
//
// §三 PHASE 7 asks for 漫画式撕裂: 边缘发白 / 墨线 / 分帧, and then immediately
// warns 不要直接做成搞笑漫画 UI. The line is that the language must be IN THE
// MATERIAL and not OVER THE PICTURE.
//
// So there is no screen-space overlay anywhere in this file. The white is the
// sheet's own split edge going to paper; the ink is a hard dark band on the far
// side of that edge; and both only exist within a few centimetres of a cut. An
// intact part of the sheet is never inked. A comic panel is a frame around
// content; this has no frame, and no content that is not the world.
//
// ---------------------------------------------------------------------------
// 4 · NO WALL CLOCK
// ---------------------------------------------------------------------------
//
// Every animation here reads `clock` (the ceremony time, handed in by the
// director) and never `TIME`. Wall time would make a ripple depend on when the
// frame happened to be rendered, and this line has already lost a pass to a
// director that could not be scrubbed.
//
// ---------------------------------------------------------------------------
// 5 · THE COLOUR SPACE, WHICH COST THIS EFFECT ITS FIRST HONEST MEASUREMENT
// ---------------------------------------------------------------------------
//
// `source_color` is NOT decoration on `capture_tex`. The viewport this samples has
// already been tonemapped and sRGB-ENCODED — it is display-referred data, the
// picture as a viewer would see it. Without the hint, Godot hands those numbers
// to the shader raw and this file then treats them as SCENE-LINEAR, which means
// the tonemapper runs over them a SECOND time on the way out.
//
// That is not a small error at the dark end, and it is invisible in the code: the
// transfer measured off two real renders was
//
//     world sRGB 0.134  ->  film 0.811   x 6.04
//     world sRGB 0.728  ->  film 0.729   x 1.00
//
// — the film brightening everything dark by six times while copying bright pixels
// perfectly, because tonemapping is near-identity at the top and a large gain at
// the bottom. The read on screen was a washed-out grey film floating over a room
// it was supposed to BE. Fixing it is one word.
uniform sampler2D capture_tex : source_color, filter_linear, repeat_disable;

uniform float clock = 0.0;
// THE RADIUS OF THE FILM AS IT IS RIGHT NOW, contraction included — not the
// radius the mesh was built at. Every metric term below (`ripple`, `curl`, the
// lean, the normal's finite difference) is scaled by it, so the whole surface
// deforms at its own scale instead of at a scale it stopped having at 1.40s.
uniform float sheet_radius = 2.2;
// HOW FAR THE PICTURE HAS BEEN PULLED IN, 1.0 to `sheet_contract_end`. Applied
// to the vertex position, which is what makes the film shrink on screen and open
// the frame at the edges for the void to come through. See the tuning's note:
// this is the ONLY reason anything behind the film is ever visible, because a
// film hauled toward the player only ever gets bigger.
uniform float contract = 1.0;

// ---- the surface --------------------------------------------------------
uniform float warp = 0.075;
uniform float ripple = 0.022;
uniform float ripple_hz = 3.1;
uniform float curl = 0.30;

// ---- the peel -----------------------------------------------------------
// 0 = still part of the world, 1 = fully free. The front travels up the sheet.
uniform float peel = 0.0;
uniform float pull_amount = 1.35;
uniform float lift_amount = 0.22;

// ---- the cuts -----------------------------------------------------------
// Segment endpoints in METRES in the sheet's own plane, the half-width of the
// gap each has opened, and how recently the tip passed (which is what the white
// edge at the cut's lip is driven by).
const int CUT_MAX = 6;
uniform vec4 cut_seg[CUT_MAX];
uniform float cut_open[CUT_MAX];
uniform float cut_glow[CUT_MAX];

// ---- the end ------------------------------------------------------------
uniform float tear = 0.0;
uniform float flash = 0.0;
uniform float dissolve = 0.0;
uniform float edge_inner = 0.80;
uniform float ink_width = 0.018;
uniform float white_width = 0.055;

varying vec2 v_uv;
// The mesh's own coordinate system, baked per vertex. See
// `ChainRealitySheet._vert` — all three are normalised by the OUTLINE and not by
// the nominal radius, which is the difference between a rim fade that fires
// where the edge is and one that fires 30% early on half the perimeter.
varying float v_r;     // 0 centre, 1.0 on the outline, wherever that is
varying float v_seam;  // 0 on this shard's own mesh boundary, 1 at 6cm inside
varying float v_peel;  // 0 at the outline's bottom edge, 1 at its top
varying vec2 v_q;
varying vec3 v_n;

// Where the point falls relative to the segment a-b: the perpendicular distance,
// and which side of the segment, so the two sides can be pushed apart in
// opposite directions.
vec2 seg_side(vec2 p, vec2 a, vec2 b, out float dist) {
	vec2 ab = b - a;
	float len2 = max(dot(ab, ab), 1e-6);
	float h = clamp(dot(p - a, ab) / len2, 0.0, 1.0);
	dist = length(p - (a + ab * h));
	vec2 n2 = normalize(vec2(-ab.y, ab.x));
	return n2 * sign(dot(p - a, n2));
}

// ---------------------------------------------------------------------------
// THE ENTIRE SURFACE, AS ONE FUNCTION.
//
// Returns the displacement of the point `q` (metres, in the sheet's plane, with
// `r` its normalised distance from the centre) from the flat ideal it was born
// as. The vertex shader uses it once for position and twice more for the normal.
// ---------------------------------------------------------------------------
vec3 sheet_offset(vec2 q, float r) {
	float ang = atan(q.y, q.x);
	vec3 d = vec3(0.0);

	// OUT OF PLANE. A membrane is not a plane. The low-frequency term gives it a
	// gentle bowl and the two travelling ripples give it a surface with traffic
	// on it — the same differential motion the iaido void uses to get depth out
	// of something that has no thickness.
	d.z += warp * (0.35 + 0.65 * cos(ang * 1.7 + 1.1)) * (1.0 - r * 0.45);
	d.z += ripple * sin(ang * 3.0 + clock * ripple_hz) * r * sheet_radius;
	d.z += ripple * 0.55 * sin(ang * 5.0 - clock * ripple_hz * 1.37 + 2.2)
		* r * r * sheet_radius;

	// THE RIM CURL. The edge of a pulled-off film turns back toward whoever
	// pulled it. This is the only place the sheet gets anything like thickness,
	// and it is what stops the silhouette reading as a cut-out.
	d.z += curl * smoothstep(0.56, 1.0, r) * sheet_radius * 0.22;

	// THE CUTS. Each opens a gap by moving the two sides APART — along the
	// segment's own perpendicular, and out of plane, so a slit opens like a
	// wound rather than like a zip. Only the immediate neighbourhood moves.
	for (int i = 0; i < CUT_MAX; i++) {
		float open = cut_open[i];
		if (open <= 0.0001) {
			continue;
		}
		float dist;
		vec2 side = seg_side(q, cut_seg[i].xy, cut_seg[i].zw, dist);
		float near = 1.0 - smoothstep(open * 1.2, open * 3.4, dist);
		if (near <= 0.0) {
			continue;
		}
		float lip = near * open;
		d.xy += side * lip * 0.55;
		d.z += side.y * lip * 0.85;
	}

	return d;
}

void vertex() {
	float r = COLOR.r;
	// THE CONTRACTION IS HERE AND NOWHERE ELSE. Everything downstream — the
	// offsets, the normals, the cut distances — is computed in this contracted
	// space, so a single multiply moves the whole surface, its deformation and
	// its cuts together and nothing can be left behind at the old size.
	vec2 q = VERTEX.xy * contract;
	v_r = r;
	v_seam = COLOR.g;
	// THE PEEL COORDINATE IS BAKED, NOT DERIVED FROM `q.y`. See
	// `ChainRealitySheet._vert`: `COLOR.b` is the point's projection on the
	// OUTLINE's own vertical axis, normalised by the outline's height at that
	// angle, so it reaches exactly 1.0 on the top edge of a short lobe as well
	// as a long one. `q.y / sheet_radius` does not: it reaches only 0.84 on a
	// short lobe, which leaves the last centimetres of the peel permanently
	// stuck to the world on that side of the sheet.
	v_peel = COLOR.b;
	v_q = q;
	v_uv = UV2;

	// ---- THE PEEL ---------------------------------------------------------
	// The sheet lets go from its LOWER edge and the separation runs upward. A
	// point at peel coordinate `p` is freed once the front has passed it, and
	// only a freed point is carried toward the player — which is why the sheet
	// STRETCHES before it comes away, and why this is a peel rather than a fade.
	float p = clamp(v_peel, 0.0, 1.0);
	float peeled = 1.0 - smoothstep(peel - 0.34, peel + 0.02, p);
	// The freed part also leans back a little as it goes, so the sheet rotates
	// out of the world's plane instead of sliding along it.
	float lean = peeled * peeled * 0.10;

	vec3 offset = sheet_offset(q, r);
	offset += vec3(0.0, lift_amount, pull_amount) * peeled;
	offset.y -= lean * sheet_radius;

	vec3 pos = vec3(q, 0.0) + offset;
	VERTEX = pos;

	// ---- REAL NORMALS, FROM THE FUNCTION ITSELF ---------------------------
	// The differences are taken from the DEFORMED surface and not from the flat
	// plane, and the centre is subtracted so what is crossed is a tangent pair.
	float e = sheet_radius * 0.02;
	vec3 qa = vec3(q + vec2(e, 0.0), 0.0) + sheet_offset(q + vec2(e, 0.0), r);
	vec3 qb = vec3(q + vec2(0.0, e), 0.0) + sheet_offset(q + vec2(0.0, e), r);
	vec3 n = normalize(cross(qa - pos, qb - pos));
	v_n = n;
	NORMAL = n;
}

void fragment() {
	// ---- THE WORLD, ON THE MATERIAL ---------------------------------------
	vec3 col = texture(capture_tex, clamp(v_uv, vec2(0.0015), vec2(0.9985))).rgb;

	// Thinned and slightly cooled toward the rim, so the edge reads as material
	// running out rather than as a shape being masked out. Small, and smaller
	// than it was: this file's albedo is scene-linear now (see §5), so a wash that
	// looked like a tint when the numbers were being double-tonemapped is a lit
	// band now.
	float thin = smoothstep(0.86, 1.02, v_r);
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(luma), thin * 0.20);
	col *= 1.0 - thin * 0.12;

	// ---- IT IS A SURFACE, AND THE ONLY PLACE THAT IS ALLOWED TO SHOW ------
	//
	// Unshaded, so there is no light here to do it for us — and a film that is a
	// flat photograph laid over the world is exactly the 纯 shader 平面贴片 the
	// brief forbids. The ONE place the sheet leaves the plane is its rim: the
	// curl bends the last part of the radius back toward the viewer, so the normal
	// there tips away from the camera.
	//
	// SO THE SHADING IS ZERO WHERE THE FILM IS FLAT, AND THAT IS THE POINT. This
	// term used to be `col *= 0.83 + 0.30 * facing` plus an additive cold colour,
	// which lifted the whole body by 13% and washed the rim out to daylight
	// whether the rim had turned or not. A flat region of a peeled photograph IS
	// the world, and any constant gain over it is the film announcing itself in
	// the one moment it must be invisible. The measurement that caught the second
	// half of it: a cold daylight laid over the whole outer HALF of the radius
	// came back on screen as a soft grey halo around the entire piece — bloom, not
	// edge — because any term that spans 40% of a 3m object is a field, not a line.
	//
	// So: the body loses light where the curl has turned it, and the only bright
	// thing on the silhouette is a band four percent wide.
	float facing = clamp(v_n.z, 0.0, 1.0);
	float turned = pow(1.0 - facing, 1.7);
	col *= 1.0 - turned * smoothstep(0.55, 1.0, v_r) * 0.45;

	// THE FILM'S OWN THICKNESS, CATCHING THE SKY. One hairline at the very edge,
	// and it is the same line whatever the film is doing — the peel, the haul and
	// the hold all have the same edge. Faded out by `tear` because after the tear
	// the edge of a piece is the white paper lip of a cut, and two edges on one
	// silhouette is one too many.
	float rim = smoothstep(0.945, 0.985, v_r) * (1.0 - smoothstep(0.985, 1.02, v_r));
	col = mix(col, vec3(0.40, 0.50, 0.64), rim * (1.0 - tear) * 0.80);

	float alpha = 1.0 - smoothstep(edge_inner, 1.0, v_r);

	// ---- THE CUTS, AND THE MANGA EDGE -------------------------------------
	float hot = 0.0;
	float ink = 0.0;
	for (int i = 0; i < CUT_MAX; i++) {
		float open = cut_open[i];
		if (open <= 0.0001) {
			continue;
		}
		float dist;
		seg_side(v_q, cut_seg[i].xy, cut_seg[i].zw, dist);
		// THE GAP, AND IT HAS TO BE THE WIDEST OF THE THREE BANDS. Nothing is
		// drawn in it, so what shows through is the world BEHIND the film — the
		// cut has to be a hole through the material. The white lip and the ink
		// line used to be several times wider than the gap, which turned every
		// stroke into a stripe drawn on the film and hid the one detail that says
		// it was cut at all.
		alpha *= smoothstep(open * 0.40, open * 1.05, dist);
		// THE LIP. A white edge on the cut, fading as the tip's heat does.
		float lip = (1.0 - smoothstep(0.0, max(white_width * 1.6, open), dist))
			* (0.35 + 0.65 * cut_glow[i]);
		hot = max(hot, lip);
		// THE INK. Just outside the white, a hard dark band — the drawn line that
		// says this is a tear in a printed surface. Thin: at `ink_width` 0.018
		// this is 4cm wide, which is 7px at 720p from the film's own distance.
		// Wider and it stops being a pen line and starts being a stripe.
		float band = (1.0 - smoothstep(ink_width * 1.2, ink_width * 3.4, dist))
			* smoothstep(open * 0.40, open * 1.10, dist);
		ink = max(ink, band * (0.4 + 0.6 * cut_glow[i]));
	}

	// ---- THE TEAR ---------------------------------------------------------
	// As the pieces come apart the split edges go to paper and the material
	// around them loses its light. The white is confined to `hot`, a few
	// centimetres wide, so an intact part of the sheet is never inked.
	col = mix(col, vec3(0.93, 0.91, 0.86), hot * tear * 0.85);
	col *= 1.0 - ink * 0.82;
	col *= 1.0 - tear * (1.0 - hot) * 0.35;

	// THE SEAM. Each piece's OWN mesh boundary — the split the shard was cut
	// along rather than any of the five strokes. Same language as the cuts and
	// from the same numbers: a white lip on the boundary itself (1.2cm) and a
	// thin ink line a few millimetres inside it. Multiplied by `tear` because
	// while the film is whole the six pieces are coincident and a visible seam
	// would draw the pie chart this outline exists to avoid.
	float seam_white = 1.0 - smoothstep(0.0, 0.16, v_seam);
	float seam_ink = smoothstep(0.12, 0.32, v_seam) * (1.0 - smoothstep(0.50, 0.95, v_seam));
	col = mix(col, vec3(0.95, 0.93, 0.88), seam_white * tear * 0.90);
	col *= 1.0 - seam_ink * tear * 0.72;

	// ---- THE FRONT ITSELF. The line where the material is still deciding whether it
	// is part of the world or not: everything below it has let go, everything
	// above it has not. It is the ONE thing that says the separation is running
	// UPWARD rather than the film simply sliding away, and it is drawn from the
	// BAKED peel coordinate so it stays square to the outline's own vertical axis
	// instead of to the screen. Faded at the rim so it dies into the silhouette
	// rather than stopping in mid-air.
	float front = 1.0 - smoothstep(0.0, 0.055, abs(v_peel - peel));
	float front_live = smoothstep(-0.04, 0.06, peel) * (1.0 - smoothstep(0.94, 1.04, peel));
	float front_edge = 1.0 - smoothstep(0.72, 1.0, v_r);
	col += vec3(0.72, 0.84, 1.00) * front * front_live * front_edge * (1.0 - tear) * 0.12;

	// ---- THE END ----------------------------------------------------------
	col += vec3(1.0, 0.97, 0.92) * flash;
	// Dissolve eats the sheet from the inside out, per point, so it goes as
	// material rather than as a uniform fade to zero.
	//
	// AND IT HAS TO REACH ZERO, WHICH THE FIRST VERSION DID NOT. The mask was
	// `1.0 - dissolve * clamp(0.30 + 0.70 * grain)`, and the 0.30 FLOOR meant that
	// at a full dissolve the quietest third of the pixels kept 70% of their alpha —
	// so PHASE 8 ended on the world with the film's pieces still hanging over it,
	// faintly, forever. 断片消失 did not happen. Raising the grain coefficient past
	// 1.0 instead puts every point's threshold below the dissolve's own travel, so
	// the end state is empty for every point and the grain still decides WHICH
	// points go first — which is the whole reason for having it.
	float grain = fract(sin(dot(v_q, vec2(37.1, 91.7))) * 43758.5453);
	alpha *= clamp(1.0 - dissolve * (1.0 + 0.60 * grain), 0.0, 1.0);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
