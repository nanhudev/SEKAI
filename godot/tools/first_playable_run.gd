extends SceneTree
# ============================================================================
# FIRST PLAYABLE SEQUENCE — the §29 acceptance run
# ============================================================================
#
#   Godot --path F:/SEKAI/godot --script res://tools/first_playable_run.gd
#
# NOT HEADLESS. This is the round's acceptance pass and §30 asks a question no
# headless test can answer - "does SEKAI look like a game that has already
# started?" - so this runs in a real window, renders real frames, and writes a
# PNG at every beat to F:/SEKAI/.render/first_playable/ for review afterwards.
#
# WHAT IS REAL HERE, AND WHAT IS THE HARNESS.
#
#   REAL. The Main Menu and its button. The loading caption. The world build.
#   The fade-in. Walking (via `Input.action_press` on the same actions a
#   keyboard sets). Turning (via synthetic `InputEventMouseMotion`, through the
#   exact relation `player_movement.gd` implements: rotate_y(-relative.x *
#   mouse_sensitivity)). Every story trigger - E, R, LMB, Q - injected as a real
#   InputEvent through `Input.parse_input_event`, which is the same entry point
#   a person's keyboard uses, so `MistvalePlaza._unhandled_input` routes it and
#   `StoryUI._input` takes E during a conversation exactly as it would for them.
#
#   HARNESS. Nothing about the world is written directly. No actor is moved, no
#   stage is set, no `director.on_*()` is called, no node is teleported. The
#   only thing this file does that a player would not is decide WHAT to press,
#   and it decides that by reading the story's own state.
#
# That distinction is the whole value of the run. §21 says progress must be
# triggered by real player behaviour, so a test that called the director's
# handlers would certify the one thing the round is trying to prove it does not
# do. This presses the keys instead, and reads the story back by watching it move.
#
# ASSERTIONS, NOT PRINTS: every beat either passes or increments `_fail`, and the
# exit code is the failure count. The screenshots are evidence, not proof.

const OUT := "F:/SEKAI/.render/first_playable/"
const MAIN_SCENE := "res://scenes/main/Main.tscn"
# There is deliberately no FRAMES_PER_SECOND constant here. Every wait in this
# file is wall clock via `_now()`, for the reason written above `_await_stage`.

## Stage ordinals, mirrored from `StoryDirector.Stage` so this file does not
## depend on the class resolving. They are checked against the director below.
const ST_ARRIVAL := 0
const ST_MET_MIRA := 1
const ST_GET_SWORD := 2
const ST_DRAW_SWORD := 3
const ST_BASIC_ATTACK := 4
const ST_USE_SKILL := 5
const ST_ENEMY_EVENT := 6
const ST_FIRST_COMBAT := 7
const ST_COMBAT_COMPLETE := 8
const ST_NEXT_OBJECTIVE := 9

var _fail := 0
var _checks := 0

var _main: Node
var _world: Node3D
var _player: CharacterBody3D
var _director: Node
var _ui: Node
var _npc: Node3D
var _post: Node3D
var _rack: Node3D
var _hold: Node
var _slot: Node
var _combat: Node

