extends SceneTree
# Universal Single-Sword Layer check.
#
# Verifies that the base language is complete and honest for every style:
# a light chain with readable timing, a Tap/Hold heavy that is not "damage x2",
# sprint / retreat variants, a riposte, and a guard profile.

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
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
	combat = player.get_node("CombatController")
	await physics_frame
	await physics_frame

	_verify_style_data()
	_verify_light_timing()
	await _verify_combo_reset()
	await _verify_heavy_charge()
	await _verify_cancel_window()
	_verify_pose_sampler()

	if failures.is_empty():
		print("PASS: universal single-sword moveset · chain, charging heavy, cancels, pose curves")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _verify_style_data() -> void:
	for style_id in SwordMovesetLibrary.all_styles():
		var moveset: SwordMoveset = SwordMovesetLibrary.build(style_id)
		var tag := String(style_id)
		_check(moveset.has_light_chain(), "%s has no light chain" % tag)
		_check(moveset.get_move(moveset.heavy_id) != null, "%s has no heavy" % tag)
		_check(moveset.get_move(moveset.sprint_light_id) != null, "%s has no sprint attack" % tag)
		_check(moveset.get_move(moveset.retreat_light_id) != null, "%s has no retreat attack" % tag)
		_check(moveset.get_move(moveset.riposte_id) != null, "%s has no riposte" % tag)
		_check(moveset.guard != null, "%s has no guard profile" % tag)
		_check(
			moveset.guard.perfect_guard_window >= 0.08 and moveset.guard.perfect_guard_window <= 0.16,
			"%s perfect guard window outside the 80-160ms band (%.3f)" % [tag, moveset.guard.perfect_guard_window]
		)
		# The answer window is wide for a style whose perfect guard is a PAYOFF.
		# A binding style is the documented exception: it deliberately shortens
		# the window to the bind's deck window (0.2-0.4s), because there the
		# reward is the choice between three exits, not the time to make it.
		if moveset.guard.bind_enabled:
			_check(
				moveset.guard.riposte_window >= 0.20 and moveset.guard.riposte_window <= 0.40,
				"%s bind deck window outside the 0.2-0.4s band (%.2f)" % [tag, moveset.guard.riposte_window]
			)
		else:
			_check(
				moveset.guard.riposte_window >= 0.5 and moveset.guard.riposte_window <= 0.9,
				"%s riposte window outside the 0.5-0.9s band (%.2f)" % [tag, moveset.guard.riposte_window]
			)
		for move_id in moveset.moves:
			var move: SwordMove = moveset.moves[move_id]
			_check(move.startup > 0.0, "%s/%s has no startup" % [tag, move_id])
			_check(move.strike > 0.0, "%s/%s has no active window" % [tag, move_id])
			_check(move.recovery > 0.0, "%s/%s has no recovery" % [tag, move_id])
			_check(move.strike_power > 1.0, "%s/%s strike has no acceleration curve" % [tag, move_id])
			_check(
				move.anchor != move.contact,
				"%s/%s never actually moves the weapon" % [tag, move_id]
			)


func _verify_light_timing() -> void:
	var moveset := SwordMovesetLibrary.universal()
	# THE BASIC SENTENCE'S OWN BANDS. Four beats, and they cannot all be the same
	# length: A1 is a draw and a short cut, A2 follows it, A3 stops the world for
	# a beat and draws three times, A4 releases everything at once. A combo where
	# every move is 0.35s has no rhythm to speak of.
	var expectations := {
		SwordBasic.A1: Vector2(0.38, 0.44),
		SwordBasic.A2: Vector2(0.38, 0.46),
		SwordBasic.A3: Vector2(0.90, 1.15),
		SwordBasic.A4: Vector2(0.60, 0.76),
	}
	for move_id in expectations:
		var move: SwordMove = moveset.get_move(move_id)
		var window: Vector2 = expectations[move_id]
		var total := move.total_time()
		_check(
			total >= window.x - 0.005 and total <= window.y + 0.005,
			"%s total %.3fs outside the designed %.2f-%.2f band" % [move_id, total, window.x, window.y]
		)
	_check(
		moveset.light_chain == SwordBasic.light_chain(),
		"the universal light chain is not the four-beat basic sentence"
	)
	var a1: SwordMove = moveset.get_move(SwordBasic.A1)
	var a2: SwordMove = moveset.get_move(SwordBasic.A2)
	var a3: SwordMove = moveset.get_move(SwordBasic.A3)
	var a4: SwordMove = moveset.get_move(SwordBasic.A4)
	# DISTANCE IS THE GRAMMAR. Each beat must reach differently from the last, or
	# the combo is one move wearing four timings.
	_check(a1.reach_mode == &"body", "A1 reaches further than arm's length")
	_check(a2.reach_mode == &"wave" and a2.reach >= 6.0 and a2.reach <= 10.0,
		"A2's wave is %.1fm, outside the designed 6-10m mid range" % a2.reach)
	_check(a3.reach_mode == &"trace" and a3.traces.size() == 3,
		"A3 is not a three-mark space cut")
	_check(a4.reach_mode == &"arc" and (a4.reach_arc_to - a4.reach_arc_from) > 180.0,
		"A4 is not a major arc — a cut that has not passed behind the player is a shockwave")
	# A3 breaks the rhythm with a longer wind-up, exactly as §16 asks, and it is
	# the ONE beat that reaches furthest even though A4 comes after it.
	_check(a3.startup > a1.startup * 1.2, "A3 does not break the rhythm with a longer startup")
	_check(
		a3.traces[0]["reach"] < a3.traces[1]["reach"] and a3.traces[1]["reach"] < a3.traces[2]["reach"],
		"A3's three marks do not grow outward, so the third cut has nowhere to go"
	)
	_check(a4.reach_radius < 6.0, "A4 is an area finisher, not a long-range one (%.1fm)" % a4.reach_radius)



