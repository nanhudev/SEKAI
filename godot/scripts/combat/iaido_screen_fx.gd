extends CanvasLayer
class_name IaidoScreenFX
# Composites the world-only cut above the desaturated world and below the
# weapon foreground, so the sword is never torn, desaturated or shattered.

var focus_rect: ColorRect
var focus_material: ShaderMaterial
var reverse_wave: ReverseWaveEffect
var last_resolution := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 6
	focus_material = ShaderMaterial.new()
	focus_material.shader = preload("res://vfx/iaido_world_split.gdshader")
	focus_rect = ColorRect.new()
	focus_rect.name = "WorldOnlySplit"
	focus_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_rect.material = focus_material
	add_child(focus_rect)
	reverse_wave = ReverseWaveEffect.new()
	reverse_wave.name = "ReverseWaveEffect"
	add_child(reverse_wave)
	reset_iaido_fx()


func present(frame: Dictionary) -> void:
	var focus := float(frame.get("focus", 0.0))
	var void_open := float(frame.get("void_open", 0.0))
	var gap_px := float(frame.get("gap_px", 0.0))
	var separation_px := float(frame.get("separation_px", 0.0))
	var fracture := float(frame.get("fracture", 0.0))
	var shatter := float(frame.get("shatter", 0.0))
	var dissolve := float(frame.get("dissolve", 0.0))
	var wave_strength := float(frame.get("wave_strength", 0.0))

	focus_material.set_shader_parameter("resolution", frame.get("resolution", Vector2(1920.0, 1080.0)))
	focus_material.set_shader_parameter("cut_center", frame.get("cut_center", Vector2(0.5, 0.5)))
	focus_material.set_shader_parameter("cut_angle", float(frame.get("cut_angle", -30.0)))
	focus_material.set_shader_parameter("time", float(frame.get("time", 0.0)))
	focus_material.set_shader_parameter("focus", focus)
	focus_material.set_shader_parameter("void_open", void_open)
	focus_material.set_shader_parameter("gap_px", gap_px)
	focus_material.set_shader_parameter("separation_px", separation_px)
	focus_material.set_shader_parameter("depth_parallax", float(frame.get("depth_parallax", 0.006)))
	focus_material.set_shader_parameter("restore_pull", float(frame.get("restore_pull", 0.0)))
	focus_material.set_shader_parameter("slide_px", float(frame.get("slide_px", 0.0)))
	focus_material.set_shader_parameter("ivory_flash", float(frame.get("ivory_flash", 0.0)))
	focus_material.set_shader_parameter("void_life", float(frame.get("void_life", 1.0)))
	focus_material.set_shader_parameter("void_edge_color", frame.get("void_edge_color", Color(0.020, 0.043, 0.110)))
	focus_material.set_shader_parameter("void_mid_color", frame.get("void_mid_color", Color(0.086, 0.125, 0.320)))
	focus_material.set_shader_parameter("void_core_color", frame.get("void_core_color", Color(0.760, 0.870, 0.950)))
	focus_material.set_shader_parameter("void_core_width", float(frame.get("void_core_width", 0.16)))
	focus_material.set_shader_parameter("void_edge_width_px", float(frame.get("void_edge_width_px", 2.2)))
	focus_material.set_shader_parameter("fracture", fracture)
	focus_material.set_shader_parameter("shatter", shatter)
	focus_material.set_shader_parameter("dissolve", dissolve)
	focus_material.set_shader_parameter("refract_px", float(frame.get("refract_px", 6.0)))
	focus_material.set_shader_parameter("rim_px", float(frame.get("rim_px", 3.5)))
	focus_material.set_shader_parameter("wave_strength", wave_strength)
	focus_material.set_shader_parameter("wave_a", float(frame.get("wave_a", 0.0)))
	focus_material.set_shader_parameter("wave_b", float(frame.get("wave_b", 0.0)))
	focus_material.set_shader_parameter("wave_c", float(frame.get("wave_c", 0.0)))
	focus_material.set_shader_parameter("sheath_uv", frame.get("sheath_uv", Vector2(0.22, 0.80)))

	reverse_wave.set_frame(
		frame.get("sheath_uv", Vector2(0.22, 0.80)),
		Vector3(float(frame.get("wave_a", 0.0)), float(frame.get("wave_b", 0.0)), float(frame.get("wave_c", 0.0))),
		wave_strength
	)

	focus_rect.visible = (
		focus > 0.001
		or void_open > 0.001
		or gap_px > 0.01
		or separation_px > 0.01
		or fracture > 0.001
		or shatter > 0.001
		or wave_strength > 0.001
		or absf(float(frame.get("ivory_flash", 0.0))) > 0.001
	)


func reset_iaido_fx() -> void:
	if focus_material == null:
		return
	present({
		"focus": 0.0,
		"void_open": 0.0,
		"gap_px": 0.0,
		"separation_px": 0.0,
		"fracture": 0.0,
		"shatter": 0.0,
		"dissolve": 0.0,
		"wave_strength": 0.0,
		"wave_a": 0.0,
		"wave_b": 0.0,
		"wave_c": 0.0,
		"ivory_flash": 0.0,
		"sheath_uv": Vector2(0.22, 0.80),
		"resolution": last_resolution if last_resolution.length_squared() > 1.0 else Vector2(1920.0, 1080.0),
	})
	focus_rect.visible = false
	if reverse_wave != null:
		reverse_wave.set_frame(Vector2(0.22, 0.80), Vector3.ZERO, 0.0)
