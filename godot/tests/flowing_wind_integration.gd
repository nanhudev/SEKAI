extends SceneTree
# 回风式 (Flowing Wind) check.
#
# The acceptance question from the design brief is behavioural, not numeric:
#   "does the player start moving on purpose to keep the sword flowing?"
# So this test refuses to be satisfied by numbers going up. It asserts that
# Flow buys HANDLING (steering, recovery, earlier transitions) and explicitly
# asserts that it does NOT buy damage — if Flow ever becomes a damage multiplier
# the style turns into a stat check and the design has failed.
#
# It also covers 折柳 (decline the exchange), 惊鸿 (transition enhancer) and
# 长风 (the player-aimed signature).

const UNIVERSAL := SwordMovesetLibrary.STYLE_UNIVERSAL
const HIDDEN_EDGE := SwordMovesetLibrary.STYLE_HIDDEN_EDGE
const FLOWING_WIND := SwordMovesetLibrary.STYLE_FLOWING_WIND

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _now() -> float:
	# The controller owns the clock its windows are stamped in. Comparing a
	# combat timestamp against wall time is comparing two currencies, and it
	# stops being true the moment the controller stops using the wall — which
	# is exactly what happened when every window moved onto simulation time.
	return combat._now()


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

	await _verify_flow_is_style_only()
	await _verify_flow_builds_and_breaks()
	await _verify_flow_buys_handling_not_damage()
	await _verify_zheliu_declines_the_exchange()
	await _verify_jinghong_opens_transitions()
	await _verify_changfeng_is_player_driven()

	if failures.is_empty():
		print("PASS: 回风 Flow buys handling not damage, 折柳 declines, 长风 stays in the player's hands")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _strike_player() -> void:
	var enemy_hitbox: CombatHitbox = dummy.get_node("AttackHitbox")
	enemy_hitbox.set_active(true)
	await physics_frame
	await physics_frame
	enemy_hitbox.set_active(false)


func _verify_flow_is_style_only() -> void:
	var universal := SwordMovesetLibrary.universal()
	var hidden := SwordMovesetLibrary.hidden_edge()
	var flow := SwordMovesetLibrary.flowing_wind()
	_check(not universal.flow_enabled, "Flow leaked into the Universal layer")
	_check(not hidden.flow_enabled, "Flow leaked into 藏锋流: 势 belongs to 回风")
	_check(flow.flow_enabled, "回风 has no Flow at all")
	# Flow must be a handling stat, so the data has no damage field to abuse.
	_check(flow.flow_max > 0.0, "回风 Flow has no ceiling")
	_check(flow.flow_recovery_at_max < 1.0, "Flow does not shorten recovery")
	_check(flow.flow_steer_bonus > 1.0, "Flow does not improve steering")


func _verify_flow_builds_and_breaks() -> void:
	combat.set_style(FLOWING_WIND, true)
	combat.finish_action()
	await _wait(2)
	_check(is_zero_approx(combat.flow), "回风 did not start the fight at zero 势")

	# Connecting builds it.
	player.global_position = Vector3(0, 1.15, -1.1)
	combat.request(&"light")
	var frames := 0
	while not combat.move_hit and frames < 60:
		await physics_frame
		frames += 1
	_check(combat.move_hit, "回风 light never connected")
	var after_hit := combat.flow
	_check(after_hit > 0.0, "A connected cut did not build 势")
	combat.finish_action()
	await _wait(2)

	# Whiffing takes it back.
	player.global_position = Vector3(0, 1.15, 14.0)
	await _wait(2)
	var before_whiff := combat.flow
	combat.request(&"light")
	frames = 0
	while combat.state != CombatController.State.IDLE and frames < 200:
		await physics_frame
		frames += 1
	_check(combat.flow < before_whiff, "Whiffing did not cost 势 (%.1f -> %.1f)" % [before_whiff, combat.flow])

	# Standing still lets it drain away entirely.
	frames = 0
	while combat.flow > 0.0 and frames < 600:
		await physics_frame
		frames += 1
	_check(is_zero_approx(combat.flow), "势 never decayed while standing still")
	player.global_position = Vector3(0, 1.15, -0.6)
	await _wait(2)


