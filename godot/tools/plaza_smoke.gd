extends SceneTree
# ============================================================================
# FIRST PLAYABLE SEQUENCE — headless smoke test
# ============================================================================
#
# Run:
#   Godot --headless --path F:/SEKAI/godot --fixed-fps 60 \
#         --script res://tools/plaza_smoke.gd
#
# WHAT THIS PROVES, AND WHAT IT DELIBERATELY DOES NOT.
#
# It proves the scene loads, every node that `CombatController`, `IaidoDirector`
# and `StoryDirector` reach for by path exists, the world boots into the state
# §2 asks for (empty hands, no HUD, no prompt), the input profile was actually
# rewritten, and the opening beat runs to its end on its own clock without
# throwing.
#
# It does NOT prove the story plays. Every transition after ARRIVAL is triggered
# by a real keypress or a real blade crossing a real body - that IS the design
# (§21 forbids `if time > 15: spawn enemy`), so faking them here would mean
# faking the exact thing under test. Those are the §29 acceptance pass, which
# needs a visible Godot and a person.
#
# ASSERTIONS, NOT PRINTS. This project's rule is that a check which cannot go red
# is decoration, so every line below either passes or increments `_fail`, and the
# exit code is the count of failures.
#
# `--fixed-fps 60` IS REQUIRED for the timing assertions: without it the engine
# renders as fast as the CPU allows, `delta` becomes a fraction of a millisecond,
# and `StoryDirector`'s 20.7 s opening beat would need tens of thousands of
# frames. With it, one frame is exactly 1/60 s of story time and the numbers in
# `story_director.gd` are reproduced in the test.

const SCENE_PATH := "res://scenes/world/MistvalePlaza.tscn"
## §22's save file, which `SekaiSaveFlags` writes and `is_returning_player()`
## reads. Named here because this suite has to move it out of the way; see
## `_stash_flags()`.
const FLAGS_PATH := "user://sekai_flags.json"

## A HARD CEILING ON THIS TEST'S RUNTIME, AND IT IS NOT DECORATION.
##
## When a script under test fails to PARSE, Godot reports the parse error and
## then keeps running its main loop. The coroutine in `_initialize` that was
## awaiting a frame simply never resumes, so `quit()` is never reached and the
## process idles and burns CPU indefinitely. That is exactly what happened on the
## first run of this file: a one-line `match` over-wrap in `story_director.gd`
## turned a 20-second test into a 17-minute hang with 1400 s of CPU and no
## result. A watchdog converts "silent hang" into "reported failure", which is
## the difference between a test and a trap.
const WATCHDOG_SECONDS := 300.0

## Every node that something reaches for with a bare `get_node()` or an exported
## path. A missing one of these is not a cosmetic problem - it is the crash the
## whole round is trying not to ship.
const REQUIRED_NODES := [
	# the combat backbone: `CombatController._ready` bare-gets the first three,
	# `IaidoDirector._ready` bare-gets the rest.
	"CombatScreenFX", "TimeEffectManager", "IaidoDirector",
	"IaidoScreenFX", "IaidoGlassLayer", "IaidoAudioTimeline",
	"AudioStateController", "WorldPauseManager", "IaidoTargetCollector",
	"IaidoTear3D", "CombatAudioDirector",
	# the world stack
	"WorldEnvironment", "Sun", "Bounce", "Terrain", "Land", "HeroEnvironment",
	"Town", "Landmarks",
	# the actors
	"Player", "Mira", "SwordRack", "TrainingPost", "Stele", "SpawnPoint",
	"AlleyMouth",
	# the story layer
	"StoryUI", "StoryDirector", "CombatMusic",
]

## The opening beat, summed from the constants in `story_director.gd`:
## 4.2 hold + 2.0 + 0.6 + 2.8 + 0.9 + 1.4 + 0.5 + 3.0 + 1.2 + 2.2 + 1.6 + 0.3.
## Written out rather than recomputed so that a change to any one of them makes
## this number wrong and the test says so.
const OPENING_SECONDS := 20.7

var _fail := 0
var _checks := 0
## The player's save file, stashed for the duration of the run and put back on
## the way out. See `_stash_flags()`.
var _flags_backup := ""
var _had_flags := false


