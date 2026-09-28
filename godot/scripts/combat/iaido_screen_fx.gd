extends CanvasLayer
class_name IaidoScreenFX
# Composites the world-only cut above the desaturated world and below the
# weapon foreground, so the sword is never torn, desaturated or shattered.
#
# This node is a thin pass-through: the director samples the timeline and hands
# over a frame dictionary, and the shader + reverse-wave overlay render it.

var focus_rect: ColorRect
var focus_material: ShaderMaterial
var reverse_wave: ReverseWaveEffect
var last_resolution := Vector2.ZERO

# The UE5-baked reality fracture. Bound once: the network is fixed data, and the
# shader derives how much of it is revealed from `fracture` / `shatter`, so
# nothing has to be pushed per frame.
const CRACK_MASK := "res://resources/vfx/reality_crack_mask.png"
const EDGE_MASK := "res://resources/vfx/reality_edge_mask.png"
const FLOW_MASK := "res://resources/vfx/reality_flow_mask.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 6
	focus_material = ShaderMaterial.new()
	focus_material.shader = preload("res://vfx/iaido_world_split.gdshader")
	_bind_fracture_masks()
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


func _bind_fracture_masks() -> void:
	for pair in [["crack_mask", CRACK_MASK], ["edge_mask", EDGE_MASK], ["flow_mask", FLOW_MASK]]:
		var path := String(pair[1])
		if not ResourceLoader.exists(path):
			push_warning("IaidoScreenFX: missing fracture mask %s" % path)
			continue
		focus_material.set_shader_parameter(String(pair[0]), load(path))


func present(frame: Dictionary) -> void:
	var focus := float(frame.get("focus", 0.0))
	var void_open := float(frame.get("void_open", 0.0))
	var gap_px := float(frame.get("gap_px", 0.0))
	var separation_px := float(frame.get("separation_px", 0.0))
	var fracture := float(frame.get("fracture", 0.0))
	var shatter := float(frame.get("shatter", 0.0))
	var dissolve := float(frame.get("dissolve", 0.0))
	var wave_strength := float(frame.get("wave_strength", 0.0))

	last_resolution = frame.get("resolution", Vector2(1920.0, 1080.0))
	focus_material.set_shader_parameter("resolution", last_resolution)
	focus_material.set_shader_parameter("cut_center", frame.get("cut_center", Vector2(0.5, 0.5)))
	focus_material.set_shader_parameter("cut_angle", float(frame.get("cut_angle", -30.0)))
	focus_material.set_shader_parameter("time", float(frame.get("time", 0.0)))
	# The void reads off its own clock so the time stop can stall it.
	focus_material.set_shader_parameter("void_clock", float(frame.get("void_clock", frame.get("time", 0.0))))
	focus_material.set_shader_parameter("focus", focus)
	# Colour leaves the world from the koiguchi outward: `focus` is how much has
	# gone, this is how far it has spread. Bound separately because a uniform
	# drain is a filter and a filter has no cause.
	focus_material.set_shader_parameter("grey_spread", float(frame.get("grey_spread", 0.0)))
	# How far along the slash the glassification front has travelled. The cracks,
	# the surface turning to glass and the world being consumed all read it, so
	# they cannot drift apart.
	focus_material.set_shader_parameter("stream", float(frame.get("stream", 0.0)))
	focus_material.set_shader_parameter("void_open", void_open)
	focus_material.set_shader_parameter("gap_px", gap_px)
	focus_material.set_shader_parameter("separation_px", separation_px)
	focus_material.set_shader_parameter("depth_parallax", float(frame.get("depth_parallax", 0.010)))
	focus_material.set_shader_parameter("restore_pull", float(frame.get("restore_pull", 0.0)))
	focus_material.set_shader_parameter("slide_px", float(frame.get("slide_px", 0.0)))
	focus_material.set_shader_parameter("ivory_flash", float(frame.get("ivory_flash", 0.0)))
	focus_material.set_shader_parameter("blade_flash", float(frame.get("blade_flash", 0.0)))
	focus_material.set_shader_parameter("void_life", float(frame.get("void_life", 1.0)))
	focus_material.set_shader_parameter("void_speed", float(frame.get("void_speed", 0.10)))
	focus_material.set_shader_parameter("void_back_color", frame.get("void_back_color", Color(0.008, 0.027, 0.067)))
	focus_material.set_shader_parameter("void_deep_color", frame.get("void_deep_color", Color(0.024, 0.078, 0.165)))
	focus_material.set_shader_parameter("void_lip_color", frame.get("void_lip_color", Color(0.043, 0.165, 0.290)))
	focus_material.set_shader_parameter("void_core_color", frame.get("void_core_color", Color(0.560, 0.740, 0.850)))
	focus_material.set_shader_parameter("void_edge_width_px", float(frame.get("void_edge_width_px", 3.0)))
	# The world drains BOTH where the glassification stream has passed and, at the
	# end, everywhere the devour has reached. See PHASE M2 in iaido_tuning.gd.
	focus_material.set_shader_parameter("world_drain", float(frame.get("world_drain", 0.0)))
	focus_material.set_shader_parameter("drained_world_color", frame.get("drained_world_color", Color(0.014, 0.022, 0.046)))
	focus_material.set_shader_parameter("drained_world_deep", frame.get("drained_world_deep", Color(0.004, 0.006, 0.016)))
	focus_material.set_shader_parameter("drain_crack_fade", float(frame.get("drain_crack_fade", 0.85)))
	# NOTE: V4 deleted `cut_face_px` / `cut_lip_px` along with the geometry that
	# drew the black bar. The wound is bounded only by per-face chip noise now,
	# so there is nothing left to bind here. Do not re-add them.
	focus_material.set_shader_parameter("fracture", fracture)
	focus_material.set_shader_parameter("shatter", shatter)
	focus_material.set_shader_parameter("dissolve", dissolve)
	focus_material.set_shader_parameter("refract_px", float(frame.get("refract_px", 5.0)))
	focus_material.set_shader_parameter("rim_px", float(frame.get("rim_px", 2.5)))
	focus_material.set_shader_parameter("shatter_px", float(frame.get("shatter_px", 26.0)))
	focus_material.set_shader_parameter("wave_strength", wave_strength)
	focus_material.set_shader_parameter("wave_a", float(frame.get("wave_a", 0.0)))
	focus_material.set_shader_parameter("wave_b", float(frame.get("wave_b", 0.0)))
	focus_material.set_shader_parameter("wave_c", float(frame.get("wave_c", 0.0)))
	focus_material.set_shader_parameter("wave_suck", float(frame.get("wave_suck", 0.0)))
	focus_material.set_shader_parameter("sheath_uv", frame.get("sheath_uv", Vector2(0.22, 0.80)))

	reverse_wave.set_frame(
		frame.get("sheath_uv", Vector2(0.22, 0.80)),
		Vector3(float(frame.get("wave_a", 0.0)), float(frame.get("wave_b", 0.0)), float(frame.get("wave_c", 0.0))),
		wave_strength,
		float(frame.get("wave_suck", 0.0))
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
		or absf(float(frame.get("blade_flash", 0.0))) > 0.001
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
		"wave_suck": 0.0,
		"ivory_flash": 0.0,
		"blade_flash": 0.0,
		"sheath_uv": Vector2(0.22, 0.80),
		"resolution": last_resolution if last_resolution.length_squared() > 1.0 else Vector2(1920.0, 1080.0),
	})
	focus_rect.visible = false
	if reverse_wave != null:
		reverse_wave.set_frame(Vector2(0.22, 0.80), Vector3.ZERO, 0.0, 0.0)
