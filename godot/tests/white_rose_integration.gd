extends SceneTree
# 白蔷庭剑术 · White Rose School — distance as the style's decision.
#
# The brief's own question for this style is:
#   "does the player start actively controlling distance?"
# So this test refuses to accept a style that is a rhythm reskin. It asserts that
# Measure changes the QUALITY of an attack (startup / reach / posture) and never
# its damage, that the chain refuses to finish, that the feint is the one move
# whose exit opens during the wind-up, and that the guard BINDS into a choice
# rather than flinging the enemy away.
#
# It also checks §44: no style may be hard-bound to an element.

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var failures: Array[String] = []

const CLOSE := 0.95
const IDEAL := 2.20
const FAR := 4.60


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


# Let idle processing run: measure_range is refreshed in _process().
func _settle() -> void:
	await process_frame
	await process_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	dummy = world.get_node("TechnicalDummy")
	combat = player.get_node("CombatController")
	player.global_position = Vector3(0, 1.15, -0.6)
	dummy.set("attack_cooldown", 999.0)
	await _wait(3)

	await _verify_measure_is_not_a_damage_stat()
	await _verify_measure_reads_only_what_is_in_front()
	await _verify_chuanting_rewards_measure_not_crowding()
	await _verify_third_cut_keeps_the_threat_alive()
	await _verify_the_chain_is_short_cuts()
	await _verify_jiazhang_can_be_taken_back_mid_windup()
	await _verify_bind_is_a_choice()
	await _verify_no_style_is_bound_to_an_element()

	if failures.is_empty():
		print("PASS: 白蔷庭 · measure buys handling not damage, the chain refuses to finish, the feint is real, and the bind is a choice")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


# ---------------------------------------------------------------- helpers

func _place_dummy(distance: float) -> void:
	var forward := -player.global_transform.basis.z
	dummy.global_position = player.global_position + forward * distance + Vector3(0, -0.55, 0)


func _reset() -> void:
	combat.finish_action()
	dummy.call("reset_dummy")
	dummy.set("attack_cooldown", 999.0)
	combat.set_style(SwordMovesetLibrary.STYLE_WHITE_ROSE, true)
	combat.reset_flow()
	combat.reset_skill_cooldowns()


# Commit a named move WITHOUT waiting for it: this samples the exact hitbox and
# startup the player would have got if they had pressed the button right now.
func _commit(move_id: StringName) -> Dictionary:
	combat.finish_action()
	var move: SwordMove = combat.moveset.get_move(move_id)
	combat.call("_begin_move", move, CombatController.State.ATTACK)
	return {
		"startup": combat.effective_startup(),
		"damage": float(combat.hitbox.damage),
		"poise": float(combat.hitbox.poise_damage),
		"reach": combat.hitbox.position.z,
	}


# --- the core claim: measure is handling, not power ----------------------

func _verify_measure_is_not_a_damage_stat() -> void:
	_reset()

	_place_dummy(CLOSE)
	await _settle()
	var close_shot := _commit(&"wr_l2")
	var close_label := combat.measure_label()

	_place_dummy(IDEAL)
	await _settle()
	var ideal_shot := _commit(&"wr_l2")
	var ideal_label := combat.measure_label()

	_place_dummy(FAR)
	await _settle()
	var far_shot := _commit(&"wr_l2")
	var far_label := combat.measure_label()

	_check(close_label == &"close", "0.95m did not read as too close (got %s)" % close_label)
	_check(ideal_label == &"ideal", "2.20m did not read as ideal measure (got %s)" % ideal_label)
	_check(far_label == &"far", "4.60m did not read as too far (got %s)" % far_label)

	# The whole point: the same move hits equally hard at every distance...
	_check(
		is_equal_approx(close_shot["damage"], ideal_shot["damage"])
		and is_equal_approx(ideal_shot["damage"], far_shot["damage"]),
		"Measure changed the damage (%.1f / %.1f / %.1f) — it became a power stat"
		% [close_shot["damage"], ideal_shot["damage"], far_shot["damage"]]
	)
	# ...but it does not behave the same way.
	_check(
		ideal_shot["startup"] < close_shot["startup"] and ideal_shot["startup"] < far_shot["startup"],
		"Stance at ideal measure did not start faster (close %.3f / ideal %.3f / far %.3f)"
		% [close_shot["startup"], ideal_shot["startup"], far_shot["startup"]]
	)
	_check(
		ideal_shot["poise"] > close_shot["poise"] and ideal_shot["poise"] > far_shot["poise"],
		"Stance at ideal measure did not break posture harder (%.1f / %.1f / %.1f)"
		% [close_shot["poise"], ideal_shot["poise"], far_shot["poise"]]
	)
	_check(
		ideal_shot["reach"] < close_shot["reach"],
		"An extended point at ideal measure did not reach further (%.2f vs %.2f)"
		% [ideal_shot["reach"], close_shot["reach"]]
	)
	_check(combat.measure_ideal_count >= 1, "Ideal measure never actually fired")
	_reset()


