shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 stone_light : source_color = vec3(0.56, 0.55, 0.52);
uniform vec3 stone_dark : source_color = vec3(0.39, 0.40, 0.39);
uniform vec3 wet_stone : source_color = vec3(0.27, 0.34, 0.35);
uniform vec3 mortar : source_color = vec3(0.25, 0.26, 0.26);

varying vec3 world_position;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Courses follow the existing arch geometry. Alternating widths break the
	// ruler-straight joints without introducing a noisy stone wall texture.
	float along = dot(world_position.xz, vec2(-0.83, -0.56));
	float course = floor(world_position.y / 0.82);
	float stagger = mod(course, 2.0) * 0.87 + hash12(vec2(course, 7.0)) * 0.19;
	float u = (along + stagger) / 1.85;
	float cell = floor(u);
	float shade = hash12(vec2(cell, course));
	vec3 stone = mix(stone_dark, stone_light, 0.38 + 0.58 * shade);
	float grain = hash12(floor(world_position.xz * 3.0) + vec2(course, cell));
	stone *= 0.94 + grain * 0.10;
	float joint_v = 1.0 - smoothstep(0.018, 0.045, min(fract(u), 1.0 - fract(u)));
	float joint_h = 1.0 - smoothstep(0.025, 0.070,
		min(fract(world_position.y / 0.82), 1.0 - fract(world_position.y / 0.82)));
	stone = mix(stone, mortar, max(joint_v, joint_h) * 0.52);
	float wet = 1.0 - smoothstep(6.45, 7.90, world_position.y);
	stone = mix(stone, wet_stone, wet * 0.67);
	ALBEDO = stone;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
