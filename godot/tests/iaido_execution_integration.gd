extends SceneTree

# 聚合斩 · IAIDO EXECUTION integration check.
#
# The ceremony itself is already guarded by `iaido_integration.gd`. This suite is
# about the thing that happens to the BODY: §C's "already cut, but the result
# arrived a moment late", and the eight tests §S of the execution brief asks for.
#
# THE HARD PART IS THE CLOCK. A real-time run of the ceremony is ten seconds of
# wall time per attempt, and the beat under test is 0.45s of it. So almost
# everything here is run on the director's own scrub (`set_debug_hold`), which
# jumps the ceremony to an exact instant and processes one frame there — the same
# mechanism the reviewer's screenshot tool uses, and the reason `IaidoExecution`
# is written as a pure function of `t` in the first place. One full real-time run
# is kept, at the end, because a suite that only ever scrubs never proves the
# ceremony actually gets there on its own.
#
# NOTHING HERE IS STATICALLY TYPED AGAINST `CombatTuning` OR `IaidoTuning` — see
# `sekai-headless-verify` §1.4. The tuning resource is read dynamically, and the
# enemy is asked what it thinks rather than told.

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var iaido: IaidoDirector
var camera: Camera3D
var tuning: Resource
var attacks: Array[int] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	dummy = world.get_node("TechnicalDummy")
	combat = player.get_node("CombatController")
	iaido = world.get_node("IaidoDirector")
	camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
	tuning = iaido.tuning
	player.global_position = Vector3(0.0, 1.15, 0.0)
	dummy.connect("attack_started", func(variant: int) -> void: attacks.append(variant))
	await physics_frame
	await physics_frame

	_verify_the_material_table()
	_verify_the_timeline_and_its_budget()
	_verify_the_plane_is_the_line_the_world_draws()
	_verify_mode_resolution()
	await _verify_hold_then_release()
	await _verify_a_non_lethal_cut_does_not_split()
	await _verify_a_held_body_cannot_act()
	await _verify_an_ordinary_kill_never_executes()
	await _verify_authored_split_meshes()
	await _verify_multi_kill()
	await _verify_every_way_out_of_the_ceremony_resolves()
	await _verify_full_run_in_real_time()

	if failures.is_empty():
		print("PASS: Iaido execution · one plane drives the world cut and the cross-section, a lethal cut holds the body, the sheath click lets it fall, and no path leaves it standing")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


# =============================================================================
# helpers
# =============================================================================

## Everything back to a known state: the body alive, no leftover ceremony, the
## debug lethality switch off.
func _prepare() -> void:
	if iaido.active:
		iaido.release_debug_hold()
		iaido.finish_iaido()
	iaido.set_debug_lethality(0)
	dummy.set("execution_profile", null)
	dummy.set("max_health", 120.0)
	dummy.call("reset_dummy")
	combat.iaido_ready_at = 0.0
	player.set("stamina", 100.0)
	player.set("health", 100.0)
	player.global_position = Vector3(0.0, 1.15, 0.0)
	attacks.clear()


## Jump the ceremony to an exact instant and process one frame there.
func _hold(t: float) -> void:
	iaido.set_debug_hold(t)
	iaido._process(0.0)


func _at(name: String) -> float:
	return float(tuning.get(name))


func _execution() -> IaidoExecution:
	if iaido.executions.is_empty():
		return null
	return iaido.executions[0]


func _execution_nodes() -> int:
	var count := 0
	for child in world.get_children():
		if child is IaidoExecution:
			count += 1
	return count


func _damage_time() -> float:
	return _at("damage_time")


# =============================================================================
# 1 · the data layer: one rule, a different face per material
# =============================================================================