func _verify_measure_reads_only_what_is_in_front() -> void:
	_reset()
	# Behind the player: there is nobody to measure, and an empty lane is not the
	# same thing as "too far".
	var backward := player.global_transform.basis.z
	dummy.global_position = player.global_position + backward * IDEAL + Vector3(0, -0.55, 0)
	await _settle()
	_check(combat.measure_label() == &"", "Measure read an opponent standing behind the player")

	_place_dummy(IDEAL)
	await _settle()
	_check(combat.measure_label() == &"ideal", "A target straight ahead was not read")

	# Out of the cone: 3m ahead but pushed 6m sideways.
	dummy.global_position = player.global_position + Vector3(6.0, -0.55, -IDEAL)
	await _settle()
	_check(combat.measure_label() == &"", "Measure read an opponent off to the side")

	# And the style that owns no measure reads nothing, at any distance.
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	_place_dummy(IDEAL)
	await _settle()
	_check(combat.measure_label() == &"", "Universal has a measure: the mechanic leaked out of 白蔷庭")
	_reset()


func _verify_chuanting_rewards_measure_not_crowding() -> void:
	_reset()

	_place_dummy(CLOSE)
	await _settle()
	var hugging := _commit(&"wr_chuanting")

	_place_dummy(IDEAL)
	await _settle()
	var measured := _commit(&"wr_chuanting")

	# 穿庭 is the case the brief calls out by name: a posture weapon at ideal
	# measure, an ordinary heavy when face-hugging.
	_check(
		measured["poise"] > hugging["poise"] * 1.6,
		"穿庭 did not reward measure over crowding (%.1f hugged vs %.1f measured)"
		% [hugging["poise"], measured["poise"]]
	)
	_check(
		measured["poise"] >= 50.0,
		"穿庭 at ideal measure did not reach a posture break (%.1f)" % measured["poise"]
	)
	# And still not by hitting harder.
	_check(
		is_equal_approx(hugging["damage"], measured["damage"]),
		"穿庭 got its measure bonus from damage (%.1f vs %.1f)" % [hugging["damage"], measured["damage"]]
	)
	_reset()


# --- the chain deliberately refuses to resolve ---------------------------

func _verify_third_cut_keeps_the_threat_alive() -> void:
	_reset()
	var l3: SwordMove = combat.moveset.get_move(&"wr_l3")
	_check(l3 != null, "第三式 反 is missing from the chain")
	if l3 == null:
		return
	_check(l3.followup_id == &"wr_l1", "The third cut does not feed back into the chain")
	_check(
		not l3.followup_from_start,
		"The third cut opens its follow-up before contact: a whiff would keep a dead chain alive"
	)

	# Behavioural half: connect → the chain continues; whiff → it does not.
	_place_dummy(IDEAL)
	await _settle()
	combat.call("_begin_move", l3, CombatController.State.ATTACK)
	combat.call("_on_hitbox_landed", {
		"damage": 16.0, "poise_damage": 15.0, "element": &"physical",
		"impulse": 0.0, "source": player, "target": dummy,
	})
	var connected := combat.pending_followup_id
	_check(connected == &"wr_l1", "Connecting with 第三式 did not keep the chain alive (got %s)" % connected)

	combat.finish_action()
	combat.call("_begin_move", l3, CombatController.State.ATTACK)
	var whiffed := combat.pending_followup_id
	_check(whiffed == &"", "Whiffing 第三式 still kept the chain alive")
	_reset()


