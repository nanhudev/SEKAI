extends SceneTree
# Sword style check: 藏锋流 (Hidden Edge) and 回风式 (Flowing Wind).
#
# The acceptance question is not "does the number go up" but "is this a
# different way of thinking about the fight":
#   藏锋 waits, 回风 moves. Both must be visible in the timing data, not only in
#   a damage table.

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

	await _verify_style_identity()
	await _verify_sheath_rhythm()
	await _verify_sokyu_enhance()
	await _verify_tsubame_followup()
	await _verify_danzhang_interrupt()
	await _verify_flowing_wind_on_hit()

	if failures.is_empty():
		print("PASS: hidden-edge and flowing-wind differ from the universal layer in rhythm, not in damage")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _verify_style_identity() -> void:
	var hidden := SwordMovesetLibrary.hidden_edge()
	var flow := SwordMovesetLibrary.flowing_wind()
	# Three styles, three sentences.
	_check(hidden.light_chain.size() == 3, "藏锋 light chain is not three cuts")
	_check(flow.light_chain.size() == 4, "回风 light chain is not four cuts")
	_check(hidden.get_move(&"he_ichimonji").startup < 0.07, "一文字 is not an extreme-startup draw")
	_check(hidden.get_move(&"he_dansui").anticipation_power > 4.0, "断水 has no held stillness before the cut")
	_check(
		flow.get_move(&"fw_l1").steer > hidden.get_move(&"he_ichimonji").steer * 2.0,
		"回风 does not steer through its attacks more than 藏锋 does"
	)
	_check(flow.flow_on_hit_recovery < 0.7, "回风 does not shorten recovery on contact")
	_check(flow.combo_window > hidden.combo_window, "回风 does not sustain the chain longer than 藏锋")
	_check(hidden.pose_stiffness > flow.pose_stiffness, "藏锋 is not tighter than 回风")
	# Switching is a real action, not an instant costume change.
	combat.set_style(UNIVERSAL, true)
	combat.request(&"light")
	await physics_frame
	_check(not combat.set_style(HIDDEN_EDGE, false), "Style switched in the middle of a swing")
	combat.finish_action()
	await physics_frame
	_check(combat.set_style(HIDDEN_EDGE, false), "Style did not switch while standing still")
	_check(combat.moveset.style_id == HIDDEN_EDGE, "Style id did not update")


func _verify_sheath_rhythm() -> void:
	combat.set_style(HIDDEN_EDGE, true)
	combat.finish_action()
	_check(combat.sheath_amount < 0.2, "藏锋 starts the fight already sheathed")
	# Waiting is the mechanic: standing still long enough returns the blade.
	var frames := 0
	while not combat.is_sheathed() and frames < 200:
		await physics_frame
		frames += 1
	_check(combat.is_sheathed(), "The blade never returned to the sheath while idle")
	# A sheathed draw is stronger. Spamming Light never gets this.
	combat.request(&"light")
	var move := combat.moveset.get_move(&"he_ichimonji")
	_check(combat.active_move_id == &"he_ichimonji", "藏锋 did not open with 一文字")
	_check(
		combat.effective_startup() < move.startup,
		"纳刀拔刀 did not shorten the draw (%.3f vs %.3f)" % [combat.effective_startup(), move.startup]
	)
	_check(combat.hitbox.poise_damage > move.poise_damage, "纳刀拔刀 did not raise posture damage")
	combat.finish_action()
	await _wait(2)
	# Chaining immediately must lose the bonus: the blade never got back in.
	combat.request(&"light")
	await _wait(8)
	combat.request(&"light")
	_check(combat.combo_index == 2, "藏锋 second cut did not chain (index=%d)" % combat.combo_index)
	_check(combat.sheath_amount < 0.2, "Sheathing happened in the middle of a chain")
	combat.finish_action()
	await _wait(2)


func _verify_sokyu_enhance() -> void:
	combat.set_style(HIDDEN_EDGE, true)
	combat.reset_skill_cooldowns()
	combat.finish_action()
	await physics_frame
	var base_startup: float = combat.moveset.get_move(&"he_ichimonji").startup
	_check(combat.trigger_skill(0), "纳息 was rejected")
	_check(combat.active_move_id == &"he_sokyu", "纳息 did not play its own settle")
	var frames := 0
	while combat.state == CombatController.State.SKILL and frames < 300:
		await physics_frame
		frames += 1
	_check(combat.enhance_left > 6.0, "纳息 did not enter the enhance state")
	combat.request(&"light")
	_check(combat.effective_startup() < base_startup, "纳息 did not change the 一文字 rhythm")
	_check(combat.hitbox.poise_damage > combat.moveset.get_move(&"he_ichimonji").poise_damage, "纳息 did not raise first-hit posture")
	combat.finish_action()
	combat.skill_cooldowns.clear()
	await _wait(2)