func _verify_the_material_table() -> void:
	var families := [
		IaidoExecutionProfile.MATERIAL_CONSTRUCT,
		IaidoExecutionProfile.MATERIAL_BIOLOGICAL,
		IaidoExecutionProfile.MATERIAL_ICE,
		IaidoExecutionProfile.MATERIAL_PLANT,
	]
	var interiors: Array[Color] = []
	for family in families:
		var profile := IaidoExecutionLibrary.construct()
		profile.cut_material = family
		IaidoExecutionLibrary.apply_material(profile)
		var surface: Dictionary = IaidoExecutionLibrary.surface(family)
		_check(
			profile.interior_color.is_equal_approx(surface["interior_color"]),
			"profile.cut_material %s did not take its cross-section from the table" % family
		)
		interiors.append(profile.interior_color)
		# §L · NO GORE BY DEFAULT. A cross-section that is bright, or that leans
		# red, has chosen an art direction the design explicitly did not.
		var brightest := maxf(profile.interior_color.r, maxf(profile.interior_color.g, profile.interior_color.b))
		var others := maxf(profile.interior_color.g, profile.interior_color.b)
		_check(brightest <= 0.55, "the %s cross-section is bright (%.2f) — it will read as a painted panel" % [family, brightest])
		_check(profile.interior_color.r <= others + 0.10, "the %s cross-section is red-dominant" % family)
	# ...and the families must be distinguishable, or the table is decoration.
	for i in interiors.size():
		for j in range(i + 1, interiors.size()):
			_check(
				not interiors[i].is_equal_approx(interiors[j]),
				"two material families share a cross-section colour (%s / %s)"
					% [families[i], families[j]]
			)
	# A preset is handed out as a COPY. The .tres is shared, and a debug button
	# that mutated it would retune every construct in the game from a panel press.
	var edited := IaidoExecutionLibrary.construct()
	edited.hold_separation_m = 9.0
	var fresh := IaidoExecutionLibrary.construct()
	_check(
		absf(fresh.hold_separation_m - 0.022) < 0.0001,
		"presets share one live Resource — editing one enemy's profile would edit every enemy's"
	)
	# The quiet rest of the construct family: a body with no light inside it must
	# not be given one.
	var biological := IaidoExecutionLibrary.biological()
	_check(
		biological.core_emission == 0.0,
		"the biological cross-section carries core emission — realistic gore by another name"
	)


# =============================================================================
# 2 · the timeline, and the window the fall has to fit inside
# =============================================================================

func _verify_the_timeline_and_its_budget() -> void:
	var damage_time := _damage_time()
	var cut_start := _at("cut_start")
	var final_click := _at("final_click")
	var devour_start := _at("devour_start")
	var restore_start := _at("restore_start")
	# The cut lands WHEN THE WORLD REACTS, not when the blade leaves — the enemy
	# and the world have to be cut by the same event.
	_check(absf(damage_time - cut_start) < 0.001, "the body is cut at %.2fs but the world is cut at %.2fs" % [damage_time, cut_start])
	# §C · the hold. 刀先过去 → 世界晚一拍承认 → 怪物再晚一拍失去完整性.
	_check(
		final_click - damage_time >= 3.0,
		"the body is only held for %.2fs — §C's whole idea needs it standing for most of the ceremony"
			% (final_click - damage_time)
	)
	# §R BEAT 3 · the click is the signature window: world collapse, enemy release
	# and audio, allowed to be one to three frames apart and no further.
	var frames := absf(final_click - devour_start) * 30.0
	_check(
		frames <= 3.0 + 0.01,
		"the enemy is released %.1f frames away from the world's collapse — §R asks for the same signature window"
			% frames
	)
	for id in IaidoExecutionLibrary.PRESETS.keys():
		var profile := IaidoExecutionLibrary.preset(id)
		# Trace, then the creep, then nothing — all of it inside the hold.
		_check(
			profile.trace_delay + profile.trace_fade <= profile.align_start + 0.001,
			"%s: the 1-3cm misalignment starts before the hairline is legible" % id
		)
		_check(
			damage_time + profile.align_end <= final_click,
			"%s: the misalignment is still creeping when the click lands" % id
		)
		_check(
			profile.align_end - damage_time <= 0.75,
			"%s: §C asks for the 1-3cm misalignment by T0+600ms, it takes %.0fms"
				% [id, (profile.align_end - damage_time) * 1000.0]
		)
		_check(
			profile.hold_separation_m >= 0.010 and profile.hold_separation_m <= 0.030,
			"%s: the held misalignment is %.3fm — §C asks for 1-3cm" % [id, profile.hold_separation_m]
		)
		# §K · loss of support, not a cannon.
		_check(
			profile.release_force <= 0.60,
			"%s: the halves are launched at %.2f m/s — that is shrapnel, not structural failure"
				% [id, profile.release_force]
		)
		# THE BUDGET. Reality starts coming back at `restore_start`, and a body
		# still coming apart at that instant is two effects sharing a frame.
		var widest := final_click + 0.08 + profile.fall_duration + profile.fade_duration
		_check(
			widest <= restore_start + 0.001,
			"%s: still coming apart at %.2fs, after reality starts reconnecting at %.2fs"
				% [id, widest, restore_start]
		)
	# The damage has to be a KILL for a standard body, or the whole system is
	# unreachable in play — see the note on `execution_damage`.
	_check(
		_at("execution_damage") >= 120.0 and _at("execution_damage_splash") >= 120.0,
		"the signature cannot kill a standard enemy, so no execution can ever happen"
	)