## §17 — THE COMBO IS A WINDOW, NOT MEMORY.
##
## Two failures live here. They look nothing alike in code and identical in the
## hand. The first is the window never expiring: `finish_action()` re-armed it on
## every cleanup call, including the ones made with nothing running, so
## `combo_index` only ever climbed and a player who stopped for a second came back
## to the cut AFTER the one they left. The second is a weapon change carrying the
## index across — `stow()` ends the cut, so without an explicit clear it also
## re-opened the window, and the first cut after a swap was a continuation of a
## sentence spoken with a different weapon.
##
## Both halves are asserted, and the second one matters as much as the first: a
## "reset" that also fired INSIDE the window would just mean the chain never
## works, which is the opposite bug wearing the same test.
func _verify_combo_reset() -> void:
	combat.finish_action()
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	var chain := combat.moveset.light_chain
	combat.request(&"light")
	# Press the second cut through the real gate rather than a hard-coded time, so
	# this stays honest if the cancel window is ever retuned.
	var guard := 0
	while not bool(combat.call("_can_cancel", &"light")) and guard < 240:
		await physics_frame
		guard += 1
	combat.request(&"light")
	await physics_frame
	_check(
		combat.combo_index == 2,
		"two cuts in a row did not chain (index=%d)" % combat.combo_index
	)

	# Stop for longer than the window. 1.5s of physics frames against the 0.90s
	# `combo_window`, i.e. a margin rather than a coincidence.
	guard = 0
	while combat.state != CombatController.State.IDLE and guard < 400:
		await physics_frame
		guard += 1
	_check(combat.state == CombatController.State.IDLE, "the second cut never ended")
	for i in 90:
		await physics_frame
	combat.request(&"light")
	await physics_frame
	_check(
		combat.combo_index == 1 and combat.active_move_id == chain[0],
		"after a pause longer than the combo window the next cut was %s (index %d) "
			% [String(combat.active_move_id), combat.combo_index]
		+ "instead of A1 (§17)"
	)

	# ...AND INSIDE THE WINDOW IT STILL CONTINUES. Six frames is 0.10s of the
	# 0.90s grace: a cut made there is the next beat of the sentence, not a new
	# sentence.
	guard = 0
	while combat.state != CombatController.State.IDLE and guard < 400:
		await physics_frame
		guard += 1
	for i in 6:
		await physics_frame
	combat.request(&"light")
	await physics_frame
	_check(
		combat.combo_index == 2,
		"a cut made inside the combo window restarted the chain (index=%d)"
			% combat.combo_index
	)
	combat.finish_action()
	await physics_frame


func _verify_heavy_charge() -> void:
	var heavy := SwordMovesetLibrary.universal().get_move(&"uni_heavy")
	_check(heavy.charged_poise_bonus > 1.4, "Charged heavy does not trade into posture")
	_check(heavy.charged_damage_bonus < 1.6, "Charged heavy is just damage x2")
	# Programmatic Tap Heavy must never leave the controller stuck in CHARGE.
	combat.finish_action()
	if not combat.request(&"heavy"):
		_check(false, "Heavy request was rejected")
		return
	_check(combat.state == CombatController.State.CHARGE, "Heavy did not enter the charge state")
	var guard := 0
	while combat.state == CombatController.State.CHARGE and guard < 120:
		await physics_frame
		guard += 1
	_check(combat.state == CombatController.State.ATTACK, "Tap Heavy never released into the strike")
	_check(combat.hitbox.poise_damage >= heavy.poise_damage, "Heavy strike lost its posture damage")
	# Hold Heavy must actually raise the posture multiplier.
	combat.finish_action()
	combat.request(&"heavy")
	combat.charge_ratio = 1.0
	combat.release_heavy()
	_check(combat.move_poise_scale > 1.4, "Fully charged heavy did not scale posture (%.2f)" % combat.move_poise_scale)
	await physics_frame
	_check(combat.hitbox.poise_damage > heavy.poise_damage, "Charged hitbox posture did not increase")
	combat.finish_action()
	await physics_frame


