extends Node3D
class_name MirrorNode
# One placed mirror. Abstract surface — no realtime reflection.
# Front = -basis.z after orientation (matches Godot camera forward convention via look_at).

signal broken(node: MirrorNode)
signal selected_changed(node: MirrorNode, on: bool)

var mirror_id: int = 0
var creation_order: int = 0
var active := true
var travel_exit_ok := false
var safe_exit: Transform3D = Transform3D.IDENTITY
var label_visible := false

var _mesh: MeshInstance3D
var _frame: MeshInstance3D
var _label: Label3D
var _mat: StandardMaterial3D
var _frame_mat: StandardMaterial3D
var _spawn_t := 0.0
var _spawn_ms := 0.15
var _selected := false
var _base_scale := Vector3.ONE
var _debug_normal: MeshInstance3D
var _debug_exit: MeshInstance3D
var _show_debug := false


func configure(cfg: MirrorConfig, id: int, order: int, surface_n: Vector3) -> void:
	mirror_id = id
	creation_order = order
	_spawn_ms = cfg.spawn_anim_ms
	_spawn_t = 0.0
	_build_visual(cfg)
	_orient_to_normal(surface_n)
	scale = Vector3.ONE * 0.01
	modulate_alpha(0.0)


func get_mirror_normal() -> Vector3:
	# Facing direction of the reflective front.
	return -global_transform.basis.z


func get_front_point(distance: float = 0.0) -> Vector3:
	return global_position + get_mirror_normal() * distance


func set_selected(on: bool) -> void:
	if _selected == on:
		return
	_selected = on
	_apply_selected_visual()
	selected_changed.emit(self, on)


func is_selected() -> bool:
	return _selected


func set_label_visible(on: bool) -> void:
	label_visible = on
	if _label != null:
		_label.visible = on


func set_debug_draw(on: bool) -> void:
	_show_debug = on
	if _debug_normal != null:
		_debug_normal.visible = on
	if _debug_exit != null:
		_debug_exit.visible = on and travel_exit_ok


func modulate_alpha(a: float) -> void:
	if _mat != null:
		_mat.albedo_color.a = a
	if _frame_mat != null:
		_frame_mat.albedo_color.a = minf(1.0, a + 0.15)


func tick_spawn(delta: float) -> void:
	if _spawn_t >= _spawn_ms:
		return
	_spawn_t = minf(_spawn_ms, _spawn_t + delta)
	var u := _spawn_t / maxf(0.001, _spawn_ms)
	var e := 1.0 - (1.0 - u) * (1.0 - u)
	scale = _base_scale * e
	modulate_alpha(e * 0.78)


func _build_visual(cfg: MirrorConfig) -> void:
	_base_scale = Vector3(cfg.mirror_width, cfg.mirror_height, 0.04)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mat.albedo_color = cfg.node_color
	_mat.metallic = 0.85
	_mat.roughness = 0.22
	_mat.emission_enabled = true
	_mat.emission = cfg.card_fresnel * 0.35
	_mat.emission_energy_multiplier = 0.55
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh = MeshInstance3D.new()
	_mesh.name = "Surface"
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	_mesh.mesh = box
	_mesh.material_override = _mat
	add_child(_mesh)

	_frame_mat = StandardMaterial3D.new()
	_frame_mat.albedo_color = Color(0.72, 0.78, 0.82, 0.95)
	_frame_mat.metallic = 0.6
	_frame_mat.roughness = 0.4
	_frame = MeshInstance3D.new()
	_frame.name = "Frame"
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(1.08, 1.08, 0.35)
	_frame.mesh = frame_mesh
	_frame.material_override = _frame_mat
	_frame.scale = Vector3(1.0, 1.0, 0.08)
	add_child(_frame)

	_label = Label3D.new()
	_label.name = "DebugLabel"
	_label.text = "M%d" % mirror_id
	_label.font_size = 48
	_label.pixel_size = 0.012
	_label.position = Vector3(0.0, 0.65, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(0.75, 0.95, 1.0, 1.0)
	_label.visible = false
	add_child(_label)

	_debug_normal = _make_debug_arrow(Color(0.4, 0.9, 1.0), "DebugNormal")
	_debug_normal.visible = false
	_debug_exit = _make_debug_sphere(Color(0.3, 1.0, 0.55), "DebugExit")
	_debug_exit.visible = false


func _make_debug_arrow(color: Color, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 1.0
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	# Cylinder default is Y-up; rotate to face -Z (mirror forward).
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.position = Vector3(0, 0, -0.55)
	add_child(mi)
	return mi


func _make_debug_sphere(color: Color, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)
	return mi


func _orient_to_normal(surface_n: Vector3) -> void:
	var n := surface_n
	if n.length_squared() < 0.0001:
		n = Vector3.FORWARD
	n = n.normalized()
	# Floor-ish: stand the mirror up facing roughly away from the hit point's "up projection".
	if absf(n.y) > 0.72:
		var face := Vector3.FORWARD
		# Prefer world -Z if no better cue; caller may re-aim after placement.
		var target := global_position + face
		if target.distance_squared_to(global_position) > 0.0001:
			look_at(target, Vector3.UP)
		# Keep upright.
		rotation.x = 0.0
		rotation.z = 0.0
	else:
		# Wall: face along surface normal (mirror front out of wall).
		var up := Vector3.UP
		if absf(n.dot(up)) > 0.95:
			up = Vector3.RIGHT
		var target := global_position + n
		if target.distance_squared_to(global_position) > 0.0001:
			look_at(target, up)


func set_safe_exit(xf: Transform3D, ok: bool) -> void:
	safe_exit = xf
	travel_exit_ok = ok
	if _debug_exit != null:
		_debug_exit.global_position = xf.origin
		_debug_exit.visible = _show_debug and ok


func _apply_selected_visual() -> void:
	if _mat == null:
		return
	if _selected:
		_mat.emission_energy_multiplier = 1.4
		scale = _base_scale * 1.08
	else:
		_mat.emission_energy_multiplier = 0.55
		if _spawn_t >= _spawn_ms:
			scale = _base_scale


func _process(delta: float) -> void:
	tick_spawn(delta)
	if _debug_normal != null and _show_debug:
		_debug_normal.visible = true
	if _label != null and label_visible:
		_label.text = "M%d%s" % [mirror_id, " ★" if _selected else ""]
