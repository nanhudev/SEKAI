shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
//
// THE GREYBOX MATERIAL THAT CAN LOSE THINGS.
//
// -----------------------------------------------------------------------------
// WHY ONE SHADER FOR EVERY PROP IN THE VFX LAB
// -----------------------------------------------------------------------------
//
// Eleven prototypes all need to do the same family of impossible thing to the
// same grey box: take a chunk out of it, flatten it, drain the colour out of it,
// or make it stand in a corridor the world has cleared. If each prototype owned
// its own material, then "does the world have a hole in it" would be answered
// eleven different ways and a fix in one would not reach the others.
//
// So there is ONE material type and the prototypes drive it through uniforms.
// `carve_radius = 0` means no hole; `flatten = 0` means the object keeps its
// volume; `whiten = 0` means it keeps its colour. Every default is the identity,
// which means a prototype that sets nothing gets a plain grey box and cannot
// accidentally inherit another prototype's state.
//
// -----------------------------------------------------------------------------
// THE THREE RULE-BREAKS, AND HOW EACH ONE ACTUALLY HAPPENS
// -----------------------------------------------------------------------------
//
// CARVE — 黑日 / 天钉. The world is missing a sphere. Not a black ball drawn in
// front of it: `discard` removes the fragments themselves, so what is behind the
// surface shows through the wound. `carve_keep_inside` inverts it, which is how
// the crater of 天钉 keeps only what is inside the depression.
//
// FLATTEN — 二相簿. The object loses its THIRD dimension. Its vertices are
// projected onto a plane and the mesh degenerates into a card lying in that
// plane. Done in `vertex()` so it is the geometry that changes and not a
// texture that pretends.
//
// WHITEN — 白界. The object loses its INFORMATION. Albedo goes to a flat
// near-white, roughness to 1, metallic to 0 — a surface with no colour and no
// material left to infer anything from. The black outline is a separate
// `next_pass` the prototype attaches; it is not in here because an outline is a
// property of the silhouette and this shader only knows about the surface.
//
// -----------------------------------------------------------------------------
// ONE TRAP, WRITTEN DOWN BECAUSE THE PROJECT HAS PAID FOR IT TWICE
// -----------------------------------------------------------------------------
//
// Nothing here touches NORMAL. The standing rule in this project is that a
// fragment shader never writes NORMAL, because in `gl_compatibility` it does not
// do what the code reads like it does and the result is a surface that is lit by
// nothing. Ground detail is carried by albedo and roughness and by geometry.
//
// And nothing here is metallic. A metallic surface with no reflection probe
// renders as a black silhouette; the whole lab is metallic 0 apart from the few
// props that explicitly ask for a little, and those are lit by the sky ambient.

// ---- SURFACE -------------------------------------------------------------
uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.5);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_amount : hint_range(0.0, 8.0) = 0.0;
// A flat lift for surfaces that have to read as information rather than matter.
uniform float paper : hint_range(0.0, 1.0) = 0.0;
// For the terrain only: how much of the mesh's own vertex colour multiplies the
// albedo. A single flat colour over 600 metres is a wash and gives the eye
// nothing to measure a tilt or a flattening against.
uniform float vertex_color_mix : hint_range(0.0, 1.0) = 0.0;

// ---- WARP: the scale of space is wrong ------------------------------------
// 03 黑日's Phase B, and the reason it exists is a refusal. The obvious way to
// say "space is being distorted near that black ball" is a refraction pass or a
// screen-space lens — and both of those are CAMERA effects. They say "something
// is wrong with your eye", which is a different and much cheaper claim than
// "something is wrong with the distance between two points".
//
// This remaps distance itself, in the world, for every surface at once. The
// falloff is squared and bounded by `warp_radius`, so the effect has an address:
// inside the radius space is measurably smaller, outside it nothing has changed
// at all, and the boundary between the two is something the eye can find.
//
// `warp_amount = 0` is the identity, so this costs the other ten prototypes a
// branch that never runs.
uniform vec3 warp_center = vec3(0.0);
uniform float warp_radius = 40.0;
uniform float warp_amount : hint_range(0.0, 1.0) = 0.0;

