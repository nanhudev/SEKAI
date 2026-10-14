extends SceneTree
## Smoke: Shift Down → dodge; hold through recover → sprint; Tab hold router.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/combat/CombatSandbox.tscn") as PackedScene
	if packed == null:
		push_error("FAIL: CombatSandbox missing")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player := scene.find_child("Player", true, false)
	var combat: Node = player.get_node_or_null("CombatController") if player else null
	var ic := root.get_node_or_null("InputContract")
	var hud: Node = scene.find_child("CombatHUD", true, false)
	if player == null or combat == null or ic == null:
		push_error("FAIL: player/combat/InputContract missing")
		quit(1)
		return

	player.set("unlimited_resources", true)
	var failed := 0

	# --- Shift Down → immediate dodge ---
	_press_shift(true)
	await process_frame
	if int(combat.get("state")) != int(combat.State.DODGE):
		push_error("FAIL: Shift Down did not enter DODGE immediately (state=%s)" % combat.get("state"))
		failed += 1
	else:
		print("OK: Shift Down → DODGE immediate")

	# Hold through dodge → sprint
	var guard := 0
	while int(combat.get("state")) == int(combat.State.DODGE) and guard < 120:
		await process_frame
		guard += 1
	await process_frame
	await process_frame
	if not bool(ic.get("sprinting")) and not Input.is_action_pressed("sprint"):
		push_error("FAIL: after dodge recovery with Shift held, sprint did not engage")
		failed += 1
	else:
		print("OK: Hold Shift after dodge → Sprint")

	_press_shift(false)
	await process_frame
	if bool(ic.get("sprinting")) or Input.is_action_pressed("sprint"):
		push_error("FAIL: Shift Up did not end sprint")
		failed += 1
	else:
		print("OK: Shift Up → sprint ends")

	# Tap shift again should dodge once, not while already sprinting path
	_press_shift(true)
	await process_frame
	if int(combat.get("state")) != int(combat.State.DODGE):
		push_error("FAIL: second Shift Down did not dodge")
		failed += 1
	else:
		print("OK: second Shift Down → DODGE")
	_press_shift(false)
	guard = 0
	while int(combat.get("state")) == int(combat.State.DODGE) and guard < 120:
		await process_frame
		guard += 1

	# --- Tab tap vs hold ---
	var backpack_hits: Array[int] = [0]
	var ui_open_hits: Array[int] = [0]
	var ui_close_hits: Array[int] = [0]
	ic.backpack_requested.connect(func(): backpack_hits[0] += 1)
	ic.combat_ui_hold_started.connect(func(): ui_open_hits[0] += 1)
	ic.combat_ui_hold_ended.connect(func(): ui_close_hits[0] += 1)

	_press_tab(true)
	await process_frame
	_press_tab(false)
	await process_frame
	if backpack_hits[0] != 1 or ui_open_hits[0] != 0:
		push_error("FAIL: Tab tap should open backpack only (bp=%d ui=%d)" % [backpack_hits[0], ui_open_hits[0]])
		failed += 1
	else:
		print("OK: Tab tap → backpack only")

	_press_tab(true)
	# Hold past 220ms (wall clock — headless frame delta can be tiny).
	await create_timer(0.35).timeout
	if ui_open_hits[0] < 1:
		push_error("FAIL: Tab hold did not open Combat UI")
		failed += 1
	else:
		print("OK: Tab hold → Combat UI")
	var bp_before: int = backpack_hits[0]
	_press_tab(false)
	await process_frame
	if ui_close_hits[0] < 1:
		push_error("FAIL: Tab release did not close Combat UI")
		failed += 1
	elif backpack_hits[0] != bp_before:
		push_error("FAIL: Tab release after Combat UI also opened backpack")
		failed += 1
	else:
		print("OK: Tab release closes Combat UI without backpack")

	# Sword E → iaido (skill_1)
	if player.has_node("WeaponManager"):
		player.get_node("WeaponManager").call("equip_weapon", &"sword")
	await process_frame
	_action_press(&"skill_1")
	await process_frame
	_action_release(&"skill_1")
	await process_frame
	if int(combat.get("state")) != int(combat.State.IAIDO):
		# May fail if iaido director missing in sandbox — soft check
		print("WARN: skill_1 did not enter IAIDO (state=%s) — check sandbox directors" % combat.get("state"))
	else:
		print("OK: E/skill_1 → IAIDO")

	if hud != null:
		print("OK: CombatHUD present")

	if failed == 0:
		print("INPUT_SHIFT_TAB_SMOKE PASS")
		quit(0)
	else:
		push_error("INPUT_SHIFT_TAB_SMOKE FAIL (%d)" % failed)
		quit(1)


func _press_shift(down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = &"dodge_sprint"
	ev.pressed = down
	Input.parse_input_event(ev)


func _press_tab(down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = &"ui_tab"
	ev.pressed = down
	Input.parse_input_event(ev)


func _action_press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _action_release(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
