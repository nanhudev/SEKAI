shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.9, 0.96, 1.0, 1.0);
uniform float opacity = 0.0;
uniform float progress = 0.0;
uniform vec3 cut_eye;
uniform vec3 cut_forward;
uniform vec3 cut_direction;
uniform float cut_offset = 0.0;
uniform float half_length = 0.72;
varying vec3 world_point;
void vertex() {
    world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec3 relative = world_point - cut_eye;
    float depth = max(dot(relative, cut_forward), 0.01);
    float along = dot(relative, cut_direction) / depth - cut_offset;
    float u = (along + half_length) / max(2.0 * half_length, 0.01);
    ALBEDO = tint.rgb * COLOR.rgb;
    EMISSION = tint.rgb * 0.3;
    ALPHA = opacity * COLOR.a * (1.0 - smoothstep(progress - 0.025, progress, u));
}
