extends Node
class_name IaidoDirector
# SEKAI · Iaido / 聚合斩 — signature skill director.
#
# PHASE A  WORLD SILENCE      0.00 - 0.45   the world is switched off
# PHASE B  RETURN TO SHEATH   0.45 - 1.20   the blade walks back to the hip
# PHASE C  REVERSE WAVE       1.20 - 2.20   three shells collapse inward
# PHASE D  COMPRESSION HOLD   2.20 - 2.85   nothing happens. this is the point.
# PHASE E  SHEATH LOCK        2.85          click. FOV rips open.
# PHASE F  INSTANT DRAW       2.95 - 3.08   130ms. violent contrast.
# PHASE G  WORLD CUT          3.08 - 3.40   a real void gap opens
# PHASE H  WORLD SEPARATION   3.40 - 3.90   the halves drift apart
# PHASE I  TENSION FREEZE     3.90 - 4.25   true freeze frame
# PHASE J  GLASS FAILURE      4.25 - 4.75   the surface starts to fail
# PHASE K  SWORD CONTROL      4.40 - 5.35   two wrist revolutions
# PHASE L  SLOW SHEATHE       5.35 - 6.20   slower the closer it gets
# PHASE M  REALITY COLLAPSE   6.20 - 6.65   the world finally shatters
# PHASE N  RESTORE            6.65 - 7.20   drawn back in, reality reconnects
#
# The draw itself is one tenth of the runtime. Everything else exists to make
# that one tenth land. Do not "optimise" this by removing the holds.

@export var tuning: IaidoTuning = preload("res://resources/tuning/IaidoTuning.tres")

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var sword: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")
@onready var iaido_fx: IaidoScreenFX = get_parent().get_node("IaidoScreenFX")
@onready var glass_layer: IaidoGlassLayer = get_parent().get_node("IaidoGlassLayer")
@onready var audio_timeline: IaidoAudioTimeline = get_parent().get_node("IaidoAudioTimeline")
@onready var screen_fx: CombatScreenFX = get_parent().get_node("CombatScreenFX")
@onready var audio_state: AudioStateController = get_parent().get_node("AudioStateController")
@onready var pause_manager: WorldPauseManager = get_parent().get_node("WorldPauseManager")
@onready var sheath_anchor: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/SheathAnchor")
@onready var time_effects: TimeEffectManager = get_parent().get_node("TimeEffectManager")
@onready var collector: IaidoTargetCollector = get_parent().get_node("IaidoTargetCollector")
@onready var tear: IaidoTear3D = get_parent().get_node("IaidoTear3D")

var active := false
var elapsed := 0.0
var hold_time := -1.0
var playback_speed := 1.0
var target: Node3D
var targets: Array[Node3D] = []
var start_position := Vector3.ZERO
var previous_modes: Dictionary = {}
var events: Dictionary = {}
var world_audio_frozen := false
var target_marks: Array[MeshInstance3D] = []
var initial_sword_position := Vector3.ZERO
var initial_sword_rotation := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	playback_speed = tuning.debug_speed
	sheath_anchor.position = tuning.sheath_position
	sheath_anchor.rotation = tuning.sheath_rotation


func start_iaido() -> void:
	if active:
		return
	time_effects.reset()
	targets = collector.collect_targets(player, camera)
	target = targets[0] if not targets.is_empty() else null
	start_position = player.global_position
	player.velocity = Vector3.ZERO
	elapsed = 0.0
	events.clear()
	world_audio_frozen = false
	active = true
	initial_sword_position = sword.position
	initial_sword_rotation = sword.rotation
	iaido_fx.reset_iaido_fx()
	glass_layer.build(tuning)
	audio_timeline.reset()
	tear.global_transform = Transform3D(camera.global_basis, camera.global_position)
	for node in [camera_feedback, sword]:
		previous_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_ALWAYS
	# Ambience is pulled out fast, then the world and music are frozen.
	audio_state.duck_world_audio()
	pause_manager.acquire()