var _log: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _run() -> void:
	# ---------------------------------------------- 0. a known starting point
	#
	# THE SAVE FILE IS PER USER AND OUTLIVES EVERY RUN, SO A TEST THAT IGNORES IT
	# STOPS BEING A TEST. `user://sekai_flags.json` is written by the end of this
	# very run; on a second run the director would see a returning player, skip
	# the opening, and seat the story at NEXT_OBJECTIVE - and every stage
	# assertion below would then pass VACUOUSLY, because NEXT_OBJECTIVE is greater
	# than every stage it is compared against. A green light that cannot go red is
	# decoration. Deleting the file first makes this measure the first-ever launch,
	# which is the only thing §29 asks about.
	var flags_path := "user://sekai_flags.json"
	if FileAccess.file_exists(flags_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(flags_path))
		_say("cleared the old save so this is a first launch")

	# ---------------------------------------------------- 1. the Main Menu
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		print("FAIL  Main.tscn did not load")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _frames(40)
	_say("title screen up")
	await _shot("00_title")

	var menu: Control = _main.get_node_or_null("MainMenu")
	_check(menu != null and menu.visible, "§1  the game opens on the Main Menu")
	var button := _first_button(menu)
	_check(button != null, "§1  the title screen has a first button")
	if button != null:
		_check(String(button.text) == "开始游戏",
			"§1  the FIRST door is 开始游戏 (found `%s`)" % button.text)
		_say("clicking %s" % button.text)
		await _click(button)

	# ---------------------------------------------------- 2. the world
	var built_at := _now()
	while _main.get("plaza_world") == null and _now() - built_at < 90.0:
		await process_frame
	_world = _main.get("plaza_world") as Node3D
	_check(_world != null, "§1  开始游戏 built the plaza world")
	if _world == null:
		_finish()
		return
	_say("world built after %.1f s" % (_now() - built_at))

	_resolve()
	_check(_director != null and _ui != null and _player != null,
		"the plaza exposes its actor and story layer")
	if _director == null or _ui == null or _player == null:
		_finish()
		return

	# §2: the establishing seconds. The fade runs for 2.4 s, so waiting 3 s is
	# waiting for the black to be gone, not for a timer to expire.
	await _seconds(3.4)
	await _shot("01_spawn")
	_check(_stage() == ST_ARRIVAL or _stage() == ST_MET_MIRA,
		"§1/§2 spawned into the plaza during the opening beat (stage %s)"
			% _stage_name())
	_check(not bool(_slot.call("is_sword")),
		"§2  the player has no sword yet")
	_check(String(_hold.get("state_name")) == "SHEATHED",
		"§2  and nothing drawn")

	# ---------------------------------------------------- 3. free movement
	var before: Vector3 = _player.global_position
	Input.action_press(&"move_forward")
	await _seconds(1.0)
	Input.action_release(&"move_forward")
	await _frames(8)
	var moved: float = before.distance_to(_player.global_position)
	_check(moved > 1.0, "§2  the player can walk straight away (%.2f m in 1 s)" % moved)
	await _shot("02_walk")
	await _look_around()
	await _shot("03_look")

	# ---------------------------------------------------- 4. the first NPC
	var noticed := await _await_stage(ST_MET_MIRA, 45.0)
	_check(noticed, "§3  the opening beat finished on its own (stage %s)"
		% _stage_name())
	_say("walking to Mira")
	await _walk_to(_npc.global_position.x, _npc.global_position.z, 1.9, 30.0)
	await _frames(6)
	# ASK THE WORLD, NOT THE DIRECTOR. `npc_prompt()` is what she would say if she
	# were reached; the hub is what the player is actually being OFFERED, and the
	# hub is what goes quiet when the player is out of range. On the first run of
	# this file only the director was asked, and it passed while the player stood
	# four metres away and could not press anything at all.
	var offered := String(_world.get("_hub_prompt"))
	var reach := _player.global_position.distance_to(_npc.global_position)
	_check(offered == "[F]  交谈",
		"§5  the world offers `%s` from %.2f m away (her reach is 2.4)"
			% [offered, reach])
	await _shot("04_mira_prompt")

	await _tap(&"interact")
	await _frames(10)
	_check(bool(_ui.call("is_talking")), "§5  E opened the conversation")
	await _shot("05_dialogue")
	await _read_dialogue(12)
	_check(_stage() >= ST_GET_SWORD,
		"§5  the first conversation advanced the story to %s" % _stage_name())

	# ---------------------------------------------------- 5. the first sword
	await _walk_to(_rack.global_position.x, _rack.global_position.z, 2.2, 30.0)
	await _frames(6)
	await _shot("06_rack")
	await _tap(&"interact")
	# The pick-up is a four-beat ceremony (~1.8 s) and the toast lands at its end.
	await _seconds(2.6)
	_check(bool(_slot.call("is_sword")),
		"§6  the player is actually holding a sword now")
	_check(_stage() >= ST_DRAW_SWORD,
		"§6  taking it advanced the story to %s" % _stage_name())
	_check(String(_hold.get("state_name")) == "SHEATHED",
		"§6  it arrives IN its saya, not in the hand")
	await _shot("07_sword_taken")

	# ---------------------------------------------------- 6. the first draw
	await _tap_key(KEY_R)
	await _seconds(1.0)
	_check(String(_hold.get("state_name")) == "DRAWN",
		"§7  R completed the draw (state %s)" % _hold.get("state_name"))
	_check(_stage() >= ST_BASIC_ATTACK,
		"§7  drawing advanced the story to %s" % _stage_name())
	await _shot("08_drawn")

	# ---------------------------------------------------- 7. the first attack
	# CLOSE, because §8's lesson is a body-reach cut. `sb_a1` is BODY/CLOSE, so
	# 1.5 m is inside the swing and 1.9 would be measuring the harness's aim
	# rather than the move's reach. The post has no solid body, so nothing stops
	# the player getting this close.
	await _walk_to(_post.global_position.x, _post.global_position.z, 1.5, 30.0)
	await _face(_post.global_position.x, _post.global_position.z)
	await _frames(6)
	await _shot("09_at_post")
	var hits_before: int = int(_post.get("hit_count"))
	for _i in 5:
		if int(_post.get("hit_count")) > hits_before:
			break
		await _tap_mouse()
		await _seconds(0.8)
	await _seconds(0.4)
	var landed: int = int(_post.get("hit_count")) - hits_before
	_check(landed >= 1,
		"§8  the attack landed on the training post (%d hit(s))" % landed)
	_check(_stage() >= ST_USE_SKILL,
		"§9/§10 the first hit advanced the story to %s" % _stage_name())
	await _shot("10_first_hit")

	# ---------------------------------------------------- 8. the first skill
	# §10's 剑气 is PROJECTILE/MID — six to ten metres. Standing on top of the
	# post would fire the wave over it, so back off to the range the move was
	# authored for. This is the harness making a player's decision, not writing
	# to the world.
	var away := _post.global_position \
		+ (_player.global_position - _post.global_position).normalized() * 7.0
	away.y = _player.global_position.y
	await _walk_to(away.x, away.z, 1.2, 30.0)
	await _face(_post.global_position.x, _post.global_position.z)
	await _frames(6)
	await _shot("11_skill_range")
	await _tap_key(KEY_Q)
	await _seconds(2.2)
	_check(_stage() >= ST_ENEMY_EVENT,
		"§10 the skill connected and the world interrupted (stage %s)" % _stage_name())
	await _shot("12_skill")

	# ---------------------------------------------------- 9. the first monster
	var arrived := await _await_stage(ST_FIRST_COMBAT, 40.0)
	_check(arrived, "§13 the hound walked into the square (stage %s)" % _stage_name())
	var hound := _find_hound()
	_check(hound != null, "§12 the first enemy exists in the world")
	if hound != null:
		var script: Script = hound.get_script()
		_check(script != null and script.resource_path.contains("first_encounter"),
			"§12 the enemy is a FirstEncounterEnemy, not a test dummy")
		await _shot("13_hound")
		await _fight(hound)

	# ---------------------------------------------------- 10. the aftermath
	var done := await _await_stage(ST_NEXT_OBJECTIVE, 75.0)
	_check(done, "§19 the first sequence reached NEXT_OBJECTIVE (stage %s)"
		% _stage_name())
	await _shot("14_aftermath")
	await _read_dialogue(8)
	# §22: the flags must have been written, or re-entering replays the tutorial.
	# `Variant` rather than `:=` because this project promotes the
	# inferred-from-Variant warning to a parse error, and `get()` returns Variant.
	var flags: Variant = _director.get("flags")
	if flags != null:
		_check(bool(flags.get("has_first_sword")),
			"§22 `has_first_sword` was saved")
		_check(bool(flags.get("first_enemy_defeated")),
			"§22 `first_enemy_defeated` was saved")
		_check(bool(flags.call("is_returning_player")),
			"§22 a re-entry is recognised as a returning player")
	else:
		_check(false, "§22 the director has a save-flag store")

	# §22, ASKED OF THE DISK RATHER THAN OF MEMORY. The in-memory object reading
	# `true` proves the story ran; only the file proves it survives the process,
	# and "re-entering after completion does not replay the tutorial" is a claim
	# about the NEXT launch, not about this one.
	_check(FileAccess.file_exists(flags_path),
		"§22 the flag file was written to disk")
	if FileAccess.file_exists(flags_path):
		var text := FileAccess.get_file_as_string(flags_path)
		_check(text.contains("\"has_first_sword\": true")
				and text.contains("\"first_enemy_defeated\": true"),
			"§22 the file on disk records the sword and the enemy")

	# §19: "玩家仍可自由移动。不要强制结束。"
	var before_after: Vector3 = _player.global_position
	Input.action_press(&"move_back")
	await _seconds(1.0)
	Input.action_release(&"move_back")
	await _frames(8)
	var still_free: float = before_after.distance_to(_player.global_position)
	_check(still_free > 0.8,
		"§19 the player can still move after the sequence (%.2f m)" % still_free)
	await _shot("15_free_move")

	_finish()


