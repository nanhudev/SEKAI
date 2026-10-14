extends CanvasLayer
class_name CombatScreenFX

var overlay: ColorRect
var material: ShaderMaterial
var desaturation := 0.0
var vignette := 0.0
var flash := 0.0
var ink_slash := 0.0
var distortion := 0.0


func _ready() -> void:
	overlay = ColorRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; uniform sampler2D screen_tex : hint_screen_texture, filter_linear; uniform float desaturation = 0.0; uniform float vignette = 0.0; uniform float flash = 0.0; uniform float ink_slash = 0.0; uniform float distortion = 0.0; void fragment() { vec2 uv = SCREEN_UV * 2.0 - 1.0; float seam = uv.y + uv.x * 0.65; float warp = (1.0 - smoothstep(0.0, 0.11, abs(seam))) * distortion; vec2 displaced = clamp(SCREEN_UV + vec2(sign(seam) * warp * 0.012, -warp * 0.004), vec2(0.001), vec2(0.999)); vec3 c = texture(screen_tex, displaced).rgb; float gray = dot(c, vec3(0.299, 0.587, 0.114)); c = mix(c, vec3(gray), desaturation); float edge = smoothstep(0.25, 1.6, dot(uv, uv)); c *= 1.0 - edge * vignette; float line = 1.0 - smoothstep(0.002, 0.015, abs(seam)); c = mix(c, vec3(1.0), line * ink_slash); c += vec3(flash); COLOR = vec4(c, 1.0); }"
	material = ShaderMaterial.new()
	material.shader = shader
	overlay.material = material
	_update_shader()


func set_iaido_focus(amount: float) -> void:
	desaturation = clampf(amount, 0.0, 0.82)
	vignette = clampf(amount * 0.35, 0.0, 0.28)
	_update_shader()


func set_world_drain(amount: float) -> void:
	# Iaido PHASE A: the world is being switched off. Desaturate hard, pull a
	# cold vignette in, and leave the void in the split shader untouched.
	desaturation = clampf(amount, 0.0, 0.82)
	vignette = clampf(amount * 0.32, 0.0, 0.26)
	_update_shader()


func slash_flash(amount: float) -> void:
	ink_slash = clampf(amount, 0.0, 1.0)
	flash = 0.12 * ink_slash
	_update_shader()


func set_distortion(amount: float) -> void:
	distortion = clampf(amount, 0.0, 1.0)
	_update_shader()


func flash_hit(amount: float) -> void:
	flash = maxf(flash, clampf(amount, 0.0, 1.0))
	_update_shader()


func _process(delta: float) -> void:
	if flash > 0.0 or ink_slash > 0.0:
		flash = maxf(0.0, flash - delta * 2.8)
		ink_slash = maxf(0.0, ink_slash - delta * 3.5)
		_update_shader()


func reset() -> void:
	desaturation = 0.0
	vignette = 0.0
	flash = 0.0
	ink_slash = 0.0
	distortion = 0.0
	_update_shader()


func _update_shader() -> void:
	if material == null:
		return
	material.set_shader_parameter("desaturation", desaturation)
	material.set_shader_parameter("vignette", vignette)
	material.set_shader_parameter("flash", flash)
	material.set_shader_parameter("ink_slash", ink_slash)
	material.set_shader_parameter("distortion", distortion)
	overlay.visible = desaturation > 0.001 or vignette > 0.001 or flash > 0.001 or ink_slash > 0.001 or distortion > 0.001