// ---- CARVE: the world loses a piece -------------------------------------
uniform vec3 carve_center = vec3(0.0);
uniform float carve_radius = 0.0;        // 0 = no hole
uniform float carve_keep_inside = 0.0;   // 1 = keep ONLY inside (a crater)
uniform float carve_soft = 0.0;          // >0 fades the rim instead of cutting
//
// A SPHERE IS A BITE; A CYLINDER IS A SHAFT. 09 神罚雷 opens a corridor from the sky
// to the ground and leaves it open, and a sphere placed anywhere cuts a bowl in the
// top of the world rather than a hole through it. `carve_column = 1` measures the
// distance in XZ only, which turns the same three numbers into a vertical cylinder
// of deletion with no top and no bottom.
uniform float carve_column = 0.0;
//
// ---- RIFT: the world is split along a LINE -----------------------------------
//
// `carve` is a sphere and a sphere makes a bite. 06 地脉拔刀 is not a bite: the blade
// is drawn and the ground opens along the line of the draw, which is a PLANE, and a
// plane has to be its own primitive because a sphere cannot be made to look like a
// straight cut however it is placed.
//
// The rift is defined by a point and a horizontal normal, and it removes everything
// within `rift_width` of that plane, at every height. That last part is what makes
// it a chasm rather than a trench: the road, the ground under it and the buildings
// standing beside it are all cut through at once, because the cut is a property of
// the world and not of any one surface.
uniform vec3 rift_origin = vec3(0.0);
uniform vec3 rift_normal = vec3(1.0, 0.0, 0.0);
uniform float rift_width = 0.0;          // 0 = no rift

// ---- FLATTEN: the world loses a dimension -------------------------------
uniform vec3 flatten_origin = vec3(0.0);
uniform vec3 flatten_normal = vec3(0.0, 0.0, 1.0);
uniform float flatten : hint_range(0.0, 1.0) = 0.0;
uniform float flatten_glow : hint_range(0.0, 1.0) = 0.0;
//
// HOW MUCH DEPTH IS LEFT WHEN THE FLATTEN IS COMPLETE.
//
// `0` is the literal claim: every vertex lands exactly on the plane, the mesh
// degenerates into a card, and the world is one sheet. That is the purest version
// of 降维 and it is what the first pass did — and it produced two problems that
// looked like renderer bugs and were not:
//
//   · COPLANARITY. A terrain sheet and a building that stands on it both land at
//     exactly the same z, so the terrain and the building z-fight; the village
//     came back as a field of flickering stripes.
//   · FAR MASSES. A 380 m hill 400 m out keeps its height when it is projected
//     onto a plane 60 m from the camera, so it becomes a 380 m wall 60 m away and
//     fills the whole frame. Depth is what made it small, and depth is the thing
//     being removed.
//
// A small non-zero squash fixes both without giving up the read: the world
// becomes a WAFER instead of a plane — depth is multiplied by `flatten_squash`
// rather than deleted, so a building becomes a card ~2 cm thick standing in front
// of the terrain sheet instead of inside it, and a distant hill is still distant.
// The still reads the same ("the world is a cut-out"), and it stops fighting
// itself. `flatten_squash = 0` keeps the exact-plane behaviour.
uniform float flatten_squash : hint_range(0.0, 1.0) = 0.0;
//
// LIGHT THE SHEET LIKE A SHEET.
//
// With the world's own normals kept, a squashed village is a village that has been
// squashed: every face still catches its own light and the eye reads perspective
// compression, not dimension loss. Replacing the normals with the PLANE's normal
// makes every card on the sheet receive the same light, which is what a printed
// sheet does. Opt-in, because it is a strong look and 01 二相簿 is the only
// prototype whose claim it serves.
uniform float flatten_flat_light : hint_range(0.0, 1.0) = 0.0;

