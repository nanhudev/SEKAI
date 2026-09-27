extends SceneTree
# Guard → Perfect Guard (截锋) → Riposte loop check.
#
# This is the loop the whole sword system is judged on: you must be able to
# read an attack, cut its line, and answer inside a real window. It also checks
# the opposite case — holding Guard forever must not be a perfect guard.

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

	await _verify_perfect_guard_opens_riposte()
	await _verify_riposte_window()
	await _verify_held_guard_is_not_perfect()
	await _verify_glint_reaches_the_next_light()

	if failures.is_empty():
		print("PASS: guard · perfect guard · riposte loop with readable windows")
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


func _verify_perfect_guard_opens_riposte() -> void:
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	combat.finish_action()
	await physics_frame
	var before := combat.perfect_guard_count
	combat.set_state(CombatController.State.BLOCK)
	await _strike_player()
	_check(combat.perfect_guard_count == before + 1, "Guard pressed just before the hit did not perfect-guard")
	_check(combat.state == CombatController.State.PARRY, "Perfect guard did not enter the parry beat (state=%s)" % combat.state)
	_check(combat.edge_glint, "Perfect guard did not light the edge")
	_check(combat.riposte_until > Time.get_ticks_msec() / 1000.0, "Riposte window did not open")
	_check(dummy.state == dummy.State.STAGGER, "The interrupted enemy attack was not stopped")
	combat.finish_action()
	await physics_frame


func _verify_riposte_window() -> void:
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	combat.finish_action()
	await physics_frame
	combat.set_state(CombatController.State.BLOCK)
	await _strike_player()
	var expected: StringName = combat.moveset.guard.riposte_id
	combat.request(&"light")
	_check(combat.state == CombatController.State.RIPOSTE, "Light inside the riposte window did not start a riposte")
	_check(combat.active_move_id == expected, "Riposte used %s instead of %s" % [combat.active_move_id, expected])
	_check(combat.hitbox.poise_damage > 26.0, "Riposte carries no real posture damage (%.0f)" % combat.hitbox.poise_damage)
	combat.finish_action()
	await physics_frame


func _verify_held_guard_is_not_perfect() -> void:
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	combat.finish_action()
	player.set("health", 100.0)
	player.unlimited_resources = false
	player.set("stamina", 100.0)
	await physics_frame
	var before := combat.perfect_guard_count
	combat.set_state(CombatController.State.BLOCK)
	# Hold Guard well past the window, then eat the same attack.
	await _wait(16)
	await _strike_player()
	_check(combat.perfect_guard_count == before, "Holding Guard forever still produced a perfect guard")
	_check(combat.guard_recoil > 0.0, "A normal block produced no weapon recoil")
	_check(float(player.get("stamina")) < 100.0, "A normal block cost no stamina")
	_check(combat.state == CombatController.State.BLOCK, "A normal block knocked the player out of guard")
	# The attack must still have been mitigated, not ignored.
	_check(float(player.get("health")) > 100.0 - 12.0, "Guard did not reduce the incoming damage")
	player.unlimited_resources = true
	combat.finish_action()
	await physics_frame


func _verify_glint_reaches_the_next_light() -> void:
	combat.set_style(SwordMovesetLibrary.STYLE_HIDDEN_EDGE, true)
	combat.finish_action()
	await physics_frame
	combat.set_state(CombatController.State.BLOCK)
	await _strike_player()
	_check(combat.edge_glint, "藏锋 perfect guard did not light the edge")
	# Let the riposte window expire: the reward must survive as a lit edge on
	# the next 一文字, not force the player into the answer.
	var waited := 0.0
	while combat.edge_glint and waited < 1.2:
		await physics_frame
		waited += 1.0 / 60.0
		if Time.get_ticks_msec() / 1000.0 > combat.riposte_until:
			break
	combat.finish_action()
	await physics_frame
	if Time.get_ticks_msec() / 1000.0 <= combat.riposte_until:
		await _wait(4)
	combat.request(&"light")
	var move := combat.moveset.get_move(&"he_ichimonji")
	_check(combat.active_move_id == &"he_ichimonji", "藏锋 light did not open with 一文字")
	_check(
		combat.effective_startup() <= move.startup * 0.76,
		"截锋 reward did not reach the next 一文字 (startup %.3f vs %.3f)" % [combat.effective_startup(), move.startup]
	)
	_check(combat.hitbox.poise_damage >= move.poise_damage * 1.4, "截锋 reward did not raise posture damage")
	combat.finish_action()
	await physics_frame