func _initialize() -> void:
	_watchdog()
	_stash_flags()
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		_fail += 1
		print("FAIL  %s did not load -- every check below is meaningless." % SCENE_PATH)
		_restore_flags()
		quit(_fail)
		return
	var world := packed.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	print("--- built in %d ms ---" % (Time.get_ticks_msec() - t0))

	# BEFORE ANYTHING ELSE: is the world's own script actually attached? This is
	# the check that would have caught the parse failure immediately instead of
	# via thirty downstream failures that all looked like story bugs.
	_check(world.get_script() != null,
		"the plaza script is attached to the scene root (its _ready ran)")
	_check_nodes(world)
	_check_input_profile()
	_check_boot_state(world)

	# --- the opening beat, on its own clock ---------------------------------
	#
	# §2 says nobody speaks for the first few seconds; §3 says the first thing
	# said is about the player's body. So the stage must still be ARRIVAL well
	# into the beat, and must be MET_MIRA after it - and the prompt must appear
	# with it, because the whole point of `npc_prompt()` is that Mira has nothing
	# to say until she has noticed you.
	var director: Node = world.get_node_or_null("StoryDirector")
	await _advance(OPENING_SECONDS * 0.5)
	_check(_stage_of(director) == 0,
		"halfway through the opening beat the stage is still ARRIVAL (got %s)"
			% _stage_name_of(director))
	await _advance(OPENING_SECONDS * 0.5 + 1.5)
	_check(_stage_of(director) == 1,
		"the opening beat finished into MET_MIRA (got %s)"
			% _stage_name_of(director))
	_check(director != null and String(director.call("npc_prompt")) == "[F]  交谈",
		"Mira has something to say once she has noticed the player")

	# --- the deliverable facts of the round ---------------------------------
	_check_groups()
	_check_hound_scene()
	_check_paving_layer(world)
	await _check_ui_cards_expire(world)

	print("--- %d checks, %d failed, %d ms ---"
		% [_checks, _fail, Time.get_ticks_msec() - t0])
	if director != null and director.has_method("debug_line"):
		print(director.call("debug_line"))

	# TEAR DOWN BEFORE QUITTING, AND THAT IS NOT TIDINESS.
	#
	# `quit()` lets the engine free the whole tree in one pass during shutdown,
	# and the plaza does not survive that path - it segfaults in a destructor
	# AFTER every check has passed, which replaces the exit code with a crash and
	# makes this test unusable to any caller that reads one. Freeing the world
	# here, on a normal frame, with queued deletions given a frame to run, keeps
	# the shutdown path identical to every other scene's.
	root.remove_child(world)
	world.queue_free()
	await process_frame
	await process_frame
	_restore_flags()
	quit(_fail)


## HIDES THE PLAYER'S SAVE FOR THE DURATION OF THE RUN, AND WHY THAT IS NOT
## OPTIONAL.
##
## §22 persists the first-sequence flags to `user://sekai_flags.json`, and
## `is_returning_player()` reads them back - a returning player skips the whole
## opening beat and starts at NEXT_OBJECTIVE. So every check about the opening
## beat is silently conditional on a file that outlives the run: with a save on
## disk this suite reported six failures that all said "the story began at the
## end", and a genuine regression in the opening beat would have been
## indistinguishable from the leftovers of the previous pass.
##
## The file is moved aside rather than deleted, and put back on every exit path,
## because it is the player's progress and not this test's to discard.
func _stash_flags() -> void:
	if not FileAccess.file_exists(FLAGS_PATH):
		return
	_had_flags = true
	_flags_backup = FileAccess.get_file_as_string(FLAGS_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FLAGS_PATH))


func _restore_flags() -> void:
	if _had_flags:
		var f := FileAccess.open(FLAGS_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_flags_backup)
			f.close()
		return
	# Nothing was there when this run started, so nothing may be there when it
	# ends - this suite writes real flags as it drives the story.
	if FileAccess.file_exists(FLAGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FLAGS_PATH))


## Turns "the coroutine died somewhere" into a failure with a reason attached.
func _watchdog() -> void:
	var timer := create_timer(WATCHDOG_SECONDS, true)
	timer.timeout.connect(func() -> void:
		print("FAIL  watchdog fired at %.0f s -- an await chain aborted. Read the "
			% WATCHDOG_SECONDS + "SCRIPT ERROR lines above; the usual cause is a "
			+ "script under test failing to parse.")
		quit(99))


## `get("stage")` on a node whose script failed to load returns `null`, and
## `int(null)` throws rather than comparing false - so this reads the value
## defensively and answers -1 for "there is no stage to speak of".
func _stage_of(director: Node) -> int:
	if director == null:
		return -1
	var raw: Variant = director.get("stage")
	if raw == null or not (raw is int):
		return -1
	return int(raw)


func _stage_name_of(director: Node) -> String:
	if director == null or not director.has_method("stage_name"):
		return "<no script>"
	return String(director.call("stage_name"))


## REAL SECONDS, NOT FRAMES, AND WHY THAT IS NOT A STYLE CHOICE.
##
## `StoryDirector._begin()` waits on `create_timer`, and `create_timer` counts
## real time however fast frames are produced. A headless run produces them very
## fast - several hundred a second - so "advance 1242 frames" to represent the
## 20.7 s opening beat advanced the STORY by about two seconds, and this suite
## reported that the opening beat never finished and that Mira never noticed the
## player. `--fixed-fps 60` is the other way to make the two agree, and in this
## environment that combination segfaults.
func _advance(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) * 0.001 < seconds:
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)