# =============================================================================
# 3 · one authoritative plane, and it is the line the world draws
# =============================================================================

func _verify_the_plane_is_the_line_the_world_draws() -> void:
	var angle := float(tuning.get("cut_angle_degrees"))
	var centre: Vector2 = tuning.get("cut_center")
	var plane := IaidoCutPlane.from_camera(camera, centre, angle)
	_check(plane.is_valid(), "the cut plane came out degenerate")
	# It passes through the eye, because the line it came from is a screen line.
	_check(
		absf(plane.signed_distance(camera.global_position)) < 0.001,
		"the cut plane does not contain the camera, so it is not the screen line's preimage"
	)
	var size := camera.get_viewport().get_visible_rect().size
	var dir := Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle)))
	# Points ON the line are on the plane...
	for along in [-0.32, -0.05, 0.28]:
		var point := camera.project_position((centre + dir * along) * size, 6.0)
		_check(
			absf(plane.signed_distance(point)) < 0.004,
			"a world point whose projection is on the cut line is %.4fm off the plane" % absf(plane.signed_distance(point))
		)
	# ...and a point off the line is off the plane, on the sign the uv normal
	# points at. This is the assertion that fails if the convention is mirrored —
	# and a mirrored convention mirrors every cross-section in the game.
	var normal_uv := Vector2(-dir.y, dir.x)
	var off := camera.project_position((centre + normal_uv * 0.14) * size, 6.0)
	_check(
		plane.signed_distance(off) > 0.05,
		"the plane's positive side is the wrong screen side (signed distance %.4f)" % plane.signed_distance(off)
	)
	# THE ONE THAT MATTERS: re-project the plane and compare with the line the
	# world shader is drawing this frame. If these two disagree the world is cut
	# diagonally and the enemy is cut at the waist, which is exactly the fault
	# §B §2 names.
	var line: Dictionary = plane.screen_line(camera)
	var delta: Vector2 = (line["point"] as Vector2) - centre
	var line_dir := Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle)))
	var pixels := absf(line_dir.cross(delta)) * size.y
	_check(pixels < 2.0, "the plane's screen line is %.1fpx away from the shader's line" % pixels)
	var reported := float(line["angle"])
	var mismatch := fposmod(reported - angle, 180.0)
	mismatch = minf(mismatch, 180.0 - mismatch)
	_check(mismatch < 0.5, "the plane's screen line runs at %.2f° against the shader's %.2f°" % [reported, angle])
	# And it is FROZEN: the camera takes three impulses across the ceremony, and a
	# plane that moved with them would stop describing the slash on screen.
	var frozen := IaidoCutPlane.from_camera(camera, centre, angle)
	_check(
		(absf(frozen.offset - plane.offset) < 0.0001 and frozen.normal.is_equal_approx(plane.normal)),
		"the plane is not reproducible from the same camera state"
	)


# =============================================================================
# 4 · what each body decides
# =============================================================================

func _verify_mode_resolution() -> void:
	var cleave := IaidoExecutionLibrary.construct()
	_check(cleave.execution_type == IaidoExecutionProfile.TYPE_CLEAVE, "a construct is not authored to be cleaved")
	# A body WITH geometry gets the real two-part cleave, and it must — if missing
	# authored split meshes downgraded it to the placeholder, then the placeholder
	# would be the only path that ever runs, because ART has authored none yet.
	_check(
		cleave.resolve_mode(true) == IaidoExecutionProfile.TYPE_CLEAVE,
		"a cuttable body was sent to the fallback instead of being cleaved"
	)
	_check(
		cleave.resolve_mode(false) == cleave.fallback_execution,
		"a body with nothing to cut did not take its fallback"
	)
	var unsupported := IaidoExecutionLibrary.none()
	_check(
		unsupported.resolve_mode(true) == IaidoExecutionProfile.TYPE_NONE,
		"a body whose contract says no was answered with something else"
	)
	var boss := IaidoExecutionLibrary.boss()
	_check(boss.resolve_mode(true) == IaidoExecutionProfile.TYPE_SPECIAL, "the boss response was not used")
	_check(
		boss.resolve_mode(false) == IaidoExecutionProfile.TYPE_SPECIAL,
		"the boss fell back to a generic look — §G says the final blow must always change the death"
	)