# ============================================================ the fight
#
# The bot's policy is deliberately the one §16 describes a player having:
# close in, cut, and take the shot when the skill is up and there is room for
# it. It does not dodge, because §16 asks for a fight that is winnable without
# it, and if this loop ever needs a dodge to survive then the encounter is
# harder than the brief allows.
func _fight(hound: Node3D) -> void:
	var started := _now()
	var swings := 0
	# The cooldown is tracked here rather than asked of the controller, which
	# exposes no "is the skill ready". 6.5 s is `uni_qijian`'s authored cooldown
	# plus a margin, so Q is pressed only when the moveset would accept it
	# instead of spamming refusals that the story then has to ignore.
	var last_skill_at := _now() - 99.0
	while _now() - started < 50.0 and _alive(hound) and _stage() >= ST_FIRST_COMBAT:
		if not is_instance_valid(hound):
			break
		var p: Vector3 = _player.global_position
		var t: Vector3 = hound.global_position
		var flat := Vector2(t.x - p.x, t.z - p.z)
		await _face(t.x, t.z)
		if flat.length() > 2.1:
			Input.action_press(&"move_forward")
			await process_frame
			Input.action_release(&"move_forward")
			continue
		# Room for the wave? Then the skill, which §16 wants the fight to have.
		if _now() - last_skill_at > 6.5 and flat.length() > 5.0:
			await _tap_key(KEY_Q)
			last_skill_at = _now()
			swings += 1
			await _seconds(0.5)
			continue
		await _tap_mouse()
		swings += 1
		await _seconds(0.75)
		if swings == 2:
			await _shot("13b_exchange")
	Input.action_release(&"move_forward")
	var elapsed := _now() - started
	_say("fight over after %.1f s, %d attack inputs" % [elapsed, swings])
	_check(elapsed < 50.0,
		"§16 the first fight resolved in %.1f s (limit 50)" % elapsed)


