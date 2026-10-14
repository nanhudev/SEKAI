extends RefCounted
class_name MirrorTravel
# ENTER → TRANSIT → EXIT for A4 shift and Q travel. No mirror-world locomotion in V0.1.

enum Phase { IDLE, ENTER, TRANSIT, SELECT, EXIT }

signal phase_changed(phase: int)
signal exited(mirror: MirrorNode)
signal travel_failed(reason: StringName)

var config: MirrorConfig
var player: CharacterBody3D
var camera_fb: CameraFeedbackController
var manager: MirrorManager
var look: Node3D

var phase := Phase.IDLE
var target: MirrorNode
var time_left := 0.0
var select_left := 0.0
var invulnerable := false
var preserve_view := true
var _enter_overlay: ColorRect
var _overlay_layer: CanvasLayer
var _saved_fov_kick := 0.0
var _mode: StringName = &""  # &"shift" | &"travel"


func configure(
	cfg: MirrorConfig,
	player_body: CharacterBody3D,
	cam_fb: CameraFeedbackController,
	mgr: MirrorManager,
	look_pivot: Node3D
) -> void:
	config = cfg
	player = player_body
	camera_fb = cam_fb
	manager = mgr
	look = look_pivot
	preserve_view = cfg.preserve_view_direction


func is_active() -> bool:
	return phase != Phase.IDLE


func is_in_select() -> bool:
	return phase == Phase.SELECT


func begin_shift(preferred: MirrorNode) -> bool:
	if is_active():
		return false
	var node := preferred
	if node == null and manager != null:
		node = manager.get_aim_selected_node()
	if node == null:
		travel_failed.emit(&"no_mirror")
		return false
	if not node.travel_exit_ok:
		travel_failed.emit(&"unsafe_exit")
		# Still allow with clamped fallback if exit transform exists.
		if node.safe_exit.origin == Vector3.ZERO:
			return false
	_mode = &"shift"
	target = node
	_set_phase(Phase.ENTER)
	time_left = 0.06
	_ensure_overlay()
	_set_overlay(0.55)
	if camera_fb != null:
		camera_fb.fov_kick(config.travel_fov_kick * 0.5)
	return true


func begin_travel() -> bool:
	if is_active():
		return false
	if manager == null or manager.count() == 0:
		travel_failed.emit(&"no_mirror")
		return false
	_mode = &"travel"
	target = manager.update_selection()
	_set_phase(Phase.ENTER)
	time_left = 0.08
	select_left = config.travel_duration
	_ensure_overlay()
	_set_overlay(0.65)
	invulnerable = config.travel_invuln
	if camera_fb != null:
		camera_fb.fov_kick(config.travel_fov_kick)
	return true


func confirm_exit(preferred: MirrorNode = null) -> bool:
	if phase != Phase.SELECT:
		return false
	var node := preferred
	if node == null and manager != null:
		node = manager.get_aim_selected_node()
	if node == null:
		travel_failed.emit(&"no_target")
		return false
	if not node.travel_exit_ok and node.safe_exit.origin == Vector3.ZERO:
		travel_failed.emit(&"unsafe_exit")
		return false
	target = node
	_set_phase(Phase.TRANSIT)
	time_left = config.a4_transit_ms
	return true


func cancel() -> void:
	_finish(false)


func tick(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	match phase:
		Phase.ENTER:
			time_left = maxf(0.0, time_left - delta)
			_set_overlay(0.55 + (1.0 - time_left / 0.1) * 0.15)
			if time_left <= 0.0:
				if _mode == &"travel":
					_set_phase(Phase.SELECT)
				else:
					_set_phase(Phase.TRANSIT)
					time_left = config.a4_transit_ms
		Phase.SELECT:
			select_left = maxf(0.0, select_left - delta)
			if manager != null:
				manager.update_selection()
			_set_overlay(0.45 + 0.12 * sin(Time.get_ticks_msec() * 0.006))
			if select_left <= 0.0:
				# Auto-exit nearest / selected if time runs out.
				confirm_exit(manager.get_aim_selected_node() if manager else null)
		Phase.TRANSIT:
			time_left = maxf(0.0, time_left - delta)
			_set_overlay(0.75)
			if time_left <= 0.0:
				_perform_exit()
		Phase.EXIT:
			time_left = maxf(0.0, time_left - delta)
			_set_overlay(maxf(0.0, time_left / 0.12) * 0.4)
			if time_left <= 0.0:
				_finish(true)


func _perform_exit() -> void:
	if target == null or not is_instance_valid(target) or player == null:
		travel_failed.emit(&"lost_target")
		_finish(false)
		return
	var xf := target.safe_exit
	if not target.travel_exit_ok:
		# Soft fail: push slightly along normal from mirror.
		var n := target.get_mirror_normal()
		if n.length_squared() < 0.0001:
			n = Vector3.FORWARD
		n = n.normalized()
		var up := Vector3.UP
		if absf(n.dot(up)) > 0.95:
			up = Vector3.RIGHT
		xf = Transform3D(
			Basis.looking_at(n, up),
			target.global_position + n * config.exit_offset_min
		)
	player.global_position = xf.origin
	player.velocity = Vector3.ZERO
	if not preserve_view and look != null:
		var flat := target.get_mirror_normal()
		flat.y = 0.0
		if flat.length_squared() > 0.001:
			# Blend yaw toward mirror forward without snapping pitch.
			var yaw := atan2(-flat.x, -flat.z)
			look.rotation.y = lerpf(look.rotation.y, yaw, 0.55)
	_set_phase(Phase.EXIT)
	time_left = 0.12
	exited.emit(target)


func _finish(success: bool) -> void:
	invulnerable = false
	_set_overlay(0.0)
	_set_phase(Phase.IDLE)
	_mode = &""
	if not success:
		target = null


func _set_phase(p: Phase) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(int(p))


func _ensure_overlay() -> void:
	if _overlay_layer != null or player == null:
		return
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "MirrorTravelOverlay"
	_overlay_layer.layer = 8
	player.add_child(_overlay_layer)
	_enter_overlay = ColorRect.new()
	_enter_overlay.name = "Tint"
	_enter_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_enter_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enter_overlay.color = Color(config.tint_color.r, config.tint_color.g, config.tint_color.b, 0.0)
	_overlay_layer.add_child(_enter_overlay)


func _set_overlay(alpha: float) -> void:
	if _enter_overlay == null:
		return
	var c := config.tint_color
	_enter_overlay.color = Color(c.r, c.g, c.b, clampf(alpha, 0.0, 0.85))
	_overlay_layer.visible = alpha > 0.01
