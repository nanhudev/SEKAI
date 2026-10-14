shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
//
// A MIRROR THAT DOES NOT MOVE.
//
// -----------------------------------------------------------------------------
// WHY THIS IS NOT A WATER SHADER
// -----------------------------------------------------------------------------
//
// 05 海啸但水不动 is a clip whose entire subject is that the water DOES NOTHING. The
// world tilts and pours into the sea, and the sea receives it without a single
// ripple, without a single crest, without moving at all. So this material has no
// time uniform, no noise, no normal map, and no animation of any kind — the
// absence of those is the content, and a shader that quietly added a sine wave
// would delete the prototype's claim from the inside.
//
// What it does have is a MIRROR. There is no screen-space reflection in
// `gl_compatibility` and there is no `Sky` resource in this lab, so a real
// reflection is not available — but the sky here is a two-axis gradient, and the
// reflection of a two-axis gradient is exact and cheap: the reflected ray's own
// elevation is the only thing that decides what colour you see. Looking straight
// down into the water, the reflected ray points straight up and the water takes the
// ZENITH colour; looking out across it, the reflected ray flattens and the water
// takes the HORIZON colour.
//
// -----------------------------------------------------------------------------
// WHY A PURE MIRROR IS NOT ENOUGH, AND WHAT WAS ADDED
// -----------------------------------------------------------------------------
//
// The first version was the mirror and nothing else, and the review sheet came back
// with a desert. That is not a bug in the mirror — it is what a mirror does: at the
// grazing angles a standing eye actually uses, the reflected ray is nearly
// horizontal, so the surface returns the HORIZON colour, and at sunset the horizon
// colour is a warm tan. A large, flat, untextured tan plane with a hard horizon is
// the single most land-like picture there is. The physics was right and the reading
// was wrong.
//
// Two things were added, and both of them are static, so neither weakens the claim:
//
//   · FRESNEL, WITH THE POLARITY THE FIRST VERSION HAD UPSIDE DOWN. Water reflects
//     almost nothing when you look straight into it and almost everything at a
//     grazing angle. The old code mixed the water's own BODY colour in at grazing
//     angles and left the steep view as pure sky, which is exactly backwards and is
//     why the plane had no depth anywhere. Now the near water is dark and blue and
//     the far water is the colour of the sky, which is a gradient only water has.
//
//   · THE SUN'S PATH. One high-power `pow(dot(reflected, sun), N)` lobe, added on
//     top. A bright broken streak running from the horizon toward the viewer is the
//     most unmistakable "this is liquid" signal there is, and because the sun does
//     not move during the clip the streak does not move either. When the world
//     tilts, the land slides through the streak while the streak stays exactly where
//     it was — which is a second, independent statement of the same claim.

uniform vec3 zenith_color : source_color = vec3(0.20, 0.30, 0.46);
uniform vec3 horizon_color : source_color = vec3(0.56, 0.58, 0.60);
uniform float horizon_sharpness : hint_range(0.1, 8.0) = 1.6;
uniform float energy : hint_range(0.0, 4.0) = 1.0;
// The water's own colour, seen where the reflection is weakest — i.e. straight down.
uniform vec3 body_color : source_color = vec3(0.026, 0.045, 0.070);
// How much of the body survives at the steepest view. 1 is a window into the deep.
uniform float body : hint_range(0.0, 1.0) = 0.72;
// Direction from the water TOWARDS the sun, world space, normalised.
uniform vec3 sun_dir = vec3(0.0, 0.3, -1.0);
uniform float glint : hint_range(0.0, 8.0) = 2.2;
uniform vec3 glint_color : source_color = vec3(1.0, 0.88, 0.70);

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec3 view = normalize(world_pos - CAMERA_POSITION_WORLD);
	// The reflected elevation, about the water's own up axis. Its Y is 0 at a
	// grazing view and 1 when the eye is straight above the fragment.
	vec3 refl = reflect(view, vec3(0.0, 1.0, 0.0));
	float h = clamp(refl.y, 0.0, 1.0);
	vec3 mirror = mix(horizon_color, zenith_color,
		clamp(pow(h, horizon_sharpness), 0.0, 1.0));

	// FRESNEL: 0 looking straight down, 1 at the horizon. `body` sets how dark the
	// water gets when you look into it, and the far water keeps the sky.
	float fresnel = pow(clamp(1.0 - h, 0.0, 1.0), 5.0);
	vec3 col = mix(body_color, mirror, mix(1.0 - body, 1.0, fresnel));

	// THE SUN'S PATH. `sun_dir` is the direction TO the sun, so this is the usual
	// half-vector-free mirror lobe: brightest where the reflected ray points at the
	// sun. A second, softer lobe widens it into a path rather than a dot.
	float s = max(dot(refl, normalize(sun_dir)), 0.0);
	col += glint_color * (pow(s, 260.0) * glint + pow(s, 22.0) * glint * 0.10);

	ALBEDO = col * energy;
	EMISSION = col * energy;
}