func _process(delta: float) -> void:
	if not active:
		return
	if float(player.get("health")) <= 0.0:
		finish_iaido()
		return
	elapsed = hold_time if hold_time >= 0.0 else elapsed + delta / maxf(Engine.time_scale, 0.001) * playback_speed
	combat.state_time = elapsed
	player.global_position = start_position
	player.velocity = Vector3.ZERO

	_update_camera()
	_update_world()
	_apply_weapon_pose(elapsed)
	tear.global_transform = Transform3D(camera.global_basis, camera.global_position)
	tear.stage(elapsed, tuning)
	glass_layer.stage(elapsed, tuning)
	audio_timeline.update(elapsed)
	_fire_events()
	if elapsed >= tuning.restore_end and hold_time < 0.0:
		finish_iaido()


# --- camera ---------------------------------------------------------------
# The camera does NOT shake here. It goes unnaturally still: no bob, no sway,
# no micro tremor. The contrast with the fight a moment ago is the effect.

func _update_camera() -> void:
	var t := elapsed
	var still := _track(t, _keys_still(), &"in_out")
	camera_feedback.iaido_still = still
	camera_feedback.fov_hold = _track(t, _keys_fov(), &"in_out")
	# A half-degree breath through the compression, nothing more.
	camera_feedback.iaido_pitch = deg_to_rad(0.45) * sin(IaidoTuning.span(t, tuning.hold_start, tuning.fov_pull_end) * PI)
	camera_feedback.iaido_frozen = t >= tuning.freeze_start and t < tuning.freeze_frame_end


func _keys_still() -> Array[Vector2]:
	return [
		Vector2(tuning.silence_start, 0.0),
		Vector2(tuning.silence_end, 1.0),
		Vector2(tuning.restore_start, 1.0),
		Vector2(tuning.restore_end, 0.0),
	]


func _keys_fov() -> Array[Vector2]:
	return [
		Vector2(tuning.silence_start, 0.0),
		Vector2(tuning.silence_end, tuning.silence_fov),
		Vector2(tuning.wave_start, tuning.wave_fov),
		Vector2(tuning.hold_end, tuning.hold_fov),
		Vector2(tuning.fov_pull_end, tuning.draw_fov),
		Vector2(tuning.restore_start, tuning.draw_fov),
		Vector2(tuning.restore_end, 0.0),
	]


# --- world / screen --------------------------------------------------------

