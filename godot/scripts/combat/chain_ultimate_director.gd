extends Node3D
class_name ChainUltimateDirector
# 缚星链 · I / ULTIMATE — the whole nine-beat ceremony, in one file.
#
# ---------------------------------------------------------------------------
# WHAT THIS FILE IS
# ---------------------------------------------------------------------------
#
# It is a CONDUCTOR, not a system. The tuning resource owns every number; the
# sheet owns the membrane; `ChainVisual` owns the metal; the camera feedback
# controller owns the rig. This file decides WHAT HAPPENS WHEN and hands each of
# them the same `t`.
#
# There is no branch anywhere below on which skill this is, and no branch on the
# player's style. The ceremony is data (`ChainUltimateTuning`) plus one spine.
#
# ---------------------------------------------------------------------------
# THE SPINE: `_apply(t)` IS A PURE FUNCTION
# ---------------------------------------------------------------------------
#
# Frames are rendered from a shot list as often as they are played, and the
# lesson this project already paid for is that a director which ACCUMULATES
# cannot be scrubbed: a frame rendered at t=5.70 by being told it is 5.70 differs
# from frame 183 of a continuous take by tens of thousands of pixels, because the
# second one arrived there through everything before it.
#
# So the whole picture is derived from `t` alone:
#   · the anchor's position      from the camera's live transform
#   · the head's path            `ChainUltimateTuning.head_position(t, ...)`
#   · the head's VELOCITY        a finite difference of that same function, so it
#                                is a property of the path and not of the frame rate
#   · the sheet, the wound, the cuts, the tear, the heal   all from `evaluate(t)`
#
# The ONE stateful thing is `ChainVisual`'s own 1-frame head-lag filter, which is
# the chain's drawing talking about its own last frame. It costs nothing in a
# continuous take (which is how this is rendered) and is the only reason a
# jump-cut frame can differ at all.
#
# ---------------------------------------------------------------------------
# WHAT IT IS ALLOWED TO DO TO THE CAMERA
# ---------------------------------------------------------------------------
#
# Very little, on purpose. `fov_hold` (a generic field the feedback controller
# adds to its own fov) and the controller's own public `add_impulse` /
# `add_trauma`. Nothing here writes `motion_pivot`, `shake_pivot` or `camera.fov`
# directly: those belong to `CameraFeedbackController`, and a second writer is
# exactly the bug the iaido line already fixed once.
#
# ---------------------------------------------------------------------------
# NO SOUND PATHS IN THIS FILE
# ---------------------------------------------------------------------------
#
# The combat line's rule, and it holds here: this file emits EVENTS with names on
# them (`ultimate_event`) and never a `.wav`. `chain_ultimate_audio_timeline.gd`
# is the one place a file is named, and it is not part of the combat line.

signal ultimate_event(event: StringName, data: Dictionary)

# The brief's nine beats, in order, with the tuning fields they start at. Used by
# the debug strip and by the tests, so a beat cannot be renamed in one place and
# not the other.
const BEATS: Array = [
	["PHASE 0 · 起手", &"charge"],
	["PHASE 1 · 前刺", &"thrust"],
	["PHASE 2 · 命中锚点", &"bite"],
	["PHASE 3 · 绕两圈", &"coil"],
	["PHASE 4 · 扯膜", &"peel"],
	["PHASE 5 · 漂浮", &"float"],
	["PHASE 6 · 斩碎", &"cut"],
	["PHASE 7 · 漫画撕裂", &"tear"],
	["PHASE 8 · 恢复", &"restore"],
]

@export var tuning: ChainUltimateTuning

var active := false
var elapsed := 0.0
# -1 means "run on the frame clock". Anything else pins the ceremony to that
# time, which is how a deterministic renderer steps it.
var debug_hold := -1.0

# ---- resolved from the player ----------------------------------------------
var player: CharacterBody3D
var camera: Camera3D
var hand: Node3D
var chain: ChainDirector
var chain_visual: ChainVisual
var combat: CombatController
var camera_feedback: CameraFeedbackController
var screen_fx: CombatScreenFX

