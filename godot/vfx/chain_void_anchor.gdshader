shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, specular_disabled;

// ---------------------------------------------------------------------------
// SEKAI · 缚星链 ULTIMATE · THE VOID ANCHOR (虚空锚点)
// ---------------------------------------------------------------------------
//
// 一颗规则生成的空间节点 / 应力核 / 空间针孔核心.
//
// The brief rules out three things by name (§二.2): 不要做成科幻 UI 球, 不要做成
// 魔法火球, and — from the general VFX brief — no glowing orb with a halo. Those
// three are the same mistake wearing different colours: a bright round thing with
// a soft outline, which is an ICON and not a PLACE.
//
// SO WHAT IS IT. A place where space has been squeezed. Which means the read has
// to be built out of the things squeezing does and nothing else:
//
//   1 · IT BENDS WHAT IS BEHIND IT. `lens` samples the screen a few pixels off
//       the true pixel position, in the direction of the surface normal. This is
//       the only part of the anchor that is not decoration: it says "this is not
//       an object in front of the world, it is a place WHERE the world is
//       different", and it is why the anchor reads even when it is nearly black.
//
//   2 · IT HAS STRESS IN IT, AND THE STRESS HAS ORIENTATION. The rings are not a
//       pattern mapped onto a ball; they are thin bands whose width and
//       brightness rise where the surface is most compressed, and they are
//       trapped on the surface rather than floating in it. A sphere with texture
//       on it is a ball. A sphere whose texture is LOAD is a core.
//
//   3 · IT IS DARK. Almost entirely black, with one cold edge and one hot
//       hairline where the trident went in. Brightness is the cheapest way to
//       make something look like an effect, so it is the thing this shader
//       spends least of.
//
// NOT ANIMATED BY `TIME`. The rings drift on `clock`, which the director hands
// in from the ceremony timeline. A core that ran on wall time would not be
// re-renderable at an exact t, and this line has already paid for that lesson.

uniform float clock = 0.0;
// The world as it is behind the core. Reading it is the entire first point of
// the design note above: the anchor is legible because it MOVES what is behind
// it, so this is not an optional flourish.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// 0 at the moment of the bite, 1 when the core is fully formed. Before the bite
// there is nothing to draw, so the anchor is invisible rather than early.
uniform float form = 0.0;
// 0..1, one-shot: the flash as the trident goes through.
uniform float pierce = 0.0;
// How far the surface has been pulled inward, in metres.
uniform float implode = 0.085;
// Screen-space lens displacement at the rim, in uv. 0.012 at 6m is a few pixels
// of bend — enough to be felt, too little to be a fisheye.
uniform float lens = 0.012;

varying vec3 v_local;
varying float v_rim;

const float RING_COUNT = 5.0;

void vertex() {
	// The shell is drawn where it IS, not where it would be if nothing had
	// happened to it: the implosion is a real inward displacement of the surface,
	// which is what gives the core a silhouette that is not a sphere.
	v_local = normalize(VERTEX);
	float press = 0.55 + 0.45 * sin(v_local.y * 3.1 + clock * 0.9)
		* sin(v_local.x * 2.3 - clock * 0.7);
	float shell = implode * (0.35 + 0.65 * press);
	VERTEX -= v_local * shell * form;
	v_rim = clamp(1.0 - abs(dot(v_local, vec3(0.0, 0.0, 1.0))), 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	// Facing the viewer = 0, grazing = 1. The core's whole structure lives in
	// this coordinate, so the rings wrap the ball and thin out toward the middle
	// the way a squeezed shell would.
	float facing = 1.0 - abs(dot(normalize(v_local), vec3(0.0, 0.0, 1.0)));
	float graze = pow(1.0 - facing, 1.6);

	// ---- 1 · THE LENS -----------------------------------------------------
	vec2 bent = SCREEN_UV + n.xy * lens * form * (0.35 + 0.65 * graze);
	vec3 behind = texture(screen_tex, clamp(bent, vec2(0.002), vec2(0.998))).rgb;
	// The world behind is pulled toward the core and darkens as it goes: not a
	// tint on the anchor, a change to the world around it.
	float pull = pow(graze, 2.2) * form;
	vec3 col = behind * (0.34 + 0.66 * (1.0 - pull));

	// ---- 2 · THE STRESS ---------------------------------------------------
	// Bands that are trapped on the surface. `press` again, so the bright parts
	// of the shell are the same parts that were driven inward.
	float press = 0.55 + 0.45 * sin(v_local.y * 3.1 + clock * 0.9)
		* sin(v_local.x * 2.3 - clock * 0.7);
	float band = abs(fract(v_local.y * RING_COUNT * 0.5 + clock * 0.35) - 0.5) * 2.0;
	band = 1.0 - smoothstep(0.62, 1.0, band);
	float load = band * (0.30 + 0.70 * press) * form;
	// Cold structure, never white. This core is a rule, not a light source.
	col += vec3(0.16, 0.42, 0.66) * load * 0.55;

	// ---- 3 · THE TWO EDGES ------------------------------------------------
	// A cold catch of light where the shell turns away, and one hot hairline for
	// the instant the fork is through it. Those are the ONLY two bright things
	// this shader is allowed to draw.
	float cold = smoothstep(0.72, 1.0, graze * 0.85 + v_rim * 0.15) * form;
	col += vec3(0.42, 0.66, 0.86) * cold * 0.20;
	col += vec3(1.0, 0.94, 0.82) * pierce * 0.85;

	// It is a hole in the world, so it must be able to be black. Clamped only at
	// the very end, and the darkening above is what does the work.
	ALBEDO = clamp(col, vec3(0.0), vec3(1.4));
	ALPHA = clamp(form * (0.55 + 0.45 * graze) + pierce * 0.5, 0.0, 1.0);
}