# =============================================================================
# 5 · THE BEAT: held, then released on the click
# =============================================================================

func _verify_hold_then_release() -> void:
	_prepare()
	var damage_time := _damage_time()
	var final_click := _at("final_click")
	var restore_start := _at("restore_start")

	# ---- BEFORE THE BLADE --------------------------------------------------
	_hold(damage_time - 0.06)
	_check(_execution() == null, "a body was taken over before the blade had landed")
	_check(dummy.visible, "the body was hidden before it was cut")

	# ---- T0 · THE CUT -----------------------------------------------------
	_hold(damage_time)
	var execution := _execution()
	_check(execution != null, "a lethal signature did not enter the execution hold")
	if execution == null:
		return
	# ⚠ EVERY one of these is the §O contract: settled at the cut, visually held.
	_check(dummy.health <= 0.0, "the signature did not settle the damage at the cut (health %.1f)" % dummy.health)
	_check(not bool(dummy.call("is_alive")), "a held body still reports itself alive — anything reading this would let it act")
	_check(bool(dummy.call("expects_iaido_execution")), "the enemy did not flag the death for the director")
	_check(not dummy.visible, "the body was not handed to the execution")
	_check(
		not bool(dummy.get_node("AttackHitbox").get("active")),
		"a held body kept its hitbox armed"
	)
	_check(
		not (dummy.get_node("Hurtbox") as Area3D).monitorable,
		"a held body is still a valid target"
	)
	_check(execution.mode == IaidoExecutionProfile.TYPE_CLEAVE, "the body resolved to mode %s" % execution.mode)
	_check(
		absf(execution.release_at - (final_click + 0.02)) < 0.0001,
		"the release is at %.3fs, not on the sheath click (%.2fs + the first target's 20ms)"
			% [execution.release_at, final_click]
	)
	# 0-100ms: NOTHING LOOKS CUT. The two halves are exactly where the body was.
	_check(
		execution.separation() < 0.0005,
		"the body was already visibly split at the instant of the cut (%.4fm)" % execution.separation()
	)
	var material := _first_material(execution)
	_check(material != null, "the execution built no cut surface at all")
	if material == null:
		return
	_check(
		float(material.get_shader_parameter("trace")) < 0.001,
		"the cut line was already drawn at the instant of the cut — §C asks for 100ms of nothing"
	)

	# ---- T0+100-220ms · THE TRACE ------------------------------------------
	_hold(damage_time + 0.24)
	_check(
		float(material.get_shader_parameter("trace")) > 0.95,
		"the hairline never became legible (trace %.2f)" % float(material.get_shader_parameter("trace"))
	)

	# ---- T0+220-600ms · THE 1-3cm MISALIGNMENT -----------------------------
	_hold(damage_time + 0.36)
	var creeping := execution.separation()
	_hold(damage_time + 0.64)
	var settled := execution.separation()
	_check(
		creeping > 0.0005 and creeping < settled - 0.0005,
		"the misalignment does not creep in across T0+220-600ms (%.4f -> %.4f)" % [creeping, settled]
	)
	_check(
		absf(settled - execution.profile.hold_separation_m) < 0.002,
		"the held misalignment is %.4fm, not the profile's %.4fm"
			% [settled, execution.profile.hold_separation_m]
	)
	_check(
		settled >= 0.010 and settled <= 0.030,
		"§C asks for 1-3cm of misalignment, measured %.4fm" % settled
	)

	# ---- THE HOLD · 它还没有真正倒 -----------------------------------------
	var anchor_y := execution.cut_anchor.y
	_hold(final_click - 0.05)
	_check(
		absf(execution.separation() - settled) < 0.001,
		"the body kept moving through the hold — it is supposed to be a still of a dead thing"
	)
	for i in execution.piece_count():
		_check(
			absf(execution.piece_position(i).y - anchor_y) < 0.02,
			"piece %d drifted vertically during the hold — nothing may fall before the click" % i
		)

	# ---- THE CLICK · 分开 --------------------------------------------------
	_hold(final_click + 0.22)
	var released := execution.separation()
	_check(
		released > settled + 0.004,
		"the halves did not come apart after the click (%.4f -> %.4f)" % [settled, released]
	)
	for i in execution.piece_count():
		_check(
			execution.piece_position(i).y < anchor_y - 0.01,
			"piece %d never lost its argument with gravity (y %.3f, anchor %.3f)"
				% [i, execution.piece_position(i).y, anchor_y]
		)
	# §K §11 · the two halves do not fall in lockstep. Perfect symmetry is what
	# the eye reads as "digital", and this is the cheapest cure in the whole beat.
	_hold(final_click + 0.44)
	var drop_a := anchor_y - execution.piece_position(0).y
	var drop_b := anchor_y - execution.piece_position(1).y
	_check(
		absf(drop_a - drop_b) > 0.008,
		"the two halves fall in lockstep (%.3fm vs %.3fm) — the asymmetry is missing"
			% [drop_a, drop_b]
	)

	# ---- BEFORE REALITY COMES BACK -----------------------------------------
	_check(
		execution.visual_end() <= restore_start + 0.001,
		"the body is still coming apart at %.2fs, after reality starts reconnecting" % execution.visual_end()
	)
	_hold(restore_start - 0.02)
	_check(
		float(material.get_shader_parameter("dissolve")) >= 0.999,
		"the pieces are still solid when reality returns (dissolve %.3f)"
			% float(material.get_shader_parameter("dissolve"))
	)
	# §L · the cross-section is a material, not a colour: it has to be the one the
	# body's own family asked for.
	_check(
		(material.get_shader_parameter("interior_color") as Color).is_equal_approx(execution.profile.interior_color),
		"the cross-section material is not the one the profile asked for"
	)

	# ---- AND THEN THE CEREMONY ENDS ----------------------------------------
	iaido.finish_iaido()
	await physics_frame
	_check(_execution() == null, "the execution outlived the ceremony")
	_check(_execution_nodes() == 0, "an IaidoExecution node was left in the world")
	_check(not dummy.visible, "the killed body reappeared when the ceremony ended")
	_verify_restored("after an execution")