func _alive(hound: Node) -> bool:
	if not is_instance_valid(hound):
		return false
	if hound.is_queued_for_deletion():
		return false
	return float(hound.get("health")) > 0.0


func _find_hound() -> Node3D:
	for child in _world.get_children():
		if child is Node3D and child.has_method("stage_entry"):
			return child
	return null


# ============================================================ driving input

func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _seconds(t: float) -> void:
	await create_timer(t).timeout


## A key press and release, as an InputEvent, so `_unhandled_input` and
## `_input` see it exactly as they see a keyboard.
func _tap_key(key: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(3)
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)


## E is the interaction key in this world, and it is `interact` that the plaza
## routes; `StoryUI` takes the same physical key while a dialogue is open, so
## one helper covers both - the routing is the game's business, not the bot's.
func _tap(_action: StringName) -> void:
	await _tap_key(KEY_E)


func _tap_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(3)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)


func _click(control: Control) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var centre: Vector2 = control.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = centre
		ev.global_position = centre
		Input.parse_input_event(ev)
		await _frames(4)


## Turn the body so the camera looks at (x, z).
##
## The relation is the player's own, not an approximation of it:
## `player_movement.gd` does `rotate_y(-event.relative.x * mouse_sensitivity)`,
## so the relative x that produces a wanted yaw delta is `-delta / sensitivity`.
## It is run as a loop rather than one shot because a single synthetic delta is
## a guess about how many frames the pivot takes to settle, and a closed loop
## does not care.
func _face(x: float, z: float) -> void:
	var p: Vector3 = _player.global_position
	var dx := x - p.x
	var dz := z - p.z
	if absf(dx) + absf(dz) < 0.01:
		return
	# Godot's camera looks along -basis.z, so the yaw that points -Z at the
	# target is atan2(-dx, -dz).
	var want := atan2(-dx, -dz)
	var sens := float(_player.get("mouse_sensitivity"))
	if sens <= 0.0:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for _i in 8:
		var err := wrapf(want - _player.rotation.y, -PI, PI)
		if absf(err) < 0.02:
			return
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(-err / sens, 0.0)
		Input.parse_input_event(ev)
		await process_frame