func _update_world() -> void:
	var t := elapsed
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var anchor_uv := camera.unproject_position(sheath_anchor.global_position) / viewport_size.max(Vector2.ONE)
	anchor_uv.x = clampf(anchor_uv.x, -0.5, 1.5)
	anchor_uv.y = clampf(anchor_uv.y, -0.5, 1.5)

	var desaturation := _track(t, [
		Vector2(tuning.silence_start, 0.0),
		Vector2(tuning.silence_end, tuning.silence_desaturation),
		Vector2(tuning.hold_start, tuning.hold_desaturation),
		Vector2(tuning.cut_end, tuning.cut_desaturation),
		Vector2(tuning.restore_start, tuning.cut_desaturation),
		Vector2(tuning.restore_end, 0.0),
	], &"out")
	screen_fx.set_world_drain(desaturation)

	var wave_strength := (
		IaidoTuning.span(t, tuning.wave_start - 0.06, tuning.wave_start + 0.08)
		* (1.0 - IaidoTuning.span(t, tuning.wave_end - 0.18, tuning.wave_end - 0.02))
	)
	# Ring progress is linear here on purpose. The compression still accelerates
	# (the shader's radius curve steepens hard toward the centre, which is where
	# the "ease in" the design asks for actually lives), but stacking a cubic on
	# top of it kept every shell off-frame until the last tenth of a second, so
	# the reverse wave was invisible in motion.
	var wave_a := IaidoTuning.span(t, tuning.ring1_start, tuning.ring1_end)
	var wave_b := IaidoTuning.span(t, tuning.ring2_start, tuning.ring2_end)
	var wave_c := IaidoTuning.span(t, tuning.ring3_start, tuning.ring3_end)

	var void_open := _track(t, [
		Vector2(tuning.cut_start - 0.01, 0.0),
		Vector2(tuning.cut_start + 0.01, 1.0),
		Vector2(tuning.restore_end - 0.08, 1.0),
		Vector2(tuning.restore_end, 0.0),
	], &"linear")
	var gap_px := _track(t, [
		Vector2(tuning.cut_start, 0.0),
		Vector2(tuning.cut_start + 0.02, tuning.gap_start_px),
		Vector2(tuning.gap_mid_time, tuning.gap_mid_px),
		Vector2(tuning.cut_end, tuning.gap_max_px),
		Vector2(tuning.slow_sheathe_start, tuning.gap_max_px),
		Vector2(tuning.final_click, tuning.void_narrow_px),
		Vector2(tuning.collapse_end, tuning.collapse_gap_px),
		Vector2(tuning.restore_end, 0.0),
	], &"out")
	var separation_px := _track(t, [
		Vector2(tuning.separate_start, 0.0),
		Vector2(tuning.separate_end, tuning.separation_px),
		Vector2(tuning.restore_start, tuning.separation_px),
		Vector2(tuning.restore_end, 0.0),
	], &"out")
	var slide_px := _track(t, [
		Vector2(tuning.glass_end, 0.0),
		Vector2(tuning.final_click, tuning.post_break_slide_px),
		Vector2(tuning.restore_start, tuning.post_break_slide_px),
		Vector2(tuning.restore_end, 0.0),
	], &"in")
	var restore_pull := sin(IaidoTuning.span(t, tuning.restore_start, tuning.restore_end) * PI) * 8.0
	var fracture := _track(t, [
		Vector2(tuning.glass_start, 0.0),
		Vector2(tuning.glass_end, 1.0),
		Vector2(tuning.restore_start, 1.0),
		Vector2(tuning.restore_end, 0.0),
	], &"in")
	var shatter := _track(t, [
		Vector2(tuning.collapse_start, 0.0),
		Vector2(tuning.collapse_end, 1.0),
		Vector2(tuning.restore_end, 0.0),
	], &"in")
	var dissolve := IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.restore_start, tuning.restore_end))
	var flash := 0.0
	if t >= tuning.first_click:
		flash = tuning.ivory_flash_strength * (1.0 - IaidoTuning.span(t, tuning.first_click, tuning.first_click + tuning.ivory_flash_duration))

	iaido_fx.present({
		"resolution": viewport_size.max(Vector2.ONE),
		"cut_center": tuning.cut_center,
		"cut_angle": tuning.cut_angle_degrees,
		"time": float(Time.get_ticks_msec()) * 0.001,
		"focus": desaturation,
		"void_open": void_open,
		"gap_px": gap_px,
		"separation_px": separation_px,
		"depth_parallax": tuning.depth_parallax,
		"restore_pull": restore_pull,
		"slide_px": slide_px,
		"ivory_flash": flash,
		"void_life": tuning.void_life,
		"void_edge_color": tuning.void_edge_color,
		"void_mid_color": tuning.void_mid_color,
		"void_core_color": tuning.void_core_color,
		"void_core_width": tuning.void_core_width,
		"void_edge_width_px": tuning.void_edge_width_px,
		"fracture": fracture,
		"shatter": shatter,
		"dissolve": dissolve,
		"refract_px": tuning.refract_px,
		"rim_px": tuning.rim_px,
		"wave_strength": wave_strength,
		"wave_a": wave_a,
		"wave_b": wave_b,
		"wave_c": wave_c,
		"sheath_uv": anchor_uv,
	})

	# The weapon stays in the scene: a cold rim while the void is exposed.
	var exposure := _track(t, [
		Vector2(tuning.cut_start, 0.0),
		Vector2(tuning.cut_end, 0.85),
		Vector2(tuning.slow_sheathe_start, 0.85),
		Vector2(tuning.restore_start, 0.45),
		Vector2(tuning.restore_end, 0.0),
	], &"in_out")
	sword.set("void_exposure", exposure)


