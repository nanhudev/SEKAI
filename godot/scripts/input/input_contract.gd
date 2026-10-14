extends Node
## SEKAI Input Contract V0.1 — single owner of semantic action bindings.
##
## PHYSICAL INPUT → SEMANTIC ACTION → GAMEPLAY FUNCTION.
## Gameplay scripts should read actions (skill_1, interact, …), not KEY_*.
##
## Shift: DOWN fires Dodge immediately; if still held after dodge recovery → Sprint.
## Tab: tap (<220ms) → Backpack; hold (≥220ms) → Combat UI; release closes Combat UI
## without opening Backpack.

signal backpack_requested
signal combat_ui_hold_started
signal combat_ui_hold_ended
signal crouch_changed(active: bool)

const TAB_HOLD_SEC := 0.22
const PLAYER_GROUP := &"player"
const _HoldTracker := preload("res://scripts/input/input_hold_tracker.gd")

## DEVELOPMENT: set true only while verifying a migration alias. Default OFF so
## players never get two keys for one skill.
const ENABLE_LEGACY_ALIASES := false

enum ShiftPhase { IDLE, DODGE_ARMED, SPRINTING }

var sprinting := false
var crouching := false

var _shift_phase: int = ShiftPhase.IDLE
var _shift_held := false
var _dodge_fired_this_hold := false

var _tab: RefCounted = null
var _combat_ui_open := false
var _combat: Node = null


func _ready() -> void:
	_tab = _HoldTracker.new()
	_tab.hold_threshold_sec = TAB_HOLD_SEC
	_install_bindings()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(true)
	# Re-resolve combat when scenes change.
	if get_tree() != null:
		get_tree().node_added.connect(_on_node_added)


func is_sprint_active() -> bool:
	return sprinting


func is_crouch_active() -> bool:
	return crouching


func is_combat_ui_open() -> bool:
	return _combat_ui_open


# ---------------------------------------------------------------- bindings

func _install_bindings() -> void:
	# Movement
	_bind_key(&"move_forward", KEY_W)
	_bind_key(&"move_back", KEY_S)
	_bind_key(&"move_left", KEY_A)
	_bind_key(&"move_right", KEY_D)
	_bind_key(&"jump", KEY_SPACE)
	_bind_key(&"crouch", KEY_CTRL)
	# Walk was on V; V is now Ultimate. Alt keeps a quiet walk pace for labs.
	_bind_key(&"walk", KEY_ALT)

	# Shift owns dodge→sprint. dodge/sprint actions exist for gameplay reads but
	# are NOT physically bound to Shift — this node drives them.
	_ensure_action(&"dodge")
	_ensure_action(&"sprint")
	_clear_action_events(&"dodge")
	_clear_action_events(&"sprint")
	_bind_key(&"dodge_sprint", KEY_SHIFT)

	# Combat semantics (reuse existing names where gameplay already listens)
	_bind_mouse(&"light_attack", MOUSE_BUTTON_LEFT)
	_bind_mouse(&"attack_primary", MOUSE_BUTTON_LEFT)
	_bind_mouse(&"block", MOUSE_BUTTON_RIGHT)
	_bind_mouse(&"parry", MOUSE_BUTTON_RIGHT)

	_bind_key_exclusive(&"skill_1", KEY_E)
	_bind_key_exclusive(&"skill_2", KEY_X)
	_bind_key_exclusive(&"skill_3", KEY_C)
	_bind_key_exclusive(&"ultimate", KEY_V)

	# Adapters: existing gameplay still reads these action names.
	# Sword: skill_1/E → iaido. Do NOT alias style_skill_1 to E — that would
	# steal Iaido into trigger_skill(0). ChainDirector listens to skill_1/skill_3
	# directly for hook/lock. F3–F5 remain lab-only style signatures.
	_bind_key_exclusive(&"iaido", KEY_E)
	_bind_key_exclusive(&"heavy_attack", KEY_X) # former Hold F → Skill 2
	_bind_key_exclusive(&"style_skill_1", KEY_F3)
	_bind_key_exclusive(&"style_skill_2", KEY_F4)
	_bind_key_exclusive(&"style_skill_3", KEY_F5)

	# World
	_bind_key_exclusive(&"interact", KEY_F)

	# UI
	_bind_key_exclusive(&"ui_tab", KEY_TAB)

	# Development quick switch (keep)
	_bind_key(&"weapon_1", KEY_1)
	_bind_key(&"weapon_2", KEY_2)
	_bind_key(&"weapon_3", KEY_3)
	_bind_key(&"weapon_slot_1", KEY_1)
	_bind_key(&"weapon_slot_2", KEY_2)
	_bind_key(&"weapon_slot_3", KEY_3)

	# Magic — relocated off contract keys. Not new gameplay; input only.
	_bind_key_exclusive(&"cast_selected", KEY_Q) # was E
	_bind_key(&"fire_cast", KEY_Z)
	_bind_key_exclusive(&"frost_cast", KEY_G) # was R (R reserved / draw_sword)
	_bind_key_exclusive(&"wind_cast", KEY_B) # was C

	# Inspect stays off-contract
	_bind_key(&"inspect", KEY_U)
	_bind_mouse(&"inspect", MOUSE_BUTTON_XBUTTON2)

	# R stays RESERVED in the contract. draw_sword may still bind R elsewhere
	# as a temporary world/story control — do not assign new combat to R here.

	if ENABLE_LEGACY_ALIASES:
		_bind_key(&"iaido", KEY_I)
		_bind_key(&"heavy_attack", KEY_F)
		_bind_key(&"interact", KEY_E)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _clear_action_events(action: StringName) -> void:
	_ensure_action(action)
	for ev in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, ev)


