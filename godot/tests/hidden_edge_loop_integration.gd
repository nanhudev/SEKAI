extends SceneTree
# 藏锋 (Hidden Edge) round-loop check — P2 is polish, not new moves.
#
# The brief was explicit: 藏锋 already has enough techniques (一文字 / 返刃 / 落月 /
# 断水 / 截锋 / 纳息 / 燕返 / 断章 / 聚合斩 / 无明一刻). What it did not have was a
# closed loop BETWEEN them. The loop this test pins is:
#
#   hold the moment  →  归鞘  →  拔刀一文字 (faster, heavier)  →  back to 归鞘
#
# and the change under test is the one thing that lets the loop close mid-fight:
# a perfect guard counts as the moment, so it waives the wait before sheathing.
#
# No new moves are introduced here, and this test asserts that too.

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var failures: Array[String] = []

const HE := SwordMovesetLibrary.STYLE_HIDDEN_EDGE


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


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

	await _verify_no_new_moves_were_added()
	await _verify_sheathing_is_the_loop()
	await _verify_the_sheathed_draw_is_consumed()
	await _verify_a_perfect_guard_waives_the_wait()
	await _verify_sokyu_stacks_on_the_loop()
	await _verify_dansui_is_the_frost_payoff()

	if failures.is_empty():
		print("PASS: 藏锋 · the sheath → draw loop closes, a perfect guard counts as the moment, and no new moves were added")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _reset() -> void:
	combat.finish_action()
	combat.set_style(HE, true)
	combat.reset_skill_cooldowns()
	combat.reset_flow()
	combat.sheath_amount = 0.0
	combat.idle_time = 0.0
	combat.guard_recoil = 0.0
	dummy.call("reset_dummy")
	dummy.set("attack_cooldown", 999.0)


func _strike_player() -> void:
	var enemy_hitbox: CombatHitbox = dummy.get_node("AttackHitbox")
	enemy_hitbox.set_active(true)
	await physics_frame
	await physics_frame
	enemy_hitbox.set_active(false)


# Frames of standing still until the blade is at least 82% home.
func _frames_to_sheathe() -> int:
	for frame in 240:
		if combat.is_sheathed():
			return frame
		await physics_frame
	return 240


# Press Light on a FRESH chain and go through the real input path: _begin_move()
# zeroes sheath_amount, so the sheathed-draw bonus only exists on combo_index 1
# and only for a move started the way the player starts one.
func _press_light() -> Dictionary:
	combat.finish_action()
	combat.combo_index = 0
	combat.chain_active = false
	combat.chain_expires_at = 0.0
	combat.request(&"light")
	return {
		"startup": combat.effective_startup(),
		"poise": float(combat.hitbox.poise_damage),
		"id": combat.active_move_id,
	}


# --- the constraint: polish, not content ---------------------------------

func _verify_no_new_moves_were_added() -> void:
	combat.finish_action()
	combat.set_style(HE, true)
	var own := [
		&"he_ichimonji", &"he_kaeshi", &"he_rakugatsu", &"he_dansui",
		&"he_sokyu", &"he_tsubame_1", &"he_tsubame_2", &"he_danzhang",
	]
	var moves: Dictionary = combat.moveset.moves
	for move_id in moves:
		# The uni_* entries are the Universal moves _resolve_shared() pulls in so
		# a style can share the sprint / retreat / riposte cut. They are not 藏锋
		# content and must not be counted as such.
		if String(move_id).begins_with("uni_"):
			continue
		_check(
			own.has(move_id),
			"P2 added a new 藏锋 move (%s): the brief said polish the loop, not add techniques" % move_id
		)
	_check(own.size() == 8, "藏锋's own move list changed size")
	_check(combat.moveset.skills.size() == 3, "The skill list changed size in a polish round")
	_check(combat.moveset.signature_id == &"iaido", "聚合斩 is no longer the signature")
	_check(combat.moveset.ultimate_id == &"moment_of_no_moon", "无明一刻 is no longer the ultimate")
	_check(combat.moveset.light_chain.size() == 3, "The light chain changed size in a polish round")
	_reset()


# --- the loop itself -----------------------------------------------------