// ---- WHITEN: the world loses its information ----------------------------
uniform float whiten : hint_range(0.0, 1.0) = 0.0;
uniform vec3 whiten_tint : source_color = vec3(0.94, 0.94, 0.96);
//
// AND IT CAN ARRIVE AS A WAVE RATHER THAN AS A FADE.
//
// A global `whiten` from 0 to 1 is a dissolve: every object in the world loses its
// colour at the same instant, which reads as a filter being turned up and not as
// something happening. 08 白界 is a fire that eats colour, so the colour has to go
// FIRST WHERE THE FIRE IS and spread outward. Any non-zero `whiten_spread` turns
// `whiten` into the FRONT of a wave travelling out from `whiten_origin`, with a soft
// rim of `whiten_soft` metres on either side of it. `whiten_spread = 0` keeps the
// original global behaviour, so nothing that was written against the old uniform
// changes meaning.
//
// AND THE TEST IS `abs(...)`, NOT `> 0`. The first version gated the wave on
// `whiten_spread > 0.0` while the comment above it already promised "<0 or >0",
// which meant a NEGATIVE spread silently fell through to the global branch and
// bleached the whole world — the exact failure 08 was trying to avoid, arriving one
// layer below the code that was trying to avoid it. A negative spread is not a
// second kind of wave; it is the same wave with its front still short of the origin,
// which is what "the fire has not started yet" looks like as a number.
uniform vec3 whiten_origin = vec3(0.0);
uniform float whiten_spread = 0.0;   // 0 = global; any other value = a wave front
uniform float whiten_soft = 26.0;

// NOTE: there is deliberately NO alpha in this shader. The moment a shader
// writes ALPHA, every prop in the lab becomes a transparent material and the
// whole greybox starts sorting itself against itself — which shows up as
// objects flickering in front of things they are behind, in one prototype only,
// depending on the camera. Anything that has to leave is scaled or hidden by the
// prototype, not dissolved here.

varying vec3 world_pos;
varying vec3 vcol;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR.rgb;
	vec3 mixed = world_pos;

	if (warp_amount > 0.001) {
		// ---- SCALE, GONE WRONG -------------------------------------------
		// This is the primitive 03 黑日 needs and it is deliberately NOT a lens
		// effect, a refraction pass, or a screen-space distortion. It is a
		// remapping of DISTANCE inside a radius: a point that was `r` metres
		// from `warp_center` becomes `r * (1 - warp_amount * falloff * k)`
		// metres from it, along the same direction. Nothing rotates, nothing
		// smears; the space between things is simply smaller than it was.
		//
		// That is what makes it read as a fact about the world rather than as
		// something happening to the camera, and it is why the buildings stretch:
		// each object's vertices are warped in WORLD space (the same way
		// `flatten` works), so the near face of a building is pulled further than
		// its far face and the building is compressed along the line to the
		// centre. The falloff is squared so the effect has a definite local
		// address and the horizon is provably untouched.
		//
		// `warp_amount = 0` is the identity, so no other prototype is affected.
		vec3 wd = world_pos - warp_center;
		float wr = length(wd);
		float wf = 1.0 - smoothstep(0.0, warp_radius, wr);
		vec3 wdir = wr > 0.001 ? wd / wr : vec3(0.0);
		float pulled = wr * (1.0 - warp_amount * wf * wf * 0.62);
		mixed = warp_center + wdir * pulled;
	}

	if (flatten > 0.001) {
		// THE PROJECTION IS DONE IN WORLD SPACE and then brought back, because
		// the plane the world is flattened onto is a fact about the world and
		// not about any one object's local frame. An object rotated by its own
		// transform still flattens onto the same sheet as its neighbours —
		// which is the whole read: one plane takes the whole world.
		//
		// `depth_left` is the fraction of the distance-to-plane that survives:
		// 0 at `flatten_squash = 0` (the vertex lands ON the plane), and
		// `flatten_squash` at `flatten = 1` otherwise.
		float d = dot(mixed - flatten_origin, flatten_normal);
		float depth_left = mix(1.0, flatten_squash, flatten);
		vec3 flat_world = mixed - flatten_normal * d * (1.0 - depth_left);
		mixed = mix(mixed, flat_world, flatten);

		if (flatten_flat_light > 0.5) {
			// A printed sheet has one normal. `NORMAL` here is in MODEL space, so
			// the world-space plane normal is brought back through the inverse of
			// the model matrix — the same transform `VERTEX` just went through in
			// the other direction.
			//
			// This is a VERTEX write and that is deliberate. The project's rule is
			// that a FRAGMENT shader never writes NORMAL; the vertex stage is
			// where a normal is supposed to be decided.
			vec3 n_model = normalize(
				(inverse(MODEL_MATRIX) * vec4(flatten_normal, 0.0)).xyz);
			NORMAL = normalize(mix(NORMAL, n_model, flatten));
		}
	}

	if (warp_amount > 0.001 || flatten > 0.001) {
		VERTEX = (inverse(MODEL_MATRIX) * vec4(mixed, 1.0)).xyz;
	}
}