func _verify_flow_buys_handling_not_damage() -> void:
	combat.set_style(FLOWING_WIND, true)
	combat.finish_action()
	await _wait(2)

	# Baseline handling at zero 势.
	player.global_position = Vector3(0, 1.15, 14.0)
	await _wait(2)
	combat.request(&"light")
	await physics_frame
	var cold_steer := combat.movement_scale()
	var cold_damage := combat.hitbox.damage
	combat.finish_action()
	await _wait(2)

	# Drive 势 to the ceiling without connecting anything.
	combat.flow = combat.moveset.flow_max
	var hot_steer := combat.movement_scale() if combat.state != CombatController.State.IDLE else 0.0
	combat.request(&"light")
	await physics_frame
	hot_steer = combat.movement_scale()
	var hot_damage := combat.hitbox.damage
	_check(
		hot_steer > cold_steer * 1.2,
		"高 势 did not make the sword steer more freely (%.2f vs %.2f)" % [hot_steer, cold_steer]
	)
	# This is the line the design must not cross.
	_check(
		is_equal_approx(hot_damage, cold_damage),
		"势 changed damage (%.1f -> %.1f): it must buy handling, not power" % [cold_damage, hot_damage]
	)
	combat.finish_action()
	combat.reset_flow()
	await _wait(2)


func _verify_zheliu_declines_the_exchange() -> void:
	combat.set_style(FLOWING_WIND, true)
	combat.reset_skill_cooldowns()
	combat.finish_action()
	player.global_position = Vector3(0, 1.15, -1.2)
	await _wait(4)

	# Without 折柳 the same strike lands, so the test can prove it was declined.
	var health_before: float = player.get("health")
	await _strike_player()
	await _wait(2)
	var health_after_plain: float = player.get("health")
	_check(health_after_plain < health_before, "The control strike never damaged the player at all")

	# Now decline it.
	combat.finish_action()
	await _wait(2)
	combat.reset_flow()
	_check(combat.trigger_skill(1), "折柳 was rejected")
	_check(combat._slip_open(), "折柳 did not open its slip window")
	var slips_before := combat.slip_count
	await _strike_player()
	_check(combat.slip_count == slips_before + 1, "折柳 did not resolve as a slip")
	_check(
		is_equal_approx(float(player.get("health")), health_after_plain),
		"折柳 let the attack through: it must be declined, not traded"
	)
	_check(combat.riposte_until > _now(), "折柳 did not open the counter window")
	_check(combat.flow > 0.0, "A clean 折柳 did not feed 势")
	_check(not is_zero_approx(combat.parry_lateral), "折柳 did not step the body off the line")
	combat.finish_action()
	combat.reset_flow()
	await _wait(2)


# The baseline cut has to BE the baseline cut.
#
# `request(&"light")` returns whichever move the controller's open windows point
# at, and 折柳 has just opened a 0.9s counter window immediately before this runs:
# inside it, "light" is the RIPOSTE — a different song with a different cancel
# window. Whether the helper lands inside that window depends on how many frames
# the machine happened to spend getting here, which is why this test was FLAKY
# rather than broken, and why its failure read "the baseline cut was never
# cancellable" about a move that was never the baseline cut. Same class of bug
# as measuring the third light of a chain and calling it a light.
func _neutralise() -> void:
	combat.chain_expires_at = 0.0
	combat.combo_index = 0
	combat.last_light_at = -10.0
	combat.pending_followup_id = &""
	combat.followup_until = 0.0
	combat.riposte_until = 0.0
	combat.bind_until = 0.0
	combat.slip_until = 0.0
	combat.slip_skill = null
	combat.buffer.clear()


func _frames_until_dodge_cancel() -> int:
	# Start a fresh cut and count how long the style makes us hold it before we
	# are allowed to leave. Measuring the WAIT is the honest way to test a
	# transition enhancer: a single sample frame proves nothing, because the
	# startup is deliberately never cancellable.
	combat.finish_action()
	combat.reset_flow()
	await physics_frame
	_neutralise()
	combat.request(&"light")
	await physics_frame
	# And SAY which cut was timed. A rig that counts ninety frames of the wrong
	# move and reports a number is worse than one that says nothing.
	_check(
		combat.active_move_id == &"" or combat.active_move_id in combat.moveset.light_chain,
		"%s came out of a neutralised `light` — the windows are not the only thing deciding the move, so the frame count below is that move's number and not the baseline cut's"
			% combat.active_move_id
	)
	if combat.active_move_id != &"" and not (combat.active_move_id in combat.moveset.light_chain):
		return 999
	var frames := 0
	while frames < 90:
		await physics_frame
		frames += 1
		if combat._can_cancel(&"dodge"):
			return frames
	return 999