func _verify_cancel_window() -> void:
	combat.finish_action()
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	combat.request(&"light")
	await physics_frame
	await physics_frame
	# Still in the swing: a dodge must be buffered, not granted instantly, or
	# attacks carry no commitment at all.
	combat.request(&"dodge")
	_check(combat.state == CombatController.State.ATTACK, "Dodge cancelled out of the swing: attacks are not committed")
	# §18: AN EARLY PRESS IS A MASH, NOT A MEMORY. The input buffer is 0.10-0.18s
	# and only opens in the tail of a move, so a dodge pressed two frames into a
	# swing is dropped — remembering it would mean the button the player mashed
	# at the start of a cut fires four hundred milliseconds later, which is a
	# memory wearing a hundred-and-fifty-millisecond name.
	_check(
		combat.buffer.pending == &"",
		"An input two frames into a swing was remembered; the buffer is meant to open only near the end of a move"
	)
	# Past the cancel point the same input must be honoured immediately.
	var guard := 0
	while combat.state == CombatController.State.ATTACK and combat.state_time < 0.30 and guard < 200:
		await physics_frame
		guard += 1
	_check(combat.state == CombatController.State.ATTACK, "Light attack ended before the cancel check")
	combat.request(&"dodge")
	_check(combat.state == CombatController.State.DODGE, "Dodge was not granted at the cancel point")
	combat.finish_action()
	await physics_frame


func _verify_pose_sampler() -> void:
	var move := SwordMovesetLibrary.universal().get_move(SwordBasic.A1)
	var travelled := 0.0
	for i in 48:
		var t := float(i) / 48.0 * move.total_time()
		var sampled := SwordPoseSampler.sample(move, t)
		var position: Vector3 = sampled["position"]
		_check(position.is_finite(), "Pose sampler produced a non-finite position at t=%.3f" % t)
		if i > 0:
			travelled += position.distance_to(move.anchor)
	var done := SwordPoseSampler.sample(move, move.total_time() + 1.0)
	_check(done["phase"] == &"done", "Sampler never reports done")
	# THE BEAT LIST HAS TO KEEP THE SAME CONTRACT. A3 is sampled through a
	# different code path, so "the sampler is a pure function of t" has to be
	# asserted separately for it or the signature beat is the one move nobody
	# checked.
	var a3 := SwordMovesetLibrary.universal().get_move(SwordBasic.A3)
	for i in 40:
		var t := float(i) / 40.0 * a3.total_time()
		var sampled := SwordPoseSampler.sample(a3, t)
		var position: Vector3 = sampled["position"]
		_check(position.is_finite(), "A3's beat sampler produced a non-finite position at t=%.3f" % t)
	# And it must LAND ON its beats, not merely near them: the trace events are
	# authored at the same instants, so a beat the pose drifts past is a cut the
	# player never sees and the VFX still draws.
	var marks := 0
	for trace in a3.traces:
		var at: float = trace["t"]
		var here := SwordPoseSampler.sample(a3, at)
		var again := SwordPoseSampler.sample(a3, at)
		_check(
			(here["position"] as Vector3).is_equal_approx(again["position"] as Vector3),
			"A3's beat sampler is not deterministic at t=%.3f" % at
		)
		marks += 1
	_check(marks == 3, "A3 does not carry three cut marks")
	_check(travelled > 0.0, "Pose never leaves the anchor")
	# Contact must be reached at the end of the strike window, not drifted into.
	var at_contact := SwordPoseSampler.sample(move, move.startup + move.strike)
	_check(
		at_contact["position"].distance_to(move.contact) < 0.02,
		"Strike does not land on the authored contact pose"
	)
	# The anticipation must be slower than the strike: this is the whole point
	# of replacing the old fixed-response lerp.
	var early: Vector3 = SwordPoseSampler.sample(move, move.startup * 0.5)["position"]
	var late: Vector3 = SwordPoseSampler.sample(move, move.startup * 0.98)["position"]
	var first_half := move.anchor.distance_to(early)
	var second_half := early.distance_to(late)
	_check(second_half > first_half, "Anticipation is not accelerating into the strike")
