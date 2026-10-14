extends SceneTree
## Headless INPUT CONTRACT V0.1 checks — bindings + Shift/Tab routers exist.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _expect_key(&"skill_1", KEY_E, "E = skill_1")
	failed += _expect_key(&"skill_2", KEY_X, "X = skill_2")
	failed += _expect_key(&"skill_3", KEY_C, "C = skill_3")
	failed += _expect_key(&"ultimate", KEY_V, "V = ultimate")
	failed += _expect_key(&"iaido", KEY_E, "iaido adapter on E")
	failed += _expect_key(&"heavy_attack", KEY_X, "heavy adapter on X")
	failed += _expect_key(&"interact", KEY_F, "F = interact")
	failed += _expect_key(&"jump", KEY_SPACE, "Space = jump")
	failed += _expect_key(&"crouch", KEY_CTRL, "Ctrl = crouch")
	failed += _expect_key(&"dodge_sprint", KEY_SHIFT, "Shift = dodge_sprint")
	failed += _expect_key(&"ui_tab", KEY_TAB, "Tab = ui_tab")
	failed += _expect_key(&"weapon_1", KEY_1, "1 = weapon_1")
	failed += _expect_key(&"weapon_2", KEY_2, "2 = weapon_2")
	failed += _expect_key(&"weapon_3", KEY_3, "3 = weapon_3")
	failed += _expect_mouse(&"light_attack", MOUSE_BUTTON_LEFT, "LMB = light_attack")
	failed += _expect_mouse(&"block", MOUSE_BUTTON_RIGHT, "RMB = block")

	# Sprint must not be a physical Shift binding.
	for ev in InputMap.action_get_events(&"sprint"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SHIFT:
			push_error("FAIL: sprint still physically bound to Shift")
			failed += 1

	# Dodge must not be physically bound (InputContract fires it).
	for ev in InputMap.action_get_events(&"dodge"):
		if ev is InputEventKey:
			push_error("FAIL: dodge still has physical key %s" % OS.get_keycode_string(
				(ev as InputEventKey).physical_keycode
			))
			failed += 1

	# R must not be claimed by contract combat actions.
	for action in [&"skill_1", &"skill_2", &"skill_3", &"ultimate", &"interact", &"parry"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_R:
				push_error("FAIL: contract action %s claims reserved R" % action)
				failed += 1

	var ic := root.get_node_or_null("InputContract")
	if ic == null:
		push_error("FAIL: InputContract autoload missing")
		failed += 1
	else:
		print("OK: InputContract autoload present")

	if failed == 0:
		print("INPUT_CONTRACT_V01 PASS")
		quit(0)
	else:
		push_error("INPUT_CONTRACT_V01 FAIL (%d)" % failed)
		quit(1)


func _expect_key(action: StringName, key: Key, label: String) -> int:
	if not InputMap.has_action(action):
		push_error("FAIL: %s — action missing" % label)
		return 1
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			print("OK: %s" % label)
			return 0
	push_error("FAIL: %s — expected key %s" % [label, OS.get_keycode_string(key)])
	return 1


func _expect_mouse(action: StringName, button: MouseButton, label: String) -> int:
	if not InputMap.has_action(action):
		push_error("FAIL: %s — action missing" % label)
		return 1
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button:
			print("OK: %s" % label)
			return 0
	push_error("FAIL: %s — expected mouse button" % label)
	return 1