func _verify_jinghong_opens_transitions() -> void:
	combat.set_style(FLOWING_WIND, true)
	combat.reset_skill_cooldowns()
	combat.finish_action()
	await _wait(2)

	var frames_cold := await _frames_until_dodge_cancel()
	_check(frames_cold < 900, "The baseline cut was never cancellable at all")

	_check(combat.trigger_skill(2), "惊鸿 was rejected")
	_check(combat.active_move_id == &"fw_jinghong", "惊鸿 did not play its own move")
	var frames := 0
	while combat.state == CombatController.State.SKILL and frames < 300:
		await physics_frame
		frames += 1
	_check(combat.enhance_left > 5.0, "惊鸿 did not enter its enhanced state")
	_check(combat.enhance_transition_bonus > 0.0, "惊鸿 carries no transition bonus")

	var frames_hot := await _frames_until_dodge_cancel()
	_check(
		frames_hot < frames_cold,
		"惊鸿 did not let the style exit earlier (%d frames vs %d)" % [frames_hot, frames_cold]
	)

	# It must expire rather than being a permanent upgrade.
	combat.finish_action()
	frames = 0
	while combat.enhance_left > 0.0 and frames < 900:
		await physics_frame
		frames += 1
	_check(combat.enhance_left == 0.0, "惊鸿 never expired")
	var frames_after := await _frames_until_dodge_cancel()
	_check(
		frames_after > frames_hot,
		"惊鸿 was still speeding up transitions after it expired (%d vs %d)" % [frames_after, frames_hot]
	)
	combat.set_style(FLOWING_WIND, true)
	combat.finish_action()
	await _wait(2)


func _verify_changfeng_is_player_driven() -> void:
	combat.set_style(FLOWING_WIND, true)
	combat.reset_skill_cooldowns()
	combat.finish_action()
	player.global_position = Vector3(0, 1.15, 14.0)
	await _wait(2)

	# Aim the cut left: the pose must flip, because the player chose the side.
	Input.action_press("move_left")
	combat.request(&"iaido")
	Input.action_release("move_left")
	_check(combat.active_move_id == &"fw_changfeng_1", "长风 did not start its first cut")
	_check(combat.move_mirror < 0.0, "长风 ignored the player's aim")
	# The sequence must not lock the player down: steering stays open.
	_check(combat.movement_scale() > 0.5, "长风 took the wheel away from the player")
	# The window opens from the start, so a whiff cannot silently end it.
	_check(combat.pending_followup_id == &"fw_changfeng_2", "长风 opened no continuation")
	combat.finish_action()
	await _wait(2)

	# The player continues the sequence by hand, and aims each cut themselves.
	combat.reset_skill_cooldowns()
	Input.action_press("move_right")
	combat.request(&"iaido")
	Input.action_release("move_right")
	_check(combat.active_move_id == &"fw_changfeng_1", "长风 did not start again after its cooldown cleared")
	_check(combat.move_mirror > 0.0, "长风 did not mirror to the right")
	combat.request(&"light")
	_check(combat.active_move_id == &"fw_changfeng_2", "长风 did not continue to the second cut")
	combat.request(&"light")
	_check(combat.active_move_id == &"fw_changfeng_3", "长风 did not reach its third cut")
	# It is a signature, so it must have a real cooldown and it must not be the
	# ultimate slot.
	_check(combat.moveset.signature_id == &"fw_changfeng_1", "长风 is not registered as the signature")
	_check(combat.moveset.ultimate_id == &"", "长风 stole the ultimate slot")
	_check(combat.signature_cooldown_left() > 0.0, "长风 has no cooldown")
	combat.finish_action()
	await _wait(2)

	# 聚合斩 is 藏锋's signature and must be untouched by any of this.
	combat.set_style(HIDDEN_EDGE, true)
	_check(combat.moveset.signature_id == &"iaido", "藏锋 lost 聚合斩 as its signature")
	_check(combat.moveset.ultimate_id == &"moment_of_no_moon", "藏锋 lost its ultimate")
	combat.set_style(UNIVERSAL, true)
	combat.finish_action()
	await _wait(2)