# --- sword -----------------------------------------------------------------

func _apply_weapon_pose(t: float) -> void:
	var sheath := tuning.sheath_position
	var sheath_rot := tuning.sheath_rotation
	var drawn := tuning.drawn_position
	var drawn_rot := tuning.drawn_rotation
	var p := initial_sword_position
	var r := initial_sword_rotation

	if t < tuning.sheath_start:
		# PHASE A: the arm does not move. Only the world changes.
		pass
	elif t < tuning.sheath_end:
		# PHASE B: steady travel, then a controlled deceleration at the mouth.
		var u := IaidoTuning.span(t, tuning.sheath_start, tuning.sheath_end)
		var k: float = (u / 0.6) * 0.74 if u < 0.6 else 0.74 + 0.26 * IaidoTuning.ease_out_cubic((u - 0.6) / 0.4)
		p = initial_sword_position.lerp(sheath, k)
		r = initial_sword_rotation.lerp(sheath_rot, k)
	elif t < tuning.draw_start:
		p = sheath
		r = sheath_rot
	elif t < tuning.draw_end:
		# PHASE F: three seconds of restraint released in 130ms.
		var k := IaidoTuning.ease_in_accel(IaidoTuning.span(t, tuning.draw_start, tuning.draw_end))
		p = sheath.lerp(drawn, k)
		r = sheath_rot.lerp(drawn_rot, k)
	elif t < tuning.spin_start:
		p = drawn
		r = drawn_rot
	elif t < tuning.spin_end:
		# PHASE K: two wrist revolutions, fast then medium. Not a screen spin.
		var first := IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.spin_start, tuning.spin_first_end))
		var second := IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.spin_first_end, tuning.spin_end))
		var turns := TAU * (first + second)
		p = drawn + Vector3(cos(turns) * 0.030, sin(turns) * 0.024 + 0.018, 0.0)
		r = drawn_rot + Vector3(sin(turns * 0.5) * 0.18, cos(turns * 0.5) * 0.10, -turns)
	elif t < tuning.slow_sheathe_end:
		# PHASE L: 1.0x -> 0.6x -> 0.3x. The last centimetres are the whole point.
		var u := IaidoTuning.span(t, tuning.slow_sheathe_start, tuning.slow_sheathe_end)
		var k: float
		if u < 0.50:
			k = IaidoTuning.ease_in_out(u / 0.50) * 0.62
		elif u < 0.80:
			k = 0.62 + IaidoTuning.ease_in_out((u - 0.50) / 0.30) * 0.28
		else:
			k = 0.90 + IaidoTuning.ease_out_quint((u - 0.80) / 0.20) * 0.10
		p = drawn.lerp(sheath, k)
		r = drawn_rot.lerp(sheath_rot, k)
	else:
		var settle := IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.restore_start, tuning.restore_end))
		p = sheath.lerp(sword.IDLE_POSITION, settle)
		r = sheath_rot.lerp(sword.IDLE_ROTATION, settle)

	sword.position = p
	sword.rotation = r
	sword.click_flash.visible = (
		(t >= tuning.first_click and t < tuning.first_click + 0.035)
		or (t >= tuning.final_click and t < tuning.final_click + 0.04)
	)


# --- events ----------------------------------------------------------------

func _fire_events() -> void:
	var t := elapsed
	if t >= tuning.damage_time and not events.has("impact"):
		events["impact"] = true
		_apply_impact()
	if t >= tuning.damage_time + 0.11:
		_clear_target_marks()
	if t >= tuning.cut_start and not events.has("cut"):
		events["cut"] = true
		camera_feedback.add_iaido_frame(Vector2(0.006, -0.010))
	if t >= tuning.final_click and not events.has("final"):
		events["final"] = true
		camera_feedback.add_iaido_frame(Vector2(0.010, -0.014))


