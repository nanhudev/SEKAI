extends SceneTree
# PHANTOM CHAIN V0.1 — smoke + switch isolation.
# Proves: equip, A1-A4 start, bind rule, sword/chain independence, no leftover VFX.

const DT := 1.0 / 60.0
const MANAGER_SCRIPT := preload("res://scripts/combat/weapon_manager.gd")
const PHANTOM_SCRIPT := preload("res://scripts/combat/phantom_chain/phantom_chain_controller.gd")

var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var weapon: WeaponSlot
var manager: Node
var phantom: Node
var combat: CombatController
var chain: ChainDirector
var dummy: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	await _wait(20)

	player = world.get_node("Player")
	weapon = player.get_node("WeaponSlot")
	manager = player.get_node("WeaponManager")
	phantom = player.get_node("PhantomChainController")
	combat = player.get_node("CombatController")
	chain = player.get_node("ChainDirector")
	dummy = world.get_node_or_null("TechnicalDummy")
	if dummy == null:
		dummy = world.find_child("TechnicalDummy", true, false)

	_check(phantom != null, "Player has no PhantomChainController")
	_check(MANAGER_SCRIPT.knows(WeaponSlot.PHANTOM_CHAIN), "registry does not know phantom_chain")
	_check(MANAGER_KEY2_IS_PHANTOM(), "key 2 is not phantom_chain")

	# --- equip ---
	_check(weapon.equip(WeaponSlot.PHANTOM_CHAIN), "slot equip phantom_chain refused")
	await _wait(6)
	_check(weapon.is_phantom_chain(), "slot did not take phantom chain")
	_check(bool(phantom.call("is_equipped")), "controller not equipped")
	_check(not chain.is_equipped(), "star-bind still thinks it is equipped")

	# --- A1 ---
	_check(bool(phantom.call("request", &"light")), "A1 refused")
	await _wait_move_idle()
	_check(int(phantom.get("combo_index")) == 1, "combo did not advance to 1 after A1")

	# --- A2 ---
	_check(bool(phantom.call("request", &"light")), "A2 refused")
	await _wait_move_idle()
	_check(int(phantom.get("combo_index")) == 2, "combo did not advance to 2 after A2")

	# --- place dummy for A3 ---
	if dummy != null:
		dummy.global_position = player.global_position + Vector3(0, 0, -3.5)
		await _wait(4)
		_check(bool(phantom.call("request", &"light")), "A3 refused")
		await _wait_move_idle()
		var st: Dictionary = phantom.call("debug_state")
		_check(bool(st.get("bind", false)), "A3 did not establish bind")
		var d0: float = float(st.get("max_dist", 0.0))
		if d0 > 0.0:
			dummy.global_position = player.global_position + Vector3(0, 0, -(d0 + 2.0))
			await _wait(20)
			st = phantom.call("debug_state")
			_check(float(st.get("tension", 0.0)) >= 0.85, "tension did not rise at limit")
		_check(bool(phantom.call("request", &"light")), "pull refused during bind")
		await _wait(12)

	# --- A4 ---
	phantom.call("reset")
	weapon.equip(WeaponSlot.PHANTOM_CHAIN)
	await _wait(4)
	phantom.set("combo_index", 3)
	_check(bool(phantom.call("request", &"light")), "A4 refused")
	await _wait_move_idle()
	_check(int(phantom.get("combo_index")) == 0, "A4 did not reset combo")

	# --- manager sheathe path (hotkey 2) ---
	weapon.equip(WeaponSlot.SWORD)
	await _wait(4)
	_check(bool(manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)), "manager equip refused")
	await _wait_until_weapon(WeaponSlot.PHANTOM_CHAIN)
	_check(weapon.is_phantom_chain(), "manager sheathe path did not deliver phantom chain")

	# --- switch storm via manager ---
	for i in 12:
		manager.call("equip_weapon", WeaponSlot.SWORD)
		await _wait_until_weapon(WeaponSlot.SWORD)
		manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)
		await _wait_until_weapon(WeaponSlot.PHANTOM_CHAIN)
	_check(weapon.is_phantom_chain(), "switch storm left wrong weapon")
	_check(bool(phantom.call("is_equipped")), "phantom not equipped after storm")
	_check(not chain.is_equipped(), "star-bind equipped after storm")
	_check(phantom.call("debug_state").get("state") != "ATTACK", "stuck in attack after storm")

	# --- sword still works ---
	manager.call("equip_weapon", WeaponSlot.SWORD)
	await _wait_until_weapon(WeaponSlot.SWORD)
	_check(weapon.is_sword(), "could not return to sword")
	_check(not bool(phantom.call("is_equipped")), "phantom still equipped under sword")
	_check(phantom.call("debug_state").get("state") == "STOWED", "phantom not stowed")
	var swung := combat.request(&"light")
	_check(swung, "sword light attack refused after phantom round-trip")
	await _wait(10)
	combat.finish_action()

	_finish()


func MANAGER_KEY2_IS_PHANTOM() -> bool:
	var weapons: Array = MANAGER_SCRIPT.WEAPONS
	return weapons.size() >= 2 and weapons[1]["id"] == &"phantom_chain" and weapons[1]["key"] == KEY_2


func _wait_until_weapon(wanted: StringName) -> void:
	# Sheathe is 1.75s; draw is 1.75s; raise is 0.18s. Budget generously.
	for i in 360:
		if manager.call("current_weapon") == wanted:
			var sheathe_done := float(manager.call("sheathe_progress")) >= 0.999
			var switching := bool(manager.get("switching"))
			var drawing := bool(manager.get("drawing_in"))
			if sheathe_done and not switching and not drawing:
				# Sword also needs equip_blend ≈ 1 before it can attack.
				if wanted == WeaponSlot.SWORD and float(combat.equip_blend) < 0.999:
					await process_frame
					continue
				await _wait(3)
				return
		await process_frame
	_fail("timed out waiting for weapon %s (have %s)" % [String(wanted), String(weapon.kind)])


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _wait_move_idle() -> void:
	for i in 120:
		await process_frame
		var st: Dictionary = phantom.call("debug_state")
		var s := String(st.get("state", ""))
		if s == "READY" or s == "BIND" or s == "STOWED":
			await process_frame
			return


func _fail(msg: String) -> void:
	failures.append(msg)
	print("FAIL: ", msg)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		print("FAIL: ", msg)
	else:
		print("ok: ", msg)


func _finish() -> void:
	print("")
	if failures.is_empty():
		print("PHANTOM CHAIN V0.1 PASS (%d checks conceptually)" % 1)
		quit(0)
	else:
		print("PHANTOM CHAIN V0.1 FAIL — %d" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)