void fragment() {
	// ---- CARVE -----------------------------------------------------------
	// `discard` and not a black sphere: the surface is genuinely not there, so
	// what is behind it is what the eye sees through the wound.
	if (carve_radius > 0.0) {
		float d = distance(world_pos, carve_center);
		if (carve_column > 0.5) {
			d = length(world_pos.xz - carve_center.xz);
		}
		float keep = 1.0;
		if (carve_keep_inside > 0.5) {
			keep = step(d, carve_radius);
		} else {
			keep = step(carve_radius, d);
		}
		if (carve_soft > 0.0) {
			// A rim that fades rather than cuts, for the torn edge of a wound
			// that should not be a perfect circle.
			if (carve_keep_inside > 0.5) {
				keep *= 1.0 - smoothstep(carve_radius, carve_radius + carve_soft, d);
			} else {
				keep *= smoothstep(carve_radius - carve_soft, carve_radius, d);
			}
		}
		if (keep < 0.5) {
			discard;
		}
	}

	// ---- RIFT ------------------------------------------------------------
	// A straight cut through everything, at every height. The edge is deliberately
	// razor-sharp: ground that has been SPLIT has two faces that fit together, and a
	// soft edge would read as erosion.
	if (rift_width > 0.0) {
		vec2 n2 = normalize(rift_normal.xz);
		vec2 d2 = world_pos.xz - rift_origin.xz;
		if (abs(dot(d2, n2)) < rift_width) {
			discard;
		}
	}

	// ---- SURFACE ---------------------------------------------------------
	// The wave, resolved per FRAGMENT rather than per object, so a building is
	// eaten from one end to the other as the front passes through it.
	float w = whiten;
	if (abs(whiten_spread) > 0.0001) {
		float d = distance(world_pos, whiten_origin);
		w = whiten * (1.0 - smoothstep(whiten_spread - whiten_soft,
			whiten_spread + whiten_soft, d));
		if (w <= 0.001) {
			// Untouched by the fire: skip the rest of the mix entirely.
			w = 0.0;
		}
	}
	vec3 albedo = mix(base_color, whiten_tint, w);
	albedo = mix(albedo, vec3(0.97, 0.97, 0.98), paper * 0.6);
	albedo *= mix(vec3(1.0), vcol, vertex_color_mix);
	ALBEDO = albedo;

	// A whitened surface has no material left: fully rough, fully dielectric.
	ROUGHNESS = mix(roughness, 1.0, w);
	METALLIC = metallic * (1.0 - w) * (1.0 - paper);

	EMISSION = emission_color * emission_amount;
	// A FLATTENED WORLD IS A PRINTED WORLD: it carries its own ink instead of being
	// lit by a scene it is no longer part of.
	//
	// This is not a stylistic lift, it is a repair. Projecting a horizontal terrain
	// onto a vertical plane turns it into a curtain, which makes its triangles
	// BACK-FACING from the viewer — and the compatibility renderer flips the normal
	// of a back-facing triangle before lighting it. `flatten_flat_light` therefore
	// points the ground's normal away from the camera and the ground comes back
	// ambient-lit and navy while the buildings standing on it are sunlit. Carrying
	// the albedo in EMISSION makes every card on the sheet read the same whichever
	// way its triangles happen to face, which is also what a printed sheet does.
	EMISSION += flatten * flatten_glow * albedo * 1.45;
	EMISSION += flatten_glow * vec3(0.42, 0.60, 0.92) * 0.22;
	// A WHITENED WORLD CARRIES ITS OWN LIGHT. At 0.05 the swap from a lit greybox to
	// an unlit one was a change of hue and nothing else — the village in 08 was pale
	// grey before the fire and pale white after it, and the two frames were nearly
	// the same picture. A world made of information should look faintly SELF-LIT, the
	// way a plaster model under studio light does, so the fire's payoff is a change
	// of MATERIAL and not of tint.
	EMISSION += w * whiten_tint * 0.13;
}
