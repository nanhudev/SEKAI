extends CanvasLayer
class_name CombatScreenFX

var overlay: ColorRect
var material: ShaderMaterial
var desaturation := 0.0
var vignette := 0.0
var flash := 0.0
var ink_slash := 0.0


func _ready() -> void:
	overlay = ColorRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; uniform sampler2D screen_tex : hint_screen_texture, filter_linear; uniform float desaturation = 0.0; uniform float vignette = 0.0; uniform float flash = 0.0; uniform float ink_slash = 0.0; void fragment() { vec3 c = texture(screen_tex, SCREEN_UV).rgb; float gray = dot(c, vec3(0.299, 0.587, 0.114)); c = mix(c, vec3(gray), desaturation); vec2 uv = SCREEN_UV * 2.0 - 1.0; float edge = smoothstep(0.25, 1.6, dot(uv, uv)); c *= 1.0 - edge * vignette; float seam = abs(uv.y + uv.x * 0.65); float line = 1.0 - smoothstep(0.002, 0.015, seam); c = mix(c, vec3(1.0), line * ink_slash); c += vec3(flash); COLOR = vec4(c, 1.0); }"
	material = ShaderMaterial.new()
	material.shader = shader
	overlay.material = material
	_update_shader()


func set_iaido_focus(amount: float) -> void:
	desaturation = clampf(amount, 0.0, 0.7)
	vignette = clampf(amount * 0.35, 0.0, 0.25)
	_update_shader()


func slash_flash(amount: float) -> void:
	ink_slash = clampf(amount, 0.0, 1.0)
	flash = 0.12 * ink_slash
	_update_shader()


func reset() -> void:
	desaturation = 0.0
	vignette = 0.0
	flash = 0.0
	ink_slash = 0.0
	_update_shader()


func _update_shader() -> void:
	if material == null:
		return
	material.set_shader_parameter("desaturation", desaturation)
	material.set_shader_parameter("vignette", vignette)
	material.set_shader_parameter("flash", flash)
	material.set_shader_parameter("ink_slash", ink_slash)