func _check_nodes(world: Node) -> void:
	for path in REQUIRED_NODES:
		_check(world.get_node_or_null(path) != null,
			"node present: %s" % path)
	# The Player carries three of the systems the story is written against, and
	# none of them are optional: without the slot there is no "empty hands",
	# without the hold controller there is no four-state draw, and without the
	# combat controller there is no blade to draw at all.
	for path in ["Player/WeaponSlot", "Player/CombatController",
			"Player/WeaponManager", "Player/SwordHoldController",
			"Player/CameraFeedbackController"]:
		_check(world.get_node_or_null(path) != null,
			"node present: %s" % path)
	# Mira's four layers (§23). `VisualRoot` is what ART replaces; the anchor is
	# what the camera will aim at when the real model arrives.
	for path in ["Mira/VisualRoot", "Mira/DialogueAnchor", "Mira/Interaction"]:
		_check(world.get_node_or_null(path) != null,
			"node present: %s" % path)


## §2 and §20, checked as facts rather than as intentions.
func _check_boot_state(world: Node) -> void:
	var slot = world.get_node_or_null("Player/WeaponSlot")
	var hold = world.get_node_or_null("Player/SwordHoldController")
	var director: Node = world.get_node_or_null("StoryDirector")
	var stele = world.get_node_or_null("Stele")
	# A node with no script answers every get() with null and every call() with an
	# error, which reads downstream as a dozen separate story bugs.
	_check(director != null and director.get_script() != null,
		"StoryDirector has its script attached")
	_check(stele != null and stele.get_script() != null,
		"Stele has its script attached")
	_check(slot != null and not bool(slot.call("is_sword")),
		"§2  the player starts with no sword in the slot")
	_check(slot != null and String(slot.call("display_name")) == "空手 · Unarmed",
		"§2  the slot reports itself as empty")
	_check(hold != null and String(hold.get("state_name")) == "SHEATHED",
		"§7  the sword starts in its saya (SHEATHED)")
	_check(_stage_of(director) == 0, "the sequence starts at ARRIVAL")
	_check(stele != null and stele.has_method("pulse"),
		"§3  the stele can pulse")
	# §1 wants a centre, and every actor is placed from the height field - but
	# "the body origin is near the ground" is the WRONG QUESTION and asking it is
	# how this test passed 71 checks on a world where the player was buried 0.78 m
	# deep in the terrain and could not move. `Player.tscn`'s capsule is 1.8 m
	# tall and centred on the origin, so the origin SHOULD sit about a metre above
	# the ground; it is the capsule's BOTTOM that has to be on it. So this measures
	# the bottom.
	var player: Node3D = world.get_node_or_null("Player")
	if player == null:
		_check(false, "§1  the player exists")
		return
	var ground: float = MistvaleHeights.height_at(player.global_position.x,
		player.global_position.z)
	var clearance := player.global_position.y + _capsule_bottom_offset(player) - ground
	_check(clearance > -0.05 and clearance < 0.45,
		"§1  the player stands ON the ground rather than in it "
		+ "(capsule bottom is %+.3f m from it)" % clearance)


## Where the collider's underside sits relative to the body origin.
func _capsule_bottom_offset(body: Node3D) -> float:
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		return -0.9
	var capsule := shape.shape as CapsuleShape3D
	if capsule != null:
		return shape.position.y - capsule.height * 0.5
	var box := shape.shape as BoxShape3D
	if box != null:
		return shape.position.y - box.size.y * 0.5
	return -0.9


func _check_input_profile() -> void:
	_check(InputMap.has_action("draw_sword"), "§7  `draw_sword` is bound")
	_check(_has_key("draw_sword", KEY_R), "§7  R draws the sword")
	_check(InputMap.has_action("style_skill_1"),
		"§10 `style_skill_1` survives as the skill carrier")
	_check(_has_key("style_skill_1", KEY_Q), "§10 Q releases the skill")
	# §26: the released actions must have NO events left, or the player presses a
	# key that does nothing and concludes the game is broken. `released` here is
	# the same list the world uses, checked from the outside.
	for action in ["cast_selected", "fire_cast", "frost_cast", "wind_cast",
			"style_skill_2", "style_skill_3", "iaido", "ultimate",
			"weapon_1", "weapon_2"]:
		if not InputMap.has_action(action):
			continue
		_check(InputMap.action_get_events(action).is_empty(),
			"§26 `%s` was released and has no events" % action)
	# The duplicate-event defect: two identical key events on one action behaves
	# correctly today and misstates the bindings, and the restore writes it back.
	_check(InputMap.action_get_events("draw_sword").size() == 1,
		"§7  `draw_sword` carries exactly one event, not two")