func _verify_the_chain_is_short_cuts() -> void:
	_reset()
	var chain := combat.moveset.light_chain
	_check(chain.size() == 3, "白蔷庭's basic chain is not three cuts (got %d)" % chain.size())

	var heavy: SwordMove = combat.moveset.get_move(combat.moveset.heavy_id)
	for move_id in chain:
		var move: SwordMove = combat.moveset.get_move(move_id)
		if move == null:
			continue
		# No big swings: every basic cut must be small and, crucially, must keep
		# a hitbox that is a point rather than an arc.
		_check(
			move.pose_span() <= 0.235,
			"%s has a long tail: it is a swing, not a cut (%.3fs)" % [move.display_name, move.pose_span()]
		)
		_check(
			move.poise_damage < heavy.poise_damage * 0.6,
			"%s breaks posture like a heavy: the chain has a finisher in it" % move.display_name
		)
	# The second cut is the point: much deeper than it is wide.
	var thrust: SwordMove = combat.moveset.get_move(&"wr_l2")
	_check(
		thrust.hitbox_size.z > thrust.hitbox_size.x * 2.5,
		"第二式 刺 is not a point (%.2f wide x %.2f deep)" % [thrust.hitbox_size.x, thrust.hitbox_size.z]
	)
	_reset()


# --- 假章: the only exit that opens during the wind-up -------------------

func _verify_jiazhang_can_be_taken_back_mid_windup() -> void:
	_reset()
	# A known distance, so the measure multiplier on startup cannot make the
	# numbers below drift between runs.
	_place_dummy(IDEAL)
	await _settle()
	var feint: SwordMove = combat.moveset.get_move(&"wr_jiazhang")
	var real: SwordMove = combat.moveset.get_move(&"wr_chuanting")
	_check(feint.feint_cancel_from < 1.0, "假章 has no early exit: it is just a slow attack")

	# Frame-counting is the honest measurement: "can I get out yet?"
	var feint_exit := await _frames_until_dodge_cancel(feint)
	var real_exit := await _frames_until_dodge_cancel(real)
	_check(
		feint_exit < real_exit,
		"假章 did not let the player leave earlier than a real thrust (%d frames vs %d)"
		% [feint_exit, real_exit]
	)

	# And it must be genuinely early: the exit has to open while the wind-up is
	# still running, not merely sooner than a very slow move's. The window scales
	# with effective_startup() because Measure shortens the wind-up too — the
	# bluff and the real thrust it imitates must stay the same length.
	combat.finish_action()
	combat.call("_begin_move", feint, CombatController.State.ATTACK)
	var windup := combat.effective_startup()
	combat.state_time = windup * feint.feint_cancel_from + 0.005
	_check(combat.state_time < windup, "The feint test did not sample inside the wind-up")
	_check(
		combat._can_cancel(&"light"),
		"假章's exit did not open inside its own wind-up (%.3fs of %.3fs)" % [combat.state_time, windup]
	)
	# The contrast: a real attack must NOT be cancellable inside its wind-up.
	combat.finish_action()
	combat.call("_begin_move", real, CombatController.State.ATTACK)
	combat.state_time = combat.effective_startup() * 0.9
	_check(not combat._can_cancel(&"light"), "A real attack was cancellable during its wind-up")
	_reset()


# How many frames until Dodge / Light unlocks again, capped so a never-unlocking
# move cannot hang the test.
func _frames_until_dodge_cancel(move: SwordMove) -> int:
	combat.finish_action()
	combat.call("_begin_move", move, CombatController.State.ATTACK)
	for frame in 240:
		if combat._can_cancel(&"light"):
			return frame
		await physics_frame
	return 240


# --- Bind: a perfect guard that hands the player a choice ----------------

func _strike_player() -> void:
	var enemy_hitbox: CombatHitbox = dummy.get_node("AttackHitbox")
	enemy_hitbox.set_active(true)
	await physics_frame
	await physics_frame
	enemy_hitbox.set_active(false)