func _bind_key(action: StringName, key: Key) -> void:
	_ensure_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _bind_key_exclusive(action: StringName, key: Key) -> void:
	_clear_action_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	_ensure_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button:
			return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _alias_action(alias: StringName, source: StringName) -> void:
	## Copy physical events from source onto alias (exclusive).
	_clear_action_events(alias)
	if not InputMap.has_action(source):
		return
	for ev in InputMap.action_get_events(source):
		InputMap.action_add_event(alias, ev.duplicate())


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	# Use _input (not unhandled): Tab/Shift must run even if a child later
	# marks the event handled. Handlers are idempotent per edge via phase flags.
	_handle_shift(event)
	_handle_tab(event)
	_handle_crouch(event)


func _handle_shift(event: InputEvent) -> void:
	if not event.is_action("dodge_sprint"):
		return
	if event.is_action_pressed("dodge_sprint") and not event.is_echo():
		_on_shift_down()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("dodge_sprint"):
		_on_shift_up()
		get_viewport().set_input_as_handled()


func _on_shift_down() -> void:
	_shift_held = true
	# Already sprinting from this hold — never re-fire dodge.
	if sprinting or _shift_phase == ShiftPhase.SPRINTING:
		return
	_dodge_fired_this_hold = true
	_shift_phase = ShiftPhase.DODGE_ARMED
	var combat := _resolve_combat()
	if combat != null and combat.has_method("request"):
		combat.request(&"dodge")
	# If dodge did not enter DODGE (no stamina / refused while idle), Hold still
	# means the player wants mobility → sprint without waiting.
	if combat != null and int(combat.get("state")) != int(combat.State.DODGE):
		if int(combat.get("state")) == int(combat.State.IDLE):
			_begin_sprint()


func _on_shift_up() -> void:
	_shift_held = false
	_dodge_fired_this_hold = false
	_shift_phase = ShiftPhase.IDLE
	_end_sprint()


func _begin_sprint() -> void:
	if sprinting:
		return
	if not _shift_held:
		return
	sprinting = true
	_shift_phase = ShiftPhase.SPRINTING
	if not Input.is_action_pressed("sprint"):
		Input.action_press("sprint")


func _end_sprint() -> void:
	if not sprinting and not Input.is_action_pressed("sprint"):
		return
	sprinting = false
	if Input.is_action_pressed("sprint"):
		Input.action_release("sprint")


func _handle_tab(event: InputEvent) -> void:
	if not event.is_action("ui_tab"):
		return
	if event.is_action_pressed("ui_tab") and not event.is_echo():
		_tab.begin()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ui_tab"):
		var result: Dictionary = _tab.end()
		if _combat_ui_open:
			_combat_ui_open = false
			combat_ui_hold_ended.emit()
		elif result.get("was_tap", false):
			backpack_requested.emit()
		get_viewport().set_input_as_handled()


func _handle_crouch(event: InputEvent) -> void:
	if not event.is_action("crouch"):
		return
	if event.is_action_pressed("crouch") and not event.is_echo():
		crouching = true
		crouch_changed.emit(true)
	elif event.is_action_released("crouch"):
		crouching = false
		crouch_changed.emit(false)


func _process(delta: float) -> void:
	_tick_shift_sprint()
	_tick_tab_hold(delta)


func _tick_shift_sprint() -> void:
	if not _shift_held or sprinting:
		return
	var combat := _resolve_combat()
	if combat == null:
		# No combat node (title / menu): Hold Shift still sprints for movement-only scenes.
		if _dodge_fired_this_hold:
			_begin_sprint()
		return
	var state: int = int(combat.get("state"))
	if state == int(combat.State.DODGE):
		return
	# After a completed dodge (or idle with hold intent), enter sprint.
	if state == int(combat.State.IDLE) or state == int(combat.State.BLOCK):
		if _dodge_fired_this_hold:
			_begin_sprint()


func _tick_tab_hold(delta: float) -> void:
	if not _tab.pressed or _combat_ui_open:
		return
	if _tab.tick(delta):
		_combat_ui_open = true
		combat_ui_hold_started.emit()


func _resolve_combat() -> Node:
	if _combat != null and is_instance_valid(_combat):
		return _combat
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group(PLAYER_GROUP)
	for node in players:
		var c := node.get_node_or_null("CombatController")
		if c != null:
			_combat = c
			if not c.state_changed.is_connected(_on_combat_state_changed):
				c.state_changed.connect(_on_combat_state_changed)
			return _combat
	return null


func _on_combat_state_changed(previous: int, current: int) -> void:
	var combat := _resolve_combat()
	if combat == null:
		return
	# Dodge recovery while Shift still held → Sprint. One dodge per Shift Down.
	if previous == int(combat.State.DODGE) and current != int(combat.State.DODGE):
		if _shift_held:
			_begin_sprint()


func _on_node_added(node: Node) -> void:
	if node.is_in_group(PLAYER_GROUP) or node.name == &"CombatController":
		_combat = null