func _has_key(action: String, key: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return true
	return false


func _check_groups() -> void:
	var names := PackedStringArray()
	for node in get_nodes_in_group("interactable"):
		names.append(String(node.name))
	_check(names.has("Mira"), "Mira is in the `interactable` group")
	_check(names.has("SwordRack"), "the rack is in the `interactable` group")
	# §8: the post is a target, not a conversation. It must NOT be in the group,
	# or walking past it would offer an [E] prompt for a straw dummy.
	_check(not names.has("TrainingPost"),
		"§8  the training post is not interactable")


func _check_hound_scene() -> void:
	var packed: PackedScene = load("res://scenes/enemies/FirstEncounterEnemy.tscn")
	if packed == null:
		_fail += 1
		_checks += 1
		print("  FAIL  §12 the hound scene loads")
		return
	var hound := packed.instantiate()
	root.add_child(hound)
	_check(hound.get_node_or_null("CollisionShape3D") != null,
		"§12 the hound has a body volume")
	_check(hound.has_signal("died") and hound.has_signal("arrived")
			and hound.has_signal("struck_player")
			and hound.has_signal("knocked_prop"),
		"§12/§13 the hound declares died / arrived / struck_player / knocked_prop")
	_check(hound.has_method("stage_entry"),
		"§13 the hound can walk in under the director's direction")
	_check(float(hound.get("max_health")) > 0.0,
		"§15 the hound has health (%.0f)" % float(hound.get("max_health")))
	# Freed here rather than left to shutdown: it was added to `root`, not to the
	# world, so the world teardown below does not reach it.
	hound.queue_free()


## §1: the square has a paved floor, AND IT IS THE ONE YOU CAN SEE.
##
## WHY THIS CHECK EXISTS. The apron was well-formed - 1152 triangles, every
## normal facing up - sat 14 cm above the analytic height field, was `visible` in
## a `visible` tree, and was drawn every frame. It was also 12 cm UNDER the
## market ribbon that `MistvaleLand` lays over the same field, so the square read
## as bare dirt and the whole 71-check suite was green. A check that measures the
## apron against the FIELD passes on a buried apron; this measures it against the
## surface the town's paving actually occupies.
func _check_paving_layer(world: Node) -> void:
	var apron: MeshInstance3D = null
	for child in world.get_children():
		if child is MeshInstance3D and child.name == "PavedApron":
			apron = child as MeshInstance3D
	_check(apron != null, "§1  the square has a paved apron")
	var land := world.get_node_or_null("Land") as MistvaleLand
	_check(land != null, "§1  the region's land layer is present")
	if apron == null or land == null:
		return
	var verts := apron.mesh.get_faces()
	_check(verts.size() >= 300, "§1  the apron is a real mesh (%d vertices)"
			% verts.size())
	var step := maxi(1, verts.size() / 240)
	var buried := 0
	var worst := -99.0
	for i in range(0, verts.size(), step):
		var p := verts[i]
		var shortfall := land.paving_height(p.x, p.z) - p.y
		if shortfall > 0.005:
			buried += 1
		worst = maxf(worst, shortfall)
	_check(buried == 0,
		"§1  the apron stands ON the town's paving, not under it "
		+ "(%d/%d sampled vertices buried, worst clearance %+.4f m)"
			% [buried, int(ceil(float(verts.size()) / float(step))), -worst])


## §20: a card exists while the thing that raised it is still true. One that
## never leaves is not "persistent", it is stuck.
##
## WHY THIS CHECK EXISTS. The hold and the fade were written as one nested test,
## so the fade ran for exactly ONE FRAME and then stopped: the alpha froze at
## 0.995 and the card stayed up for the rest of the session. In the acceptance
## run the acquisition toast from the sword rack was still drawn thirty seconds
## and five story stages later, underneath the mission-updated card, the two sets
## of text unreadable on top of each other - and every check was green, because
## nothing measured the cards' lifetime.
func _check_ui_cards_expire(world: Node) -> void:
	var ui: Node = world.get_node_or_null("StoryUI")
	_check(ui != null, "§20 the HUD exists")
	if ui == null:
		return
	var toast: Control = ui.get("_toast_box")
	var quest: Control = ui.get("_quest_box")
	ui.call("toast", "SMOKE", "check")
	ui.call("quest", "SMOKE", "check")
	_check(toast.visible and quest.visible,
		"§20 raising a card makes it visible")
	# REAL seconds, because `_process(delta)` is fed real frame time. Ten seconds
	# covers the 6 s quest hold and its 2 s fade with room to spare.
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) * 0.001 < 10.0:
		await process_frame
	_check(not toast.visible,
		"§20 the toast expired on its own (alpha %.3f)" % toast.modulate.a)
	_check(not quest.visible,
		"§20 the quest card expired on its own (alpha %.3f)" % quest.modulate.a)