func _verify_tsubame_followup() -> void:
	combat.set_style(HIDDEN_EDGE, true)
	combat.reset_skill_cooldowns()
	combat.finish_action()
	await physics_frame
	combat.trigger_skill(1)
	_check(combat.active_move_id == &"he_tsubame_1", "燕返 first cut did not start")
	var frames := 0
	while not combat.move_hit and frames < 60:
		await physics_frame
		frames += 1
	_check(combat.move_hit, "燕返 first cut never connected")
	_check(combat.pending_followup_id == &"he_tsubame_2", "燕返 opened no follow-up")
	frames = 0
	while combat.state != CombatController.State.IDLE and frames < 200:
		await physics_frame
		frames += 1
	_check(combat.state == CombatController.State.IDLE, "燕返 first cut never ended")
	# The window must survive the end of the first cut.
	combat.request(&"light")
	_check(combat.active_move_id == &"he_tsubame_2", "燕返 second cut did not fire inside the window")
	_check(combat.active_move_id != &"he_ichimonji", "燕返 window was stolen by the light chain")
	combat.finish_action()
	await _wait(2)
	# A whiff must not hand out the second cut for free.
	combat.reset_skill_cooldowns()
	player.global_position = Vector3(0, 1.15, 14.0)
	await physics_frame
	combat.trigger_skill(1)
	frames = 0
	while combat.state != CombatController.State.IDLE and frames < 200:
		await physics_frame
		frames += 1
	_check(combat.pending_followup_id == &"", "燕返 opened a follow-up after a whiff")
	player.global_position = Vector3(0, 1.15, -0.6)
	await _wait(2)


func _verify_danzhang_interrupt() -> void:
	combat.set_style(HIDDEN_EDGE, true)
	combat.reset_skill_cooldowns()
	combat.finish_action()
	dummy.call("reset_dummy")
	dummy.set("attack_cooldown", 999.0)
	await physics_frame
	dummy.call("force_attack", 1)
	await _wait(4)
	_check(dummy.call("is_telegraphing"), "The heavy attack gave no readable wind-up window")
	combat.trigger_skill(2)
	_check(combat.active_move_id == &"he_danzhang", "断章 did not start")
	var frames := 0
	while not combat.move_hit and frames < 60:
		await physics_frame
		frames += 1
	_check(combat.move_hit, "断章 never connected")
	_check(dummy.state == dummy.State.STAGGER, "断章 did not stop the enemy action")
	_check(not dummy.get("attack_open"), "断章 left the enemy attack running")
	_check(dummy.get("last_interrupt") > 0.0, "断章 did not register as an interrupt")
	combat.finish_action()
	dummy.set("attack_cooldown", 999.0)
	await _wait(2)


func _verify_flowing_wind_on_hit() -> void:
	combat.set_style(FLOWING_WIND, true)
	combat.finish_action()
	await physics_frame
	# A whiff keeps the full recovery.
	combat.request(&"light")
	await physics_frame
	_check(not combat.move_hit, "The very first frame already counted as a hit")
	var miss_scale := combat.recovery_scale()
	combat.finish_action()
	await _wait(2)
	# A connected hit shortens it: the style flows only while you land hits.
	combat.request(&"light")
	var frames := 0
	while not combat.move_hit and frames < 40:
		await physics_frame
		frames += 1
	_check(combat.move_hit, "回风 light never connected")
	var hit_scale := combat.recovery_scale()
	_check(hit_scale < miss_scale * 0.75, "回风 did not shorten recovery on contact (%.2f vs %.2f)" % [hit_scale, miss_scale])
	var connected_end := combat._move_end_time()
	var whiff_move := combat.moveset.get_move(&"fw_l1")
	var whiff_end := whiff_move.total_time()
	_check(
		connected_end < whiff_end * 0.85,
		"回风 connected cut still takes %.2fs (whiff %.2fs)" % [connected_end, whiff_end]
	)
	combat.finish_action()
	await _wait(2)