func _first_material(execution: IaidoExecution) -> ShaderMaterial:
	if execution.look.is_empty():
		return null
	return execution.look[0]["material"] as ShaderMaterial


# =============================================================================
# 6 · §G §9 · a signature that did NOT kill
# =============================================================================

func _verify_a_non_lethal_cut_does_not_split() -> void:
	_prepare()
	# A body that simply outlives the blow. The blade still lands — the damage is
	# real — but the contract's answer is "not this time".
	dummy.set("max_health", 100000.0)
	dummy.call("reset_dummy")
	_hold(_damage_time())
	_check(_execution() == null, "a signature that did not kill split the body in half")
	_check(dummy.visible, "a body that survived the cut was hidden")
	_check(bool(dummy.call("is_alive")), "a body that survived the cut was marked dead")
	_check(dummy.health < 100000.0, "the cut did no damage at all")
	_check(
		not bool(dummy.call("expects_iaido_execution")),
		"a non-lethal cut flagged itself for the execution"
	)
	var marks := 0
	for child in dummy.get_children():
		if child is ShadowCutMark:
			marks += 1
	_check(marks == 1, "a failed signature left %d deep-cut marks, expected exactly 1" % marks)
	_check(float(dummy.get("deep_slash")) > 0.0, "a failed signature left no reaction at all — it reads as a broken hit")
	iaido.finish_iaido()
	await physics_frame

	# ...and the debug switch does the same thing without touching anyone's health.
	_prepare()
	iaido.set_debug_lethality(2)
	_hold(_damage_time())
	_check(_execution() == null, "the forced non-lethal switch still split the body")
	_check(dummy.visible and bool(dummy.call("is_alive")), "the forced non-lethal switch killed the body")
	iaido.set_debug_lethality(0)
	iaido.finish_iaido()
	await physics_frame
	dummy.call("reset_dummy")
	_verify_restored("after a non-lethal cut")


# =============================================================================
# 7 · §S TEST 4 · a body being held cannot act
# =============================================================================

