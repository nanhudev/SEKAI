shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// =============================================================================
// 聚合斩 · THE CROSS-SECTION
// =============================================================================
//
// ONE ENEMY, CUT BY ONE PLANE, WITHOUT A RUNTIME MESH BOOLEAN.
//
// The two halves you see are the SAME mesh drawn twice, each with the other side
// of the plane thrown away in the fragment shader. That is the whole trick, and
// it is the right trick: a boolean per enemy per swing is a per-frame cost that
// scales with the number of things on screen, and this costs one dot product per
// vertex. A production enemy that ships authored split meshes never even runs
// this — see `IaidoExecutionProfile.split_variants` — but every enemy in the game
// is answerable to the signature on the day it is born, not the day ART finishes
// with it.
//
// THE PLANE IS IN THE PIECE'S OWN SPACE, NOT THE WORLD'S.
//
// This is not a style choice. A plane pinned in world space keeps cutting a
// piece that has already fallen away from it: as a half separates, more and more
// of it crosses the fixed plane and gets discarded, so the half visibly eats
// itself while it falls. Measured in the piece's material space the cut surface
// travels WITH the piece, which is what a cut surface does, and it costs nothing
// — the plane is transformed once, on the CPU, when the half is built.

// Object-space plane: xyz normal, w offset. See IaidoCutPlane.local_to().
uniform vec4 cut_plane = vec4(0.0, 1.0, 0.0, 0.0);
// +1 keeps the side where dot(p, n) - w > 0, -1 keeps the other one.
uniform float cut_keep = 1.0;

// The surface the enemy was already wearing. Copied off its own material so the
// swap from "one body" to "two halves" is invisible — a cut that also changed
// the colour of the thing it cut would read as a different object.
uniform vec3 albedo : source_color = vec3(0.80, 0.80, 0.80);
uniform float roughness : hint_range(0.0, 1.0) = 0.80;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// The cross-section, from IaidoExecutionLibrary.SURFACES. Per material family,
// and never red: this game's answer to "what is inside a construct" is stone,
// aged metal and a light that was still running.
uniform vec3 interior_color : source_color = vec3(0.14, 0.13, 0.13);
uniform vec3 rim_color : source_color = vec3(0.85, 0.81, 0.72);
uniform float rim : hint_range(0.0, 1.0) = 0.42;
uniform float core_emission : hint_range(0.0, 4.0) = 0.0;
uniform vec3 core_color : source_color = vec3(0.32, 0.80, 0.94);
// Width of the changed band at the lip of the cut, in object space.
uniform float band = 0.04;
// Half the body's size along the cut normal. Only used by the dissolve ramp.
uniform float body_extent = 0.60;

// 0 before the trace beat, 1 once the hairline is legible. At 0 the two halves
// are pixel-identical to the body they replaced — which is the point: the body
// is cut before anything looks cut.
uniform float trace : hint_range(0.0, 1.0) = 0.0;
// One bright beat at the release, then gone.
uniform float edge_glow : hint_range(0.0, 1.0) = 0.0;
// 0..1, the piece coming apart from the cut outward. Dithered rather than faded,
// so this material can stay in the opaque pass and never has to be sorted.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_obj;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	// Object space, so the cut is measured in the piece's own material space.
	// A varying of a linear function of the vertex is reproduced exactly by the
	// interpolator, so this is a per-vertex dot product instead of a per-pixel
	// one with no loss of accuracy.
	v_obj = VERTEX;
}

void fragment() {
	float sd = dot(v_obj, cut_plane.xyz) - cut_plane.w;
	if (cut_keep * sd < 0.0) {
		discard;
	}

	// ---- THE DISSOLVE ----------------------------------------------------
	//
	// Consumed from the cut outward: the rule of the whole skill is that the
	// wound is the cause of everything, so a body coming apart comes apart
	// starting at the wound. The dither keeps the material in the opaque pass.
	if (dissolve > 0.0001) {
		float reach = clamp(1.0 - abs(sd) / max(body_extent, 0.0001), 0.0, 1.0);
		float front = dissolve * 1.15;
		if (reach < front) {
			float n = hash13(floor(v_obj * 110.0));
			float local = (front - reach) / max(front, 0.0001);
			if (n < local) {
				discard;
			}
		}
	}

	float reveal = clamp(trace, 0.0, 1.0);
	float w = max(band, 0.0005);
	float lip = pow(1.0 - smoothstep(0.0, w, abs(sd)), 0.7);

	// ---- THE SURFACE -----------------------------------------------------
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = vec3(0.0);

	// The inside of the body, seen only once the two halves have moved apart —
	// which is why the interior can afford to be dark: something else is
	// revealing it.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		ALBEDO = interior_color;
		ROUGHNESS = 0.90;
		METALLIC = 0.0;
		// Whatever was running inside it is still, very briefly, running.
		EMISSION = core_color * core_emission * 0.30;
	}

	// ---- THE LIP ---------------------------------------------------------
	//
	// The band of material that changed state. This is the ONLY line the cut is
	// allowed to draw, it is scaled by `reveal` so nothing is drawn before the
	// trace beat, and it is deliberately starved: §B of the brief says no more
	// glow on the primary cut, so the permanent part of this is 5% and the only
	// bright frame is the release.
	vec3 lip_col = mix(interior_color, rim_color, clamp(rim, 0.0, 1.0));
	ALBEDO = mix(ALBEDO, lip_col, lip * reveal * 0.85);
	EMISSION += rim_color * lip * reveal * (0.05 + 0.45 * clamp(edge_glow, 0.0, 1.0));
}