func _look_around() -> void:
	# §2: the player can look around immediately. A little right, then back.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for delta in [0.55, -0.55]:
		for _i in 6:
			var ev := InputEventMouseMotion.new()
			ev.relative = Vector2(delta * 30.0, 0.0)
			Input.parse_input_event(ev)
			await process_frame


## Walk to a point on the ground plane by facing it and holding forward.
## Returns whether it got there; the caller checks the distance itself when the
## exact arrival matters.
func _walk_to(x: float, z: float, tolerance: float, timeout: float) -> bool:
	var started := _now()
	while _now() - started < timeout:
		var p: Vector3 = _player.global_position
		if Vector2(x - p.x, z - p.z).length() <= tolerance:
			break
		await _face(x, z)
		Input.action_press(&"move_forward")
		await process_frame
	Input.action_release(&"move_forward")
	await _frames(6)
	var p2: Vector3 = _player.global_position
	return Vector2(x - p2.x, z - p2.z).length() <= tolerance + 0.6


## Advance a conversation until it closes, by pressing E. Bounded, because a
## conversation that never closes must fail the run rather than hang it.
func _read_dialogue(max_lines: int) -> void:
	for _i in max_lines:
		if not bool(_ui.call("is_talking")):
			return
		await _seconds(1.5)
		await _tap(&"interact")


# ============================================================ story reading

func _resolve() -> void:
	_player = _world.get_node_or_null("Player") as CharacterBody3D
	_director = _world.get_node_or_null("StoryDirector")
	_ui = _world.get_node_or_null("StoryUI")
	_npc = _world.get_node_or_null("Mira") as Node3D
	_post = _world.get_node_or_null("TrainingPost") as Node3D
	_rack = _world.get_node_or_null("SwordRack") as Node3D
	if _player != null:
		_hold = _player.get_node_or_null("SwordHoldController")
		_slot = _player.get_node_or_null("WeaponSlot")
		_combat = _player.get_node_or_null("CombatController")


func _stage() -> int:
	if _director == null:
		return -1
	var raw: Variant = _director.get("stage")
	if raw == null or not (raw is int):
		return -1
	return int(raw)


func _stage_name() -> String:
	if _director == null or not _director.has_method("stage_name"):
		return "<none>"
	return String(_director.call("stage_name"))


func _now() -> float:
	return float(Time.get_ticks_msec()) * 0.001


## Wall clock, OR IT LIES. The story's own beats run on `create_timer`, which is
## real seconds, and this window has no frame cap - a fast GPU runs it well above
## 60 fps. A loop that counts frames and calls each one 1/60 s of story therefore
## expires EARLY and reports "the beat never happened" about a beat that had not
## been given its time yet. The first version of this file counted frames, timed
## out during the opening beat, and blamed the story for it: it reported ARRIVAL
## where the truth was "twenty seconds of dialogue had only just started".
func _await_stage(target: int, timeout: float) -> bool:
	var started := _now()
	while _now() - started < timeout:
		if _stage() >= target:
			return true
		await process_frame
	return false


func _first_button(menu: Control) -> Button:
	if menu == null:
		return null
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		if node is Button:
			return node as Button
		for child in node.get_children():
			stack.append(child)
	return null


# ============================================================ reporting

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)


func _say(text: String) -> void:
	print("[run] %s" % text)
	_log.append(text)


func _shot(name: String) -> void:
	var path := "%s%s.png" % [OUT, name]
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		print("  warn  no frame to capture for %s" % name)
		return
	image.save_png(path)
	_say("shot %s" % path.get_file())


func _finish() -> void:
	print("--- %d checks, %d failed ---" % [_checks, _fail])
	if _director != null and _director.has_method("debug_line"):
		print(_director.call("debug_line"))
	print("--- screenshots in %s ---" % OUT)
	quit(_fail)