func _verify_a_held_body_cannot_act() -> void:
	_prepare()
	_hold(_damage_time())
	_check(_execution() != null, "the body was not held")
	# `force_attack` is the API the developer panel uses to make an enemy swing.
	# If even that cannot move a held body, nothing in the fight can.
	dummy.call("force_attack", 1)
	_check(not bool(dummy.get_node("AttackHitbox").get("active")), "a held body armed its hitbox on command")
	_check(attacks.is_empty(), "a held body started an attack")
	dummy.call("on_interrupted", 1.0)
	_check(attacks.is_empty(), "a held body started an attack after being interrupted")
	# And it cannot be put back into the fight by a debug state change either.
	dummy.call("apply_debug_state", &"normal")
	_check(bool(dummy.call("is_alive")) == false, "a debug reset revived a held body")
	_check(not dummy.visible, "a debug reset made a held body visible while the ceremony owns it")
	iaido.finish_iaido()
	await physics_frame

	# A body whose contract says "no" is not held — it just dies, which is the
	# answer that makes the contract a contract rather than a convention.
	_prepare()
	dummy.set("execution_profile", IaidoExecutionLibrary.none())
	dummy.call("reset_dummy")
	_hold(_damage_time())
	_check(_execution() == null, "a body whose profile says 'no execution' was executed anyway")
	_check(not bool(dummy.call("expects_iaido_execution")), "a body that refuses execution flagged one")
	_check(not bool(dummy.call("is_alive")), "a body cut lethally by the signature survived it")
	iaido.finish_iaido()
	await physics_frame
	_verify_restored("after a refused execution")


# =============================================================================
# 8 · §S TEST 8 · an ordinary kill is still an ordinary kill
# =============================================================================

func _verify_an_ordinary_kill_never_executes() -> void:
	_prepare()
	# The same enemy, the same lethality, no signature: a plain overwhelming hit.
	var hurtbox := dummy.get_node("Hurtbox") as CombatHurtbox
	hurtbox.receive_hit({
		"damage": 9999.0, "poise_damage": 0.0, "element": &"physical",
		"impulse": 0.0, "source": player,
	})
	_check(not dummy.visible, "an ordinary kill left the body standing")
	_check(not bool(dummy.call("expects_iaido_execution")), "an ordinary kill flagged itself for the execution")
	_check(_execution() == null, "an ordinary kill created an execution")
	_check(_execution_nodes() == 0, "an ordinary kill left an execution node behind")
	# Damage alone must never route into the ceremony — that is the difference
	# between a signature and a damage number, and it is the whole premise.
	_prepare()
	hurtbox.receive_hit({
		"damage": 9999.0, "poise_damage": 9999.0, "element": &"physical",
		"impulse": 0.0, "source": player, "frozen_bonus": 2.0,
	})
	_check(_execution() == null, "a heavy ordinary kill created an execution")
	await physics_frame
	dummy.call("reset_dummy")


# =============================================================================
# 9 · §E §6-7 · ART's split meshes, and the swap that must be invisible
# =============================================================================

func _verify_authored_split_meshes() -> void:
	_prepare()
	var profile := IaidoExecutionLibrary.construct()
	profile.split_variants = [_half("HalfA", Color(0.55, 0.5, 0.42)), _half("HalfB", Color(0.42, 0.46, 0.5))]
	dummy.set("execution_profile", profile)
	dummy.call("reset_dummy")
	_hold(_damage_time())
	var execution := _execution()
	_check(execution != null, "an authored-split body did not enter the execution hold")
	if execution == null:
		return
	# DURING THE HOLD THE BODY IS ONE PIECE. §E §7: the shader draws the wound and
	# the real geometry is swapped in at the click — a body that is two meshes from
	# the instant of the cut was never held and the beat does not exist.
	var authored_during_hold := 0
	for piece in execution.pieces:
		authored_during_hold += (piece["pivot"] as Node3D).get_child_count()
	_check(
		authored_during_hold == 0,
		"the authored halves were swapped in at the cut — the hold never happened"
	)
	_check(execution.wounded != null, "an authored-split body wore no wound during the hold")
	_check(not execution.look.is_empty(), "the wounded body drew no cut line")
	_hold(_at("final_click") + 0.02)
	_check(execution.wounded == null, "the wounded body was not swapped out on the click")
	var swapped := 0
	for piece in execution.pieces:
		swapped += (piece["pivot"] as Node3D).get_child_count()
	_check(swapped == 2, "the click produced %d authored pieces, expected 2" % swapped)
	_check(
		execution.look.is_empty(),
		"the clip-plane cut survived the swap — the body would be drawn twice"
	)
	_hold(_at("final_click") + 0.30)
	_check(
		execution.separation() > 0.004,
		"the authored halves did not come apart after the click"
	)
	# The generic path must still be the one that runs when nothing is authored.
	iaido.finish_iaido()
	await physics_frame
	_prepare()
	_hold(_damage_time())
	var generic := _execution()
	_check(generic != null, "the generic path stopped working once authored meshes existed")
	if generic != null:
		_check(generic.wounded == null, "the generic path built a wounded body it did not need")
		var clipped := 0
		for piece in generic.pieces:
			clipped += (piece["pivot"] as Node3D).get_child_count()
		_check(clipped > 0, "the generic path built no clipped geometry")
	iaido.finish_iaido()
	await physics_frame
	_verify_restored("after the authored-split probe")