var sheet: ChainRealitySheet
var anchor_visual: MeshInstance3D
var anchor_material: ShaderMaterial

var targets: Array[Node3D] = []
var fired: Dictionary = {}
var damage_done := false
# The only state this director keeps that is not derivable from `t`: which of the
# chain's own behaviours it has taken over, so `finish()` can give them back
# exactly as it found them.
var _chain_manual_before := false
var _chain_visible_before := true
## Nodes the room asked to keep out of the captured photograph. See `configure`.
var _extra_hide: Array = []
# Whether this ceremony is the thing that owns the controller's state. The
# ceremony is a cutscene the player cannot act through, and the controller is the
# only thing that decides that — so the state is taken on `start` and given back
# on `_hard_reset`, and the flag is here so a reset that never took the state
# cannot hand `IDLE` to somebody else's state machine.
var _took_state := false


# ===========================================================================
# SETUP
# ===========================================================================

## Resolve everything by tree search from the player. Deliberately not `@onready`
## NodePaths: this director is built in code by whichever scene wants it, and a
## hard path would tie it to one scene's shape. The chain's own audio director
## already works this way.
## `extra_hide` is everything the room decided must not be printed on the film.
##
## IT EXISTS FOR THE ENEMY, AND THE ARGUMENT IS NOT ABOUT TIDINESS. The sheet is a
## picture of the WORLD — the surface the skill tears off. The enemy is not part of
## that surface; it is the thing standing IN the world, and the thing this skill is
## aimed at. Left in the capture it appears TWICE the moment the film pulls in: once
## as the photograph of itself travelling in with the picture, and once as itself,
## still standing where it was. Rendered, that doubling is unmistakable — the first
## version of this put a second cone floating inside the film's own picture, a
## metre from the real one.
##
## Taken out of the capture, the read becomes the one the design wants: the world
## comes off, and the enemy is left standing in the void holding the ground that is
## no longer there. It also means the enemy is visible for the WHOLE ceremony
## rather than blinking out at the rip, which is what a target has to do.
func configure(
	player_node: CharacterBody3D,
	next_tuning: ChainUltimateTuning = null,
	extra_hide: Array = []
) -> bool:
	var root := get_parent()
	player = player_node
	_extra_hide = extra_hide
	if player == null:
		push_error("ChainUltimateDirector: no player")
		return false
	if next_tuning != null:
		tuning = next_tuning
	if tuning == null:
		tuning = ChainUltimateTuning.new()

	camera = player.get_node_or_null(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	hand = player.get_node_or_null(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/ChainHandAnchor")
	chain = player.get_node_or_null("ChainDirector") as ChainDirector
	combat = player.get_node_or_null("CombatController") as CombatController
	camera_feedback = player.get_node_or_null("CameraFeedbackController") as CameraFeedbackController
	if camera == null or hand == null:
		push_error("ChainUltimateDirector: the player has no camera or no hand anchor")
		return false
	if chain != null:
		chain_visual = chain.chain_visual
	if root != null:
		screen_fx = root.get_node_or_null("CombatScreenFX") as CombatScreenFX

	_build_anchor()
	return true


func ready() -> bool:
	return camera != null and hand != null and tuning != null


## The anchor: a rule-generated point in front of the aim, not a physical object.
## It is NOT raycast onto anything — the brief's §五.2 is explicit that the skill
## does not need to hit real geometry, and the whole point is that the RULE
## establishes the point.
func anchor_point() -> Vector3:
	var b := camera.global_transform.basis
	var fwd := -b.z.normalized()
	var up := b.y.normalized()
	return camera.global_position + fwd * tuning.anchor_distance + up * tuning.anchor_rise


func sheet_center() -> Vector3:
	return tuning.sheet_center_at(elapsed, anchor_point(), camera.global_transform.basis)


func _build_anchor() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = tuning.anchor_radius
	mesh.height = tuning.anchor_radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	anchor_material = ShaderMaterial.new()
	anchor_material.shader = preload("res://vfx/chain_void_anchor.gdshader")
	anchor_material.render_priority = 0
	anchor_visual = MeshInstance3D.new()
	anchor_visual.name = "VoidAnchor"
	anchor_visual.mesh = mesh
	anchor_visual.material_override = anchor_material
	anchor_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anchor_visual.visible = false
	add_child(anchor_visual)

	sheet = ChainRealitySheet.new()
	sheet.name = "RealitySheet"
	sheet.visible = false
	add_child(sheet)


# ===========================================================================
# LIFECYCLE
# ===========================================================================

func start() -> bool:
	if active or not ready():
		return false
	active = true
	elapsed = 0.0
	fired.clear()
	damage_done = false
	targets.clear()
	if combat != null:
		combat.reset_skill_cooldowns()
		# THE PLAYER CANNOT ACT THROUGH THIS. `State.ULTIMATE` is the controller's
		# own "a ceremony owns me" state — the same one 无明一刻 uses — and it is
		# the difference between a nine-beat sequence and a nine-beat sequence the
		# player is swinging a sword through.
		combat.set_state(CombatController.State.ULTIMATE)
		_took_state = true
	# ---- TAKE THE CHAIN OVER --------------------------------------------
	# `manual_step` is the chain director's own "someone else is driving" switch,
	# so this needs no edit to a file another line is working in, and the chain's
	# state machine cannot fight this ceremony for the head.
	if chain != null:
		_chain_manual_before = chain.manual_step
		chain.manual_step = true
		chain.release_heavy()
	if chain_visual != null:
		_chain_visible_before = chain_visual.is_drawn()
		chain_visual.set_chain_visible(true)
		chain_visual.bite_time = tuning.bite_time
	if screen_fx != null:
		screen_fx.reset()
	_emit(&"charge", {})
	return true


func set_debug_hold(t: float) -> void:
	debug_hold = maxf(t, 0.0)
	# A held frame still has to be APPLIED, or nothing moves at all.
	if active:
		_apply(debug_hold, 1.0 / 30.0)


## The ceremony's own clock, whichever clock is currently authoritative. During a
## deterministic render `debug_hold` is the time the picture is pinned to and
## `elapsed` is standing still, so anything that rides the ceremony — the audio
## timeline, a HUD — has to ask HERE rather than read `elapsed` and silently stop
## at 0.00s for the whole take.
func now() -> float:
	return debug_hold if debug_hold >= 0.0 else elapsed


func release_debug_hold() -> void:
	debug_hold = -1.0


func _process(delta: float) -> void:
	if not active or not ready():
		return
	if debug_hold >= 0.0:
		_apply(debug_hold, delta)
		return
	elapsed += delta
	_apply(elapsed, delta)
	if elapsed >= tuning.t_end:
		finish()


func finish() -> void:
	if not active:
		_hard_reset()
		return
	active = false
	_hard_reset()
	if combat != null:
		combat.ultimate_ready_at = Time.get_ticks_msec() / 1000.0 + tuning.cooldown
		combat.notify_ultimate_finished()
	_emit(&"finished", {})


func _hard_reset() -> void:
	if sheet != null and sheet.built:
		sheet.teardown()
	if sheet != null:
		sheet.visible = false
	if anchor_visual != null:
		anchor_visual.visible = false
	if chain != null:
		chain.manual_step = _chain_manual_before
		chain.reset()
	if chain_visual != null:
		chain_visual.set_chain_visible(_chain_visible_before)
	if screen_fx != null:
		screen_fx.reset()
	if camera_feedback != null:
		camera_feedback.fov_hold = 0.0
	if _took_state and combat != null and combat.state == CombatController.State.ULTIMATE:
		combat.set_state(CombatController.State.IDLE)
	_took_state = false
	targets.clear()
	elapsed = 0.0


func _exit_tree() -> void:
	_hard_reset()


# ===========================================================================
# THE ONE FRAME FUNCTION
# ===========================================================================

func _apply(t: float, delta: float) -> void:
	var state := tuning.evaluate(t)
	var cam_xform := camera.global_transform
	var basis := cam_xform.basis
	var anchor := anchor_point()
	var hand_pos := hand.global_position
	var head := tuning.head_position(t, hand_pos, anchor, basis)

	_drive_chain(t, state, hand_pos, head, anchor, basis, delta)
	_drive_anchor(t, state)
	_drive_sheet(t, state, basis, anchor, delta)
	_drive_camera(t)
	_fire(t, state)
	if t >= tuning.t_restore_start:
		_apply_damage(state)


func beat_at(t: float) -> int:
	var marks := [
		tuning.t_thrust_start, tuning.t_bite, tuning.t_coil_start, tuning.t_pull_start,
		tuning.t_float_start, tuning.t_cut_start, tuning.t_tear_start, tuning.t_restore_start,
	]
	var index := 0
	for i in marks.size():
		if t >= float(marks[i]):
			index = i + 1
	return index


func phase_name(t: float) -> String:
	return String(BEATS[beat_at(t)][0])


# ---------------------------------------------------------------- the chain

## Hand the chain a world position and a tension. The trident's own lag, bow and
## trail are `ChainVisual`'s business and are not touched from here.
func _drive_chain(
	t: float, _state: Dictionary, hand_pos: Vector3, head: Vector3,
	anchor: Vector3, basis: Basis, delta: float
) -> void:
	if chain_visual == null:
		return
	if t < tuning.t_thrust_start:
		# 起手. Nothing has been thrown. The chain is in the fist and the ceremony
		# has not started, which is why this is HELD and not a small SWING.
		chain_visual.set_rig(ChainVisual.Rig.HELD)
		chain_visual.set_chain_visible(t > 0.05)
		chain_visual.update_chain(hand_pos, hand_pos - basis.z * 0.2, Vector3.ZERO, 0.0, delta)
		return
	chain_visual.set_chain_visible(true)
	chain_visual.set_rig(ChainVisual.Rig.SWING)
	# THE VELOCITY IS A FINITE DIFFERENCE OF THE PATH, not a measurement of the
	# frame. Reading the last frame's position would make the trail a function of
	# the frame rate, and a re-render at a different step would draw a different
	# chain.
	var h := 1.0 / 120.0
	var ahead := tuning.head_position(t + h, hand_pos, anchor, basis)
	var velocity := (ahead - head) / h
	chain_visual.update_chain(hand_pos, head, velocity, _tension_at(t), delta)


## How taut the rope is. Read off the phase rather than computed from the
## distance, because the distance is authored and a solver would only ever
## re-derive the number that was typed here.
func _tension_at(t: float) -> float:
	if t < tuning.t_bite:
		# Still paying out. A rope that is already tight on the way out has nothing
		# left to tighten when it bites.
		return 0.22 + 0.28 * ChainUltimateTuning.span(t, tuning.t_thrust_start, tuning.t_bite)
	if t < tuning.t_coil_start:
		return 0.55
	if t < tuning.t_pull_start:
		# THE TWO TURNS. 0.72 -> 1.0, so the second turn is the one at the limit.
		var u := float(tuning.evaluate(t)["coil_u"])
		return 0.72 + 0.28 * u
	if t < tuning.t_tear_start:
		# Held at full load through the haul and the cutting: the whole point of
		# the coil was to have something to load.
		return 1.0
	# After the tear the load is gone, because the thing it was holding is gone.
	return clampf(1.0 - ChainUltimateTuning.span(t, tuning.t_tear_start, tuning.t_end) * 1.4, 0.0, 1.0)


# ---------------------------------------------------------------- the anchor

func _drive_anchor(t: float, state: Dictionary) -> void:
	if anchor_visual == null or anchor_material == null:
		return
	var visible_from := tuning.t_bite - 0.03
	anchor_visual.visible = t >= visible_from and t < tuning.t_restore_start + 0.25
	if not anchor_visual.visible:
		return
	anchor_visual.global_position = anchor_point()
	# FORM: the core does not fade in, it SNAPS into being the instant the tip is
	# through it. 80ms, and it is an ease-out so most of it is in the first three
	# frames — a core that grows is a core that was always on its way.
	var form := ChainUltimateTuning.ease_out_cubic(
		ChainUltimateTuning.span(t, visible_from, visible_from + 0.08))
	anchor_material.set_shader_parameter("form", form)
	anchor_material.set_shader_parameter("clock", t)
	anchor_material.set_shader_parameter("implode", tuning.anchor_implode)
	anchor_material.set_shader_parameter(
		"pierce", ChainUltimateTuning.decay(t, tuning.t_bite, 9.0))
	# It goes out with the world, not with a fade: by the restore its job is done
	# and the sheet is what is being looked at.
	anchor_material.set_shader_parameter(
		"form",
		form * clampf(1.0 - ChainUltimateTuning.span(
			t, tuning.t_tear_start + 0.10, tuning.t_tear_start + 0.45), 0.0, 1.0))


# ----------------------------------------------------------------- the sheet

func _drive_sheet(t: float, state: Dictionary, basis: Basis, anchor: Vector3, _delta: float) -> void:
	if sheet == null or not sheet.built:
		if t >= tuning.t_pull_start and sheet != null and not sheet.built:
			# THE RIP. The capture is taken here, on its own frames, with the
			# anchor, the chain and the room's own exclusions hidden — the sheet
			# is a picture of the world BEFORE the rip, and the anchor is a thing
			# the rip added while the enemy is a thing the rip is aimed AT.
			sheet.tuning = tuning
			var hide: Array = [anchor_visual]
			if chain_visual != null:
				hide.append(chain_visual)
			hide.append_array(_extra_hide)
			sheet.visible = true
			if not sheet.arm(camera, tuning, hide, _rip_fov(t)):
				sheet.visible = false
		return
	sheet.step_capture()
	if sheet.frozen():
		sheet.apply(state, basis, tuning.sheet_center_at(t, anchor, basis))


# ------------------------------------------------------------------ camera

## The fov the camera WILL be drawn with at `t`.
##
## The capture is a photograph taken through the player's camera, and the film's
## UVs are baked from that projection — so the photograph has to be taken through
## the camera the frame is DRAWN with, not through the value `camera.fov` happens
## to hold at this instant in the director. Those are not the same number: the
## ceremony's fov is composed by the feedback controller one `_process` later, so
## at the rip `camera.fov` still reads the base 75.0 while the frame is drawn at
## 70.0. Taking the picture at 75 puts the film's content 9% off the world it
## claims to be — `capture_fov` on the sheet is what makes that visible, and §6 of
## `tests/chain_ultimate_integration.gd` is what makes it fail loudly.
func _rip_fov(t: float) -> float:
	if camera_feedback == null:
		return camera.fov
	return tuning.camera_fov_at(t, camera_feedback.base_fov)


func _drive_camera(t: float) -> void:
	if camera_feedback == null:
		return
	# The whole curve lives on the tuning now, because the CAPTURE needs the same
	# answer for the same time and `camera.fov` cannot supply it — see
	# `camera_fov_at` and `_rip_fov`.
	camera_feedback.fov_hold = tuning.camera_fov_at(t, 0.0)


# ------------------------------------------------------------------ events

## One place. Every event fires on a threshold crossing exactly once, which is
## also what makes the camera impulses and the damage land on the frame the beat
## happens rather than on the frame after it.
func _fire(t: float, state: Dictionary) -> void:
	if not fired.has(&"bite") and t >= tuning.t_bite:
		fired[&"bite"] = true
		_impulse(Vector2(0.35, -0.72), tuning.impulse_bite, 0.09)
		if screen_fx != null:
			screen_fx.flash_hit(0.07)
		_emit(&"bite", {})
	if not fired.has(&"coil_end") and t >= tuning.t_pull_start:
		fired[&"coil_end"] = true
		_impulse(Vector2(-0.62, -0.58), tuning.impulse_pull, 0.14)
		_emit(&"pull", {})
	if not fired.has(&"peel_end") and t >= tuning.t_float_start:
		fired[&"peel_end"] = true
		_emit(&"float", {})
	# ---- THE CUTS --------------------------------------------------------
	for i in tuning.cuts.size():
		var key := StringName("cut_%d" % i)
		if fired.has(key) or t < tuning.cut_time(i):
			continue
		fired[key] = true
		# Each stroke nudges the camera a hair, and the LAST one does not: the
		# tear is a tenth of a second behind it and two impulses that close
		# together read as one nervous shake instead of two events.
		if i < tuning.cuts.size() - 1:
			var dir := Vector2(0.45, 0.62) if i % 2 == 0 else Vector2(-0.48, 0.55)
			_impulse(dir.normalized(), tuning.impulse_cut, 0.07)
		if i == 0 and screen_fx != null:
			screen_fx.flash_hit(0.04)
		_emit(&"cut", {"index": i, "of": tuning.cuts.size()})
	if not fired.has(&"tear") and t >= tuning.t_tear_start:
		fired[&"tear"] = true
		_impulse(Vector2(0.30, -0.86), tuning.impulse_tear, 0.22)
		if screen_fx != null:
			screen_fx.flash_hit(0.20)
			screen_fx.ink_slash = 0.55
		_emit(&"tear", {"shards": tuning.shard_count})
	if not fired.has(&"restore") and t >= tuning.t_restore_start:
		fired[&"restore"] = true
		_emit(&"restore", {})
	# ---- THE TWO CONTINUOUS GRADES ---------------------------------------
	if screen_fx != null:
		# Space is being DRAGGED through the haul, and that is what the distortion
		# channel is for. It is wound back to zero by the time the sheet is free,
		# so the pull reads as the cause of the sheet and not as a filter.
		var drag := ChainUltimateTuning.ease_in_out(
			ChainUltimateTuning.span(t, tuning.t_pull_start, tuning.t_float_start))
		screen_fx.set_distortion(drag * 0.34)
		# A shallow drain, only across the tear, and never more than a fifth: this
		# skill's climax is a bright one and the last pass of the iaido line exists
		# precisely because eating the picture at the climax is the wrong instinct.
		var drain := ChainUltimateTuning.span(t, tuning.t_tear_start, tuning.t_tear_start + 0.12)
		drain *= 1.0 - ChainUltimateTuning.span(t, tuning.t_restore_start, tuning.t_end)
		screen_fx.set_world_drain(drain * 0.18)


func _impulse(direction: Vector2, strength: float, trauma: float) -> void:
	if camera_feedback == null:
		return
	camera_feedback.add_impulse(direction.normalized() * strength)
	camera_feedback.add_trauma(trauma)


func _emit(event: StringName, data: Dictionary) -> void:
	ultimate_event.emit(event, data)


# ----------------------------------------------------------------- the payoff

## The brief asks for a single target and for the anchor not to have to land on
## anything. So the damage is dealt to whatever is standing where the sheet WAS —
## which is the honest version of "the world came off in your hands".
##
## EVERYTHING within `hit_radius` of the WOUND takes it, once, at the tear.
func _apply_damage(_state: Dictionary) -> void:
	if damage_done:
		return
	damage_done = true
	var centre := tuning.sheet_center_at(
		tuning.t_tear_start, anchor_point(), camera.global_transform.basis)
	var radius := tuning.hit_radius
	for node in get_tree().get_nodes_in_group("hostiles"):
		var actor := node as Node3D
		if actor == null or not is_instance_valid(actor):
			continue
		var health: Variant = actor.get("health")
		if health != null and float(health) <= 0.0:
			continue
		if actor.global_position.distance_to(centre) > radius:
			continue
		targets.append(actor)
		var hurtbox := actor.get_node_or_null("Hurtbox") as CombatHurtbox
		if hurtbox == null:
			continue
		hurtbox.receive_hit({
			"damage": tuning.damage,
			"poise_damage": tuning.poise_damage,
			"element": &"physical",
			# NO IMPULSE. The brief is explicit: 不爆炸、不弹飞. What kills them is
			# the world going out from under them, not a shockwave.
			"impulse": 0.0,
			"source": player,
			"target": actor,
			"interrupt": true,
		})
	if not targets.is_empty():
		_emit(&"hit", {"count": targets.size()})