func _verify_sheathing_is_the_loop() -> void:
	_reset()
	# Standing still must be the price. If the sheath came for free, 藏锋 would be
	# a style with a buff rather than a style with a decision.
	_check(not combat.is_sheathed(), "藏锋 started with the blade already home")
	var frames := await _frames_to_sheathe()
	var seconds := frames / 60.0
	_check(combat.is_sheathed(), "Standing still never sheathed the blade")

	var expected := combat.moveset.sheath_delay + combat.moveset.sheath_time
	_check(
		seconds >= expected * 0.7,
		"归鞘 came too cheaply: %.2fs vs a designed %.2fs" % [seconds, expected]
	)

	# Drawing from a full sheath must be better, and in the way the style cares
	# about: faster and heavier, not harder.
	var sheathed_shot := _press_light()
	_check(sheathed_shot["id"] == &"he_ichimonji", "Light did not open with 一文字 (got %s)" % sheathed_shot["id"])
	combat.sheath_amount = 0.0
	var bare_shot := _press_light()
	_check(
		sheathed_shot["startup"] < bare_shot["startup"],
		"拔刀 was not faster from a full sheath (%.3f vs %.3f)" % [sheathed_shot["startup"], bare_shot["startup"]]
	)
	_check(
		sheathed_shot["poise"] > bare_shot["poise"],
		"拔刀 did not carry the posture bonus (%.1f vs %.1f)" % [sheathed_shot["poise"], bare_shot["poise"]]
	)
	var sheathed_move: SwordMove = combat.moveset.get_move(&"he_ichimonji")
	_check(
		sheathed_shot["startup"] < bare_shot["startup"] * 0.9,
		"the sheathed bonus barely moved the startup (%.3f vs %.3f)"
		% [sheathed_shot["startup"], bare_shot["startup"]]
	)
	_check(sheathed_move.damage == 26.0, "the sheathed draw changed damage, not handling")
	_reset()


func _verify_the_sheathed_draw_is_consumed() -> void:
	# A loop, not a switch: drawing spends the sheath, so the style has to earn it
	# again. Otherwise 藏锋 is just "sheathe once, be strong forever".
	_reset()
	combat.sheath_amount = 1.0
	_press_light()
	await _wait(2)
	_check(combat.sheath_amount < 0.5, "The sheath survived the draw: the loop has no cycle")
	_reset()


# --- the P2 change -------------------------------------------------------

func _verify_a_perfect_guard_waives_the_wait() -> void:
	_reset()
	_check(
		combat.moveset.guard.parry_sheath_waiver > 0.0,
		"截锋 no longer waives the wait: the loop cannot close mid-fight"
	)
	_check(
		is_zero_approx(SwordMovesetLibrary.universal().guard.parry_sheath_waiver),
		"the sheath waiver leaked out of 藏锋: Universal's parry now re-sheathes for it"
	)

	# Baseline: the wait is real.
	var plain_frames := await _frames_to_sheathe()

	# Now with a fresh 截锋 behind it.
	_reset()
	combat.set_state(CombatController.State.BLOCK)
	var before := combat.perfect_guard_count
	await _strike_player()
	_check(combat.perfect_guard_count == before + 1, "The perfect guard used to test the loop did not land")
	# Drop straight back to neutral, as the player would after the parry beat.
	combat.finish_action()
	var parried_frames := await _frames_to_sheathe()

	_check(
		parried_frames < plain_frames,
		"A perfect guard did not start the sheath sooner (%d frames vs %d)" % [parried_frames, plain_frames]
	)
	# And the difference has to be the DELAY, which is the whole point.
	var saved := (plain_frames - parried_frames) / 60.0
	_check(
		saved >= combat.moveset.sheath_delay * 0.5,
		"截锋 only saved %.2fs of a %.2fs wait: the loop still cannot close in a fight"
		% [saved, combat.moveset.sheath_delay]
	)
	_reset()


func _verify_sokyu_stacks_on_the_loop() -> void:
	# 纳息 already exists and is unchanged. What P2 has to guarantee is that it
	# compounds with the new loop instead of being redundant with it.
	_reset()
	combat.sheath_amount = 1.0
	combat.finish_action()
	# 纳息 is an ENHANCE skill: enter it directly, the same way its button does.
	combat.enhance_left = 8.0
	combat.enhance_skill_id = &"he_sokyu"
	var boosted := await _frames_to_sheathe()

	_reset()
	combat.sheath_amount = 1.0
	combat.finish_action()
	var normal := await _frames_to_sheathe()
	_check(boosted <= normal, "纳息 did not shorten the sheath at all (%d vs %d)" % [boosted, normal])
	_reset()


func _verify_dansui_is_the_frost_payoff() -> void:
	# COMBO 4 belongs to this style: Frosted + 断水 is the Brittle Break. It works
	# without any new code, and P2 must not have broken it.
	_reset()
	var dansui: SwordMove = combat.moveset.get_move(&"he_dansui")
	_check(dansui.poise_damage >= 35.0, "断水 stopped counting as a heavy: COMBO 4 has no payoff")
	_check(dansui.frozen_bonus > 1.0, "断水 no longer rewards a frozen target")

	dummy.call("apply_debug_state", &"frosted")
	var before: float = dummy.health
	dummy.call("_on_hit", {
		"damage": dansui.damage, "poise_damage": dansui.poise_damage,
		"element": &"physical", "impulse": 0.0, "source": player, "target": dummy,
	})
	_check(dummy.state == dummy.State.STAGGER, "断水 on a Frosted target no longer breaks it open")
	_check(dummy.health < before - dansui.damage, "断水 got no bonus from the frost layer")
	_check(float(dummy.get("frost")) == 0.0, "断水 did not consume the frost layer")
	_reset()