func _perfect_guard_now() -> bool:
	combat.finish_action()
	await physics_frame
	combat.set_state(CombatController.State.BLOCK)
	var before := combat.perfect_guard_count
	await _strike_player()
	return combat.perfect_guard_count == before + 1


func _verify_bind_is_a_choice() -> void:
	_reset()
	_place_dummy(IDEAL)
	await _settle()

	var guard := combat.moveset.guard
	_check(guard.bind_enabled, "白蔷庭's guard does not bind")
	_check(
		guard.bind_deck_window >= 0.20 and guard.bind_deck_window <= 0.40,
		"The bind window is outside the 0.2-0.4s the style calls for (%.2f)" % guard.bind_deck_window
	)

	# 1) The bind does not move the player off the line, unlike 回风 and 藏锋.
	_check(
		is_zero_approx(guard.parry_steer),
		"A bind that sidesteps is not a bind: the point leaves the line (%.2f)" % guard.parry_steer
	)
	var dummy_before := dummy.global_position
	var bound := await _perfect_guard_now()
	_check(bound, "The bind never happened: perfect guard did not land")
	_check(combat.state == CombatController.State.PARRY, "A bind did not enter the parry beat")
	_check(is_zero_approx(combat.parry_lateral), "The bind threw the player off the line")
	_check(combat.bind_until > Time.get_ticks_msec() / 1000.0, "The bind deck window did not open")
	# The attacker is not flung: it is stopped, in place, in front of you.
	_check(
		dummy.global_position.distance_to(dummy_before) < 0.4,
		"The bind flung the enemy away (%.2fm) — that is a parry, not a bind"
		% dummy.global_position.distance_to(dummy_before)
	)

	# 2) Light inside the window is the riposte thrust (staying in the measure).
	combat.state_time = 0.05
	_check(combat.request(&"light"), "Light inside the bind window did nothing")
	_check(
		combat.active_move_id == &"wr_bind_thrust",
		"Light inside the bind did not answer with the riposte thrust (got %s)" % combat.active_move_id
	)

	# 3) Heavy inside the window is the disengage cut (leaving the measure).
	_reset()
	_place_dummy(IDEAL)
	await _settle()
	await _perfect_guard_now()
	combat.state_time = 0.05
	_check(combat.request(&"heavy"), "Heavy inside the bind window did nothing")
	_check(
		combat.active_move_id == &"wr_bind_disengage",
		"Heavy inside the bind did not disengage (got %s)" % combat.active_move_id
	)
	var disengage: SwordMove = combat.moveset.get_move(&"wr_bind_disengage")
	_check(
		disengage.lunge < 0.0,
		"The disengage cut does not actually leave (lunge %.2f)" % disengage.lunge
	)

	# 4) Once the window closes, Heavy must go back to being an ordinary heavy.
	_reset()
	_place_dummy(IDEAL)
	await _settle()
	await _perfect_guard_now()
	combat.bind_until = 0.0
	_check(not combat._can_cancel(&"heavy"), "Heavy stayed bound after the deck window closed")
	_reset()


# --- §44: no fixed style <-> element pairings ----------------------------

func _verify_no_style_is_bound_to_an_element() -> void:
	# The brief forbids 藏锋 = ice / 回风 = wind / 白蔷 = fire. The mechanical
	# version of that rule: every style must be able to take every school, and
	# the resulting spell must be the school's own — never a style's default.
	var styles := SwordMovesetLibrary.all_styles()
	var schools := [ElementLibrary.FIRE, ElementLibrary.FROST, ElementLibrary.WIND]
	for style_id in styles:
		for school_id in schools:
			combat.set_style(style_id, true)
			combat.finish_action()
			var ok := combat.select_school(school_id)
			_check(ok, "%s could not take the %s school" % [style_id, school_id])
			var school := combat.current_school()
			_check(
				school != null and school.id == school_id,
				"%s + %s resolved to the wrong school" % [style_id, school_id]
			)
			# A style must not force a spell either.
			_check(
				combat.current_spell() != null and combat.current_spell().element_id == school_id,
				"%s overrode the %s spell" % [style_id, school_id]
			)
	_reset()
