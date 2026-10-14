shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
//
// THE SKY, AS ONE MATERIAL THE LAB CAN MOVE AND FOLD.
//
// -----------------------------------------------------------------------------
// WHY THIS IS NOT `ProceduralSkyMaterial`
// -----------------------------------------------------------------------------
//
// Eleven prototypes need the sky to do eleven different things, and three of them
// need it to be a THING rather than a background:
//
//   07 星坠 / 10 锁链拖星  need stars and a moon whose position the effect moves.
//   11 天地合页            needs the sky to be a PAGE that folds down onto the
//                          ground, which means it has to be geometry.
//   08 白界                needs the sky to lose its colour like everything else.
//
// A `Sky` resource is a background — it cannot be tilted, folded, or asked how
// bright it currently is. So the dome is an actual inverted sphere with this
// material on it, and the effect drives it like any other prop.
//
// It is `cull_front` because we are inside it, and `fog_disabled` because fog is
// a property of the air between the eye and the ground, and applying it to the
// sky would fog the sky itself.
//
// -----------------------------------------------------------------------------
// EVERY FEATURE DEFAULTS TO OFF
// -----------------------------------------------------------------------------
//
// `star_amount = 0`, `sun_amount = 0`, `moon_amount = 0`. A lab that wants a
// plain gradient sky sets nothing; a lab that wants a night sky turns on stars
// and a moon. There is no preset baked in, so a prototype can never inherit a
// sky it did not ask for.

uniform vec3 zenith_color : source_color = vec3(0.20, 0.30, 0.46);
uniform vec3 horizon_color : source_color = vec3(0.56, 0.58, 0.60);
uniform vec3 ground_color : source_color = vec3(0.16, 0.16, 0.18);
uniform float horizon_sharpness : hint_range(0.1, 8.0) = 1.6;
uniform float energy : hint_range(0.0, 4.0) = 1.0;

// ---- STARS ---------------------------------------------------------------
uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
uniform float star_density : hint_range(2.0, 90.0) = 42.0;
uniform vec3 star_color : source_color = vec3(0.85, 0.88, 1.0);

// ---- A BODY (sun by day, moon by night) ----------------------------------
// Given as a DIRECTION, so an effect can move it across the sky by moving a
// vector rather than by rotating the dome the stars are pinned to.
uniform vec3 body_direction = vec3(0.2, 0.7, -0.5);
uniform float body_amount : hint_range(0.0, 4.0) = 0.0;
uniform vec3 body_color : source_color = vec3(1.0, 0.96, 0.86);
uniform float body_radius : hint_range(0.001, 0.5) = 0.06;
uniform float body_glow : hint_range(0.0, 4.0) = 0.0;
// A moon is a DISC with a visible face; a sun is a blown-out core. Same knob.
uniform float body_face : hint_range(0.0, 1.0) = 0.0;

// ---- WHITEN: 白界 drains the sky too --------------------------------------
uniform float whiten : hint_range(0.0, 1.0) = 0.0;
uniform vec3 whiten_tint : source_color = vec3(0.95, 0.95, 0.97);

// ---- VOID: 黑日 deletes a solid angle of the sky --------------------------
//
// The sky is not painted over with black — the fragments are `discard`ed, so what
// shows through is the viewport's own background. That is the difference between
// "a black disc drawn on the sky" (a decoration) and "a region of space that is
// not there" (the claim). 03 黑日 sets the environment's background to black in
// its own `build()` so that what shows through is nothing at all.
//
// `void_cos` is the cosine of the hole's HALF-ANGLE; -1 means no hole, and the
// default is off so no prototype inherits another's sky.
//
// `void_rim` draws a thin BRIGHT line around the edge of the hole, and it exists
// because of a problem 10 锁链拖星 hit and 03 黑日 never could: a hole in a NIGHT
// sky is invisible. The night dome is nearly black, the hole is exactly black, and
// the only difference between them is the handful of stars the hole removes — so a
// disc that is 3 % of the sky, which would be a loud shape against a day sky, reads
// as nothing at all. A rim turns the absence back into a SHAPE: the sky is a sheet,
// and a sheet that has been torn has an edge. Off by default, and off for 03, whose
// claim is explicitly a hole with no rim light on it.
uniform vec3 void_direction = vec3(0.0, 1.0, 0.0);
uniform float void_cos = -1.0;
uniform float void_rim : hint_range(0.0, 4.0) = 0.0;
uniform vec3 void_rim_color : source_color = vec3(1.0, 0.94, 0.86);
// The lip's thickness, in RADIANS — not in cosine. A fixed cosine width is a
// different physical width on every hole (the same 0.0035 is 3.6° on a 6° hole and
// 0.2° on a 60° one), which is exactly the kind of unit mismatch that makes a shader
// look fine in one prototype and wrong in the next.
uniform float void_rim_angle : hint_range(0.0, 0.4) = 0.013;

