shader_type spatial;
render_mode cull_back;
uniform vec4 steel_color : source_color = vec4(0.46,0.472,0.496,1.0);
uniform float steel_metallic = 0.58;
uniform float steel_roughness = 0.22;
varying vec3 blade_point;

void vertex() {
    blade_point = VERTEX;
}

void fragment() {
    // Directional polishing and small irregular wear, no glowing painted edge.
    float grain = sin(blade_point.x * 4100.0 + sin(blade_point.y * 17.0) * 0.6);
    float scratch = pow(max(0.0,sin(blade_point.x * 1770.0 + blade_point.y * 3.4)),24.0);
    scratch *= smoothstep(0.05,0.18,blade_point.y) * (0.35 + 0.65 * pow(max(0.0,sin(blade_point.y*27.0+1.3)),6.0));
    ALBEDO = steel_color.rgb * (1.0 - scratch * 0.055 + grain * 0.008);
    METALLIC = steel_metallic;
    ROUGHNESS = clamp(steel_roughness + scratch * 0.11 + grain * 0.016,0.16,0.42);
    SPECULAR = 0.55;
}
