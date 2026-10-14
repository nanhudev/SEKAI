shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

// Shared surface language for the first Golden Path material variants.
// Parameter sets supply color and roughness; geometry supplies the large form.
uniform vec3 base_color : source_color = vec3(0.43, 0.38, 0.31);
uniform vec3 secondary_color : source_color = vec3(0.52, 0.48, 0.39);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float patch_scale = 0.18;
uniform float grain_scale = 1.45;
varying vec3 world_pos;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise2(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float macro = noise2(world_pos.xz * 0.025);
    float meso = noise2(world_pos.xz * patch_scale);
    float micro = noise2(world_pos.xz * grain_scale);
    float mix_amount = smoothstep(0.31, 0.72, meso * 0.77 + macro * 0.23);
    vec3 albedo = mix(base_color, secondary_color, mix_amount);
    float resolved = 1.0 - smoothstep(0.28, 0.95, fwidth(world_pos.x) + fwidth(world_pos.z));
    albedo *= 0.93 + (meso - 0.5) * 0.10 + (micro - 0.5) * 0.08 * resolved;
    ALBEDO = albedo;
    ROUGHNESS = roughness;
    SPECULAR = 0.18;
}