func _half(name: String, tint: Color) -> PackedScene:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.1, 0.7, 1.1)
	mesh.material = material
	var root := MeshInstance3D.new()
	root.name = name
	root.mesh = mesh
	var scene := PackedScene.new()
	scene.pack(root)
	return scene


# =============================================================================
# 10 · §P · many bodies, one slash, one cut moment
# =============================================================================

func _verify_multi_kill() -> void:
	_prepare()
	var lab := world.get("execution_lab") as ExecutionLab
	_check(lab != null, "the execution lab was never built into the sandbox")
	if lab == null:
		return
	lab.reset()
	var entry := lab.entry_position()
	player.global_position = entry
	player.velocity = Vector3.ZERO
	player.look_at_from_position(entry, entry + Vector3(0.0, 0.0, -6.0), Vector3.UP)
	combat.iaido_ready_at = 0.0
	player.set("stamina", 100.0)
	_hold(_damage_time())
	_check(
		iaido.targets.size() == 3,
		"one slash collected %d of the lab's bodies, expected 3" % iaido.targets.size()
	)
	_check(
		iaido.executions.size() == 3,
		"one slash executed %d bodies, expected 3" % iaido.executions.size()
	)
	var releases: Array[float] = []
	for execution in iaido.executions:
		releases.append(execution.release_at)
		_check(execution.piece_count() == 2, "an executed body has %d pieces" % execution.piece_count())
	# §P · the CUT is one instant, the FALL is not. 20-80ms of spread, and not
	# zero: ten bodies coming apart on one frame reads as a copy-and-paste.
	for i in releases.size():
		for j in range(i + 1, releases.size()):
			var gap := absf(releases[i] - releases[j])
			_check(gap >= 0.02 - 0.0001, "two bodies killed by one slash fall %.1fms apart — §P asks for at least 20ms" % (gap * 1000.0))
			_check(gap <= 0.08 + 0.0001, "two bodies fall %.0fms apart — §P allows at most 80ms" % (gap * 1000.0))
	# And they all resolve, and none of them is left standing.
	_hold(_at("restore_start") - 0.02)
	iaido.finish_iaido()
	await physics_frame
	_check(_execution_nodes() == 0, "the multi-kill left execution nodes behind")
	for body in lab.targets:
		_check(not body.visible, "%s was left standing" % body.name)
	lab.reset()
	_verify_restored("after the multi-kill")


# =============================================================================
# 11 · §O §12 · every way out of the ceremony, and none of them leaves a corpse
# =============================================================================

func _verify_every_way_out_of_the_ceremony_resolves() -> void:
	# ---- 1 · AN EXPLICIT ABORT, MID-HOLD ------------------------------------
	_prepare()
	_hold(_damage_time() + 1.5)
	_check(_execution() != null and not dummy.visible, "the body was not being held")
	iaido.finish_iaido()
	await physics_frame
	_check(not dummy.visible, "an aborted ceremony left the body standing")
	_check(_execution_nodes() == 0, "an aborted ceremony left an execution node behind")
	_verify_restored("after an abort")

	# ---- 2 · THE PLAYER DIES MID-HOLD --------------------------------------
	_prepare()
	_hold(_damage_time() + 1.5)
	player.set("health", 0.0)
	# IDLE FRAMES, NOT PHYSICS FRAMES.
	#
	# The director watches for a player death in `_process`, and under
	# `--headless` a couple of `physics_frame` waits can complete without an
	# idle frame ever being serviced — which is how this check once passed a
	# director that had not noticed the player was dead. The frame the death is
	# actually seen on is an idle one.
	await process_frame
	await process_frame
	_check(not iaido.active, "the ceremony kept running after the player died")
	_check(not dummy.visible, "a player death left a held body standing in the world")
	_check(_execution_nodes() == 0, "a player death left an execution node behind")
	player.set("health", 100.0)
	_verify_restored("after a player death")

	# ---- 3 · THE DIRECTOR IS DESTROYED MID-HOLD ----------------------------
	#
	# The strongest form of §12, and the last check to run because it takes the
	# director out of the world for good. A held body whose director vanishes must
	# not be left behind: it is logically dead, cannot be hit, and standing up.
	_prepare()
	_hold(_damage_time() + 1.5)
	_check(_execution() != null, "the body was not being held")
	world.remove_child(iaido)
	iaido.free()
	await physics_frame
	_check(not dummy.visible, "destroying the director mid-hold left the body standing forever")
	_check(_execution_nodes() == 0, "an execution outlived the director that owned it")
	_check(not root.get_tree().paused, "a destroyed director left the world paused")
	_check(absf(Engine.time_scale - 1.0) < 0.001, "a destroyed director left time scaled at %.2f" % Engine.time_scale)
	# AND IT IS NOT ONLY THE BODY. `CombatController.State.IAIDO` is entered when
	# the ceremony starts and cleared only by `finish_iaido()`; a director that
	# simply vanishes used to leave it set, which is not "the ceremony is still
	# running" — it is a player who can never attack again, because `request()`
	# refuses every action while the state is not IDLE.
	_check(
		combat.state == CombatController.State.IDLE,
		"the director was destroyed mid-ceremony and left the controller in state %d — the player could never act again" % combat.state
	)
	# Put a director back so the real-time run can happen at all.
	var replacement: Node = load("res://scripts/combat/iaido_director.gd").new()
	replacement.name = "IaidoDirector"
	replacement.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(replacement)
	world.get_node("IaidoDirector").set("tuning", tuning)
	# AND THE CONTROLLER HAS TO BE TOLD.
	#
	# `CombatController.iaido_director` is an `@onready` reference resolved when
	# the world came up. A director that is destroyed and rebuilt leaves that
	# pointing at a freed node, and the next `request(&"iaido")` reaches into it
	# and fails before anything runs — which is why this run reported "the
	# ceremony could not be requested at all" rather than anything about the
	# ceremony itself.
	combat.set("iaido_director", world.get_node("IaidoDirector"))
	dummy.call("reset_dummy")
	await physics_frame