func _apply_impact() -> void:
	for i in targets.size():
		var actor := targets[i]
		if not is_instance_valid(actor) or not actor.visible:
			continue
		var hurtbox := actor.get_node_or_null("Hurtbox") as CombatHurtbox
		if hurtbox == null:
			continue
		hurtbox.receive_hit({"damage": 65.0 if i == 0 else 39.0, "poise_damage": 70.0 if i == 0 else 42.0, "element": &"physical", "impulse": 0.0, "source": player})
		_add_target_mark(actor)
	camera_feedback.add_iaido_frame(Vector2(0.012, -0.020))


func _add_target_mark(actor: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.4, 0.018, 0.014)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(1.0, 0.96, 0.82)
	mesh.material = material
	var mark := MeshInstance3D.new()
	mark.mesh = mesh
	get_parent().add_child(mark)
	var angle := deg_to_rad(tuning.cut_angle_degrees)
	mark.global_transform = Transform3D(camera.global_basis, actor.global_position + Vector3.UP * 1.05)
	mark.rotation.z += -angle
	target_marks.append(mark)


func _clear_target_marks() -> void:
	for mark in target_marks:
		if is_instance_valid(mark):
			mark.queue_free()
	target_marks.clear()


# --- debug -----------------------------------------------------------------

func set_debug_hold(time: float) -> void:
	hold_time = time
	if not active:
		combat.iaido_ready_at = 0.0
		combat.request(&"iaido")
	if active:
		elapsed = time
		audio_timeline.seek(time)
		_process(0.0)


func release_debug_hold() -> void:
	hold_time = -1.0


func set_debug_speed(speed: float) -> void:
	playback_speed = clampf(speed, 0.25, 2.0)


# --- lifecycle / fail-safe --------------------------------------------------

func finish_iaido() -> void:
	if not active:
		_hard_reset()
		return
	active = false
	hold_time = -1.0
	_hard_reset()
	combat.finish_action()
	# Reality reconnect pulse: tiny, never a shake.
	camera_feedback.add_impulse(Vector2(0.0, 0.012))


func _hard_reset() -> void:
	tear.visible = false
	_clear_target_marks()
	iaido_fx.reset_iaido_fx()
	glass_layer.reset()
	audio_timeline.stop_all()
	audio_timeline.reset()
	screen_fx.reset()
	camera_feedback.fov_hold = 0.0
	camera_feedback.iaido_pitch = 0.0
	camera_feedback.iaido_frame = Vector2.ZERO
	camera_feedback.iaido_still = 0.0
	camera_feedback.iaido_frozen = false
	sword.set("void_exposure", 0.0)
	sword.click_flash.visible = false
	player.global_position = start_position
	player.velocity = Vector3.ZERO
	for node in previous_modes:
		if is_instance_valid(node):
			node.process_mode = previous_modes[node]
	previous_modes.clear()
	time_effects.reset()
	audio_state.restore_world_audio()
	pause_manager.release()


func _exit_tree() -> void:
	_clear_target_marks()
	if active:
		active = false
		_hard_reset()


# --- helpers ----------------------------------------------------------------

func _track(t: float, keys: Array[Vector2], ease: StringName = &"in_out") -> float:
	if keys.is_empty():
		return 0.0
	if t <= keys[0].x:
		return keys[0].y
	for i in range(1, keys.size()):
		if t <= keys[i].x:
			var a := keys[i - 1]
			var b := keys[i]
			var u := clampf((t - a.x) / maxf(b.x - a.x, 0.0001), 0.0, 1.0)
			match ease:
				&"out":
					u = IaidoTuning.ease_out_cubic(u)
				&"in":
					u = IaidoTuning.ease_in_cubic(u)
				&"linear":
					pass
				_:
					u = IaidoTuning.ease_in_out(u)
			return lerpf(a.y, b.y, u)
	return keys[keys.size() - 1].y
