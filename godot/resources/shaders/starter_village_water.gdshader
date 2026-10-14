shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform float flow_time = 0.0;
uniform bool falling_water = false;
varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    if (!falling_water) {
        NORMAL = vec3(0.0, 1.0, 0.0);
        TANGENT = vec3(1.0, 0.0, 0.0);
        BINORMAL = vec3(0.0, 0.0, 1.0);
    }
}

void fragment() {
    vec2 p = world_position.xz;
    float a = sin(p.y * 4.0 - flow_time * 2.0 + sin(p.x * 0.7) * 1.5);
    float b = sin(p.y * 9.0 - flow_time * 3.6 + sin(p.x * 1.8) * 2.0);
    float streak = sin(UV.x * 47.0 + sin(UV.x * 19.0) + UV.y * 7.0 - flow_time * 3.2);
    float foam = falling_water ? smoothstep(0.25, 0.9, streak) : smoothstep(0.92, 1.0, a) * smoothstep(0.2, 0.8, sin(p.x * 1.7 + sin(p.y * 0.3)));
    vec3 liquid = mix(vec3(0.035, 0.27, 0.30), vec3(0.05, 0.34, 0.36), 0.5 + 0.5 * a);
    ALBEDO = mix(liquid, vec3(0.61, 0.81, 0.78), foam * (falling_water ? 0.83 : 0.13));
    EMISSION = ALBEDO * 0.07;
    NORMAL_MAP = vec3(0.5 + a * 0.055, 0.5 + b * 0.055, 1.0);
    NORMAL_MAP_DEPTH = 0.42;
    ROUGHNESS = falling_water ? 0.5 : 0.32;
    SPECULAR = 0.45;
    ALPHA = falling_water ? 0.84 : 0.86;
}