// ---- SPIN: the sky is a THING and it can be dragged ------------------------
//
// 10 锁链拖星 hooks a star and pulls it, and the star is pinned to the sky: drag
// the star and the whole celestial sphere comes with it. `sky_spin` yaws every
// star and the body around the zenith, so the star field visibly swings across the
// frame while the world stays where it is.
//
// A YAW AND NOT A FULL ROTATION, deliberately. The zenith/horizon gradient is a
// function of elevation, and rotating it about anything else would tip the horizon
// — which would say "the world tilted" instead of "the sky slid". Only the star
// field and the body are attached to the spinning frame.
uniform float sky_spin = 0.0;

varying vec3 dir_v;


float hash13(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}


void vertex() {
	dir_v = normalize(VERTEX);
	// NOTHING HERE WRITES `POSITION`. `POSITION` in a vertex shader is the CLIP
	// space position — writing `vec4(VERTEX, 1.0)` into it does not "keep the
	// vertex where it is", it places every vertex at its raw local coordinate in
	// clip space, which for a 1600m dome is outside the frustum in every
	// direction. The whole sky renders as nothing and the background colour shows
	// through, which looks exactly like a background-colour problem and is not.
}


void fragment() {
	vec3 dir = normalize(dir_v);
	// The spinning frame. Only the stars and the body are read in it; the gradient
	// below is always read in the world frame.
	vec3 spin_dir = dir;
	if (sky_spin != 0.0) {
		float c = cos(sky_spin);
		float s = sin(sky_spin);
		spin_dir = vec3(dir.x * c - dir.z * s, dir.y, dir.x * s + dir.z * c);
	}

	// ---- THE HOLE --------------------------------------------------------
	// Before anything is lit, because a region of space that is not there cannot
	// have a colour: everything below this line is skipped, not darkened.
	float rim = 0.0;
	if (void_cos > -0.999) {
		float cd = dot(dir, normalize(void_direction));
		if (cd > void_cos) {
			discard;
		}
		// The torn edge. `cd` is just below `void_cos` at the lip of the hole and
		// falls as the fragment gets further from it, so this is brightest exactly
		// where the sky stops. The outer limit is the same half-angle plus
		// `void_rim_angle`, so a lip is always the same width ON THE SKY.
		if (void_rim > 0.0) {
			float lip = cos(acos(clamp(void_cos, -1.0, 1.0)) + void_rim_angle);
			rim = (1.0 - clamp((void_cos - cd) / max(void_cos - lip, 1e-6), 0.0, 1.0))
				* void_rim;
		}
	}

	float h = dir.y;
	vec3 sky = mix(horizon_color, zenith_color,
		clamp(pow(max(h, 0.0), horizon_sharpness), 0.0, 1.0));
	sky = mix(ground_color, sky,
		smoothstep(-0.06, 0.06, h));
	vec3 col = sky * energy;

	// ---- STARS -----------------------------------------------------------
	if (star_amount > 0.0) {
		// Only above the horizon, and only where the cell hash says there is a
		// star. The dome is large enough that a cell is a few pixels, which is
		// what a star should be.
		vec3 cell = floor(spin_dir * star_density);
		float h1 = hash13(cell);
		if (h1 > 1.0 - star_amount * 0.30) {
			vec3 jitter = vec3(hash13(cell + 1.7), hash13(cell + 4.3), hash13(cell + 9.1));
			vec3 centre = normalize((cell + 0.5 + (jitter - 0.5) * 0.8) / star_density);
			float d = distance(normalize(spin_dir), centre);
			float bright = smoothstep(0.0022, 0.0, d) * (0.5 + h1 * 0.9);
			col += star_color * bright * smoothstep(-0.02, 0.16, h) * 3.2;
		}
	}

	// ---- A BODY ----------------------------------------------------------
	// The body is read in the WORLD frame even while the stars spin, and that is
	// deliberate: the body IS the star that is being dragged, so it is the one point
	// in the sky that has stopped belonging to the celestial sphere. 10 锁链拖星
	// aims it directly from its own code, and everything around it slides.
	if (body_amount > 0.0) {
		float ang = distance(dir, normalize(body_direction));
		float disc = smoothstep(body_radius, body_radius * 0.94, ang);
		float glow = exp(-ang * ang / max(body_radius * body_radius * 9.0, 0.00001));
		// A face: a moon should look like a body, not a hole punched in the sky.
		float face = 1.0;
		if (body_face > 0.5) {
			vec3 tangential = normalize(cross(normalize(body_direction), vec3(0.0, 1.0, 0.0)));
			vec3 bitan = cross(normalize(body_direction), tangential);
			vec2 uv = vec2(dot(dir, tangential), dot(dir, bitan)) / max(body_radius, 0.0001);
			face = 0.80 + 0.20 * hash13(floor(vec3(uv * 3.0, 0.0)));
			face *= smoothstep(1.02, 0.86, length(uv));
		}
		col = mix(col, body_color * face, disc);
		col += body_color * glow * body_glow;
	}

	col = mix(col, whiten_tint, whiten);
	col += void_rim_color * rim;
	ALBEDO = col;
	EMISSION = col;
}
