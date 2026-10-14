shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, specular_disabled;

// SEKAI · PHANTOM CHAIN / 虚链
// Semi-transparent rule-link. Tension makes it real.
// Per-link along = COLOR.g (written by MultiMesh instance color).

uniform vec4 base_color : source_color = vec4(0.72, 0.80, 0.90, 1.0);
uniform float alpha = 0.40;
uniform float edge_emission = 0.35;
uniform float tension = 0.0;
uniform float fade = 1.0;
uniform float flow = 0.0;
uniform float hit_flash = 0.0;
uniform float spawn_progress = 1.0;
uniform float dissolve_progress = 0.0;

varying float v_along;
varying float v_variant;

void vertex() {
	v_variant = INSTANCE_CUSTOM.r;
	v_along = INSTANCE_CUSTOM.g;
}

void fragment() {
	float t = clamp(tension, 0.0, 1.0);
	float flash = clamp(hit_flash, 0.0, 1.0);
	float along = clamp(v_along, 0.0, 1.0);

	// Spawn start→end; dissolve end→start (hide high-along first).
	float spawn_gate = step(along - 0.001, spawn_progress);
	float dissolve_gate = 1.0 - step(1.0 - dissolve_progress + 0.001, along);
	float presence = spawn_gate * dissolve_gate * clamp(fade, 0.0, 1.0);
	if (presence <= 0.001) {
		discard;
	}

	float rim = pow(1.0 - abs(dot(normalize(NORMAL), VIEW)), 1.8);
	float flow_band = 0.5 + 0.5 * sin(along * 18.0 - flow * 6.0 + v_variant * 3.0);

	vec3 cold = base_color.rgb;
	vec3 solid = mix(cold, vec3(0.88, 0.93, 1.0), t * 0.55);
	solid = mix(solid, vec3(0.95, 0.98, 1.0), flash);
	// Slight violet optional on alternate links.
	solid = mix(solid, vec3(0.78, 0.72, 0.95), v_variant * 0.08 * (1.0 - t));

	float body_a = mix(0.28, 0.82, t);
	body_a = mix(body_a, 0.92, flash);
	body_a *= presence;
	body_a *= mix(0.85, 1.1, flow_band * 0.25);

	ALBEDO = solid;
	EMISSION = solid * (edge_emission * (0.25 + rim * 0.9) + flash * 0.8 + t * 0.35);
	ALPHA = clamp(body_a * alpha / 0.40, 0.0, 1.0);
}
