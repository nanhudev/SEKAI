extends CanvasLayer
class_name IaidoScreenFX

var focus_rect: ColorRect
var glass_rect: ColorRect
var focus_material: ShaderMaterial
var glass_material: ShaderMaterial
var saturation_loss := 0.0
var vignette := 0.0
var wave := 0.0
var wave_position := -1.0
var pre_cut := 0.0
var main_cut := 0.0
var split_pixels := 0.0
var glass := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_material = ShaderMaterial.new()
	var focus_shader := Shader.new()
	focus_shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float saturation_loss = 0.0;
uniform float vignette = 0.0;
uniform float wave = 0.0;
uniform float wave_position = -1.0;
uniform float pre_cut = 0.0;
uniform float main_cut = 0.0;
uniform float split_pixels = 0.0;
void fragment() {
    vec2 center = SCREEN_UV * 2.0 - 1.0;
    float seam = center.y + center.x * 0.65;
    vec2 normal = normalize(vec2(0.65, 1.0));
    vec2 split = normal * sign(seam) * split_pixels * SCREEN_PIXEL_SIZE;
    float pressure = (1.0 - smoothstep(0.01, 0.25, abs(seam))) * wave;
    vec2 displaced = clamp(SCREEN_UV + split + normal * sign(seam) * pressure * 0.006, vec2(0.001), vec2(0.999));
    vec3 c = texture(screen_tex, displaced).rgb;
    float gray = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(c, vec3(gray), saturation_loss);
    c *= 1.0 - smoothstep(0.30, 1.55, dot(center, center)) * vignette;
    float pre_shape = step(abs(center.x), 0.70) * (0.40 + 0.60 * step(0.15, sin(center.x * 52.0)));
    float thin = 1.0 - smoothstep(0.002, 0.011, abs(seam));
    float wide = 1.0 - smoothstep(0.003, 0.029, abs(seam));
    float wave_a = 1.0 - smoothstep(0.002, 0.009, abs(seam - wave_position));
    float wave_b = 1.0 - smoothstep(0.002, 0.006, abs(seam - wave_position + 0.11));
    c = mix(c, vec3(0.92, 0.92, 0.87), (wave_a * 0.18 + wave_b * 0.09) * wave);
    c = mix(c, vec3(0.93, 0.91, 0.84), thin * pre_cut * pre_shape * 0.75 + wide * main_cut * 0.62);
    COLOR = vec4(c, 1.0);
}
"""
	focus_material.shader = focus_shader
	focus_rect = _layer("Focus And World Split", focus_material)
	glass_material = ShaderMaterial.new()
	var glass_shader := Shader.new()
	glass_shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform float glass = 0.0;
uniform float main_cut = 0.0;
void fragment() {
    vec2 p = SCREEN_UV * 2.0 - 1.0;
    float seam = p.y + p.x * 0.65;
    float cracks = 0.0;
    float shards = 0.0;
    for (int i = 0; i < 10; i++) {
        float f = float(i);
        float x = (f - 4.5) * 0.16;
        float y = -x * 0.65;
        vec2 d = p - vec2(x, y);
        float side = mod(f, 2.0) < 1.0 ? 1.0 : -1.0;
        float ray = abs(d.y - d.x * (side * 0.85 + 0.12));
        float segment = step(0.0, d.x * side) * (1.0 - smoothstep(0.15, 0.38, length(d)));
        cracks += (1.0 - smoothstep(0.002, 0.006, ray)) * segment;
        if (i < 5) {
            vec2 shard_p = vec2(x + side * 0.07, y + side * 0.06);
            vec2 q = p - shard_p;
            float mask = step(abs(q.x) + abs(q.y * 0.7), 0.065);
            shards += mask * (0.12 + 0.08 * sin(f * 13.0));
        }
    }
    float edge = (1.0 - smoothstep(0.0, 0.009, abs(seam))) * main_cut;
    COLOR = vec4(vec3(0.97, 0.95, 0.88), clamp(cracks * glass * 0.58 + shards * glass + edge * 0.18, 0.0, 0.68));
}
"""
	glass_material.shader = glass_shader
	glass_rect = _layer("Glass Fracture", glass_material)
	reset_iaido_fx()


func _layer(label: String, shader_material: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = label
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.material = shader_material
	add_child(rect)
	return rect


func set_frame(focus: float, wave_amount: float, pre_amount: float, cut_amount: float, split_amount: float, glass_amount: float, wave_phase: float = -1.0) -> void:
	saturation_loss = focus * 0.75
	vignette = focus * 0.24
	wave = wave_amount
	wave_position = wave_phase
	pre_cut = pre_amount
	main_cut = cut_amount
	split_pixels = split_amount
	glass = glass_amount
	focus_material.set_shader_parameter("saturation_loss", saturation_loss)
	focus_material.set_shader_parameter("vignette", vignette)
	focus_material.set_shader_parameter("wave", wave)
	focus_material.set_shader_parameter("wave_position", wave_position)
	focus_material.set_shader_parameter("pre_cut", pre_cut)
	focus_material.set_shader_parameter("main_cut", main_cut)
	focus_material.set_shader_parameter("split_pixels", split_pixels)
	glass_material.set_shader_parameter("glass", glass)
	glass_material.set_shader_parameter("main_cut", main_cut)
	focus_rect.visible = focus > 0.001 or wave_amount > 0.001 or pre_amount > 0.001 or cut_amount > 0.001 or split_amount > 0.001
	glass_rect.visible = glass_amount > 0.001 or cut_amount > 0.001


func reset_iaido_fx() -> void:
	set_frame(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