# =============================================================================
# 12 · ONE real-time run, because a suite that only scrubs proves nothing
# =============================================================================

func _verify_full_run_in_real_time() -> void:
	player.global_position = Vector3(0.0, 1.15, 0.0)
	dummy.call("reset_dummy")
	var director := world.get_node("IaidoDirector") as IaidoDirector
	director.set("tuning", tuning)
	director.set("player", player)
	director.set("combat", combat)
	director.set("camera", camera)
	combat.iaido_ready_at = 0.0
	player.set("stamina", 100.0)
	player.set("health", 100.0)
	var started := combat.request(&"iaido")
	_check(started, "the ceremony could not be requested at all")
	if not started:
		return
	await physics_frame
	var saw_execution := false
	var saw_hold := false
	var saw_release := false
	var max_separation := 0.0
	# IDLE frames: the ceremony advances in `_process`, and a loop of physics
	# waits would spin here for 2400 frames without the clock ever moving.
	var guard := 0
	while director.active and guard < 2400:
		await process_frame
		guard += 1
		# Read off THIS director, not the global `iaido` — that one was destroyed
		# by the fail-safe check above, and asking a freed node for its execution
		# list is how this run reported "never created an execution at all" while
		# three bodies were visibly coming apart.
		var execution: IaidoExecution = (
			director.executions[0] if not director.executions.is_empty() else null)
		if execution == null:
			continue
		saw_execution = true
		max_separation = maxf(max_separation, execution.separation())
		if director.elapsed > _at("final_click"):
			saw_release = true
		elif director.elapsed > _at("damage_time") + 1.0:
			saw_hold = true
	_check(not director.active, "the ceremony never finished on its own")
	_check(saw_execution, "a real run never created an execution at all")
	_check(saw_hold, "a real run never reached the hold")
	_check(saw_release, "a real run never reached the release")
	_check(
		max_separation >= 0.010,
		"the largest misalignment a real run produced was %.4fm — the beat never happened" % max_separation
	)
	_check(not dummy.visible, "a real run ended with the killed body back on its feet")
	_check(_execution_nodes() == 0, "a real run left execution nodes behind")
	_check(not root.get_tree().paused, "a real run ended with the world still paused")
	_verify_restored("after a real-time run")


# =============================================================================

func _verify_restored(label: String) -> void:
	var glass_layer := world.get_node_or_null("IaidoGlassLayer")
	_check(combat.state == CombatController.State.IDLE, "combat state not restored " + label)
	_check(absf(Engine.time_scale - 1.0) < 0.001, "time scale stuck at %.2f %s" % [Engine.time_scale, label])
	_check(not root.get_tree().paused, "tree still paused " + label)
	if glass_layer != null:
		_check(not glass_layer.active, "glass shards still active " + label)
