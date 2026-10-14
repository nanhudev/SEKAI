extends SceneTree
##
## SWORD BASIC ATTACK V2 — THE DELIVERY CLIP (§39-A).
##
## ===========================================================================
## WHAT THIS FILE IS, AND WHAT IT REFUSES TO BE
## ===========================================================================
##
## It is one clean take of the new four-beat basic sentence, in the venue the
## sentence is authored for: the player's own eyes. §35 says every beat has to
## stand up in first person BEFORE any third-person work is time well spent, and
## the sword's rig is parented to the camera, so a review camera three metres back
## would be watching a duplicate of a weapon that is not being held there. There is
## no outside camera in this file. What the player sees is what is delivered.
##
## ===========================================================================
## WHY IT RUNS IN REAL TIME
## ===========================================================================
##
## The controller's clock is `combat_time` — the sum of the deltas it was actually
## given — and its windows open against that. Pinning the clock to capture tidy
## frames would desync the animation from the windows, and the whole subject of
## this clip is TIMING: A1 is 0.40s, A3 is a one-second three-beat break, and 0.9s
## of stillness is what makes the next press a new sentence. So the takes are
## played at the speed they are meant to be played at, the frames are captured as
## they come, and the measured rate is written to `fps.txt` so the encoder can
## play it back at true speed on a machine that renders faster or slower than this
## one.
##
## ===========================================================================
## WHY THE STILLS ARE CHOSEN BY PREDICATE AND NOT BY TIMESTAMP
## ===========================================================================
##
## §39-B's eight cells are `Equip draw / A1 finish / A2 release / A3 cut 1 / A3 cut
## 2 / A3 cut 3 / A4 major arc / final stance`. Three of those are EVENTS on the
## reach runtime (`trace_resolved`, `arc_resolved`) and the rest are moments inside
## a move. A take that picked them by clock would photograph the machine's frame
## rate: A3's three cuts happen 80ms apart inside a one-second move, so a timestamp
## three frames late is a picture of the wrong cut. The stills are therefore taken
## from the signals that MEAN the thing — the same signals the VFX and the audio
## listen to — so a still cannot disagree with the cut it is named after.
##
## Usage:
##   godot --path godot --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/sword_basic_v2_movie.gd -- <output_dir> [clean|rings]

const ZONE := preload("res://scripts/training/sword_combo_zone.gd")

const TITLE_SECONDS := 1.6
const OUTRO_SECONDS := 2.0
## 30 is enough to read a 40ms cut and keeps a 25-second take to a sane size. It is
## a CAP on the capture rate, not a time scale: the wall clock is untouched.
const CAPTURE_FPS := 30

var output_dir := ""
var frame_index := 0
var start_ms := 0
var sandbox: Node3D
var player: CharacterBody3D
var combat: CombatController
var reach: SwordReach
var weapon: WeaponSlot
var manager: Node
var zone: Node3D

var layer: CanvasLayer
var shot_label: Label
var caption_label: Label
var note_label: Label

## `{tag, when, done}` — `when` is a Callable predicate over the live state.
var _stills: Array[Dictionary] = []
## A still requested by an EVENT rather than a predicate, taken on the next frame
## that is captured. The event has already happened by the time the signal is
## delivered, and what is wanted is the picture of the beat it belongs to.
var _pending_still := ""
var _shot_note := ""
var _segment_started_ms := 0
## Every still tag this take asked for, against the tags that actually reached
## the disk. They are compared at the end of the run, because nothing else in
## this file ever looks in the output folder: §39-B's eight cells can be missing
## and every other line of output still reads like a clean take.
var _wanted_stills: Array[String] = []
var _written_stills: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	output_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../.render/sword_basic_v2")
	var ring_mode := String(args[1]) if args.size() > 1 else "clean"
	DirAccess.make_dir_recursive_absolute(output_dir)
	_clear_frames()

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	Engine.max_fps = CAPTURE_FPS

	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	sandbox = scene.instantiate()
	root.add_child(sandbox)
	await _warm(12)

	player = sandbox.get_node("Player")
	combat = player.get_node("CombatController")
	weapon = player.get_node("WeaponSlot")
	manager = player.get_node("WeaponManager")
	reach = combat.reach

	# The arena's own dummy is a second, unscripted target that wanders into the
	# frame and takes hits nobody asked for. This clip is about the nine bodies
	# the zone places, so it is retired rather than fought.
	var stray := sandbox.get_node_or_null("TechnicalDummy") as Node3D
	if stray != null:
		stray.visible = false
		stray.set_process(false)
		stray.set_physics_process(false)

	zone = ZONE.new()
	zone.name = "SwordComboZone"
	sandbox.add_child(zone)
	zone.build(player)
	zone.set_clean(ring_mode != "rings")

	# The key legend is a developer aid (ChainLab §17) and it is drawn over every
	# frame of a first-person clip, in the top-left, at the same size as the shot
	# titles. It is off for a delivery take and it has an API for exactly this.
	var lab := sandbox.get_node_or_null("ChainLab")
	if lab != null and lab.has_method("set_legend_visible"):
		lab.call("set_legend_visible", false)

	# THE REST OF THE LAB COMES OFF TOO, AND PASS 03 IS WHY THIS IS AN EXPLICIT LIST.
	#
	# Pass 03 shipped a clip in which every single frame carried a red/cyan/olive
	# meter block in the bottom-left and a `[1] 剑 Sword  [2] 竭焉链 Chain / Universal /
	# FROST … 2/4` readout in the bottom-right. Both are the LAB talking to the person
	# at the keyboard, and §46/§51 want the artefact clean — a key list and an element
	# ladder in a clip that is supposed to be about the weapon's four distances is a
	# caption about the controls. The legend API alone was not enough because the
	# legend is only one of the overlay's widgets.
	#
	# `CombatHUD` comes off for the same reason and costs nothing: this clip has no
	# crosshair in it, so there is no aim reticle to lose.
	#
	# `ForegroundWeaponLayer` is deliberately NOT in this list. It is not an overlay —
	# it is where the first-person blade is actually drawn (the weapon meshes are moved
	# onto a private render layer and cleared from the world camera). Hiding it does not
	# remove a duplicate sword, it removes the sword.
	for ui_name in ["DeveloperPanel", "ParryDebugOverlay", "CombatHUD"]:
		var ui := sandbox.get_node_or_null(ui_name)
		if ui != null:
			ui.set("visible", false)
		else:
			push_warning("delivery take: expected overlay %s was not in the scene" % ui_name)

	# The chain's dev readout is a separate switch from the node's visibility: the
	# overlay keeps drawing it after the legend is hidden. It is the source of the
	# `Universal / FROST n/4` block above the key list.
	var chain_dir := player.get_node_or_null("ChainDirector")
	if chain_dir != null:
		chain_dir.set("debug_readout", false)

	# THE WEAPON INDICATOR IS TWO THINGS AND ONLY ONE OF THEM IS DOCUMENTATION.
	#
	# `WeaponManager._build_indicator()` builds a bottom-right `CanvasLayer` holding a
	# `Keys` row (`[1] 剑 Sword   [2] 缚星链 Chain`) and a `Flash` label. The row is a key
	# list — the same furniture the ChainLab legend is, and the same reason it goes: a clip
	# about four distances should not be captioned with the controls.
	#
	# The flash STAYS. It is the 0.9s name that appears when the weapon changes, the file's
	# own comment calls it "the only thing on screen that names a weapon", and §39-A asks
	# for a Weapon Switch beat — the name arriving with the blade is part of that beat, not
	# a debug readout next to it. So the row is hidden rather than the layer: hiding the
	# layer would take the name with it.
	#
	# This is also why it is hidden by node and not with `_set_indicator_shown()`, which
	# switches the whole layer and is wired to F7.
	#
	# One path, one lookup. The obvious two-step form (`get WeaponIndicator`, then
	# `get Keys` off it) is what a `--check-only` run segfaulted on with no diagnostic
	# at all, so the nested form is replaced by the single path rather than trusted.
	var key_row := manager.get_node_or_null("WeaponIndicator/Keys")
	if key_row == null:
		push_warning("delivery take: WeaponManager had no WeaponIndicator/Keys row")
	else:
		key_row.set("visible", false)

	_build_overlay()
	reach.trace_resolved.connect(_on_trace_resolved)
	reach.arc_resolved.connect(_on_arc_resolved)

	print("window=", root.size, "  rings=", ring_mode, "  out=", output_dir)
	start_ms = Time.get_ticks_msec()

	await _shot("EQUIP · 拔刀 · DRAW FROM SAYA", "Press 2, then 1. The blade is taken out of the saya.", TITLE_SECONDS)
	await _take_equip()

	await _shot("A1 · 小居合 · 右划", "CLOSE. FAST. CLEAN. Touch the mouth, hold, draw across.", 0.9)
	await _take_single_beat(0, "a1_finish", ["near"])

	await _shot("A2 · 左划上挑 · 中距离剑气", "The cut LEAVES the blade. Mid range.", 0.9)
	await _take_single_beat(1, "a2_release", ["mid"])

	await _shot("A3 · 小居合领域 · 三次划痕", "STOP. ... 1 ... 2 ... 3. Long range.", 0.9)
	await _take_single_beat(2, "", ["far", "off_axis"])

	await _shot("A4 · 周身优弧横斩", "RETURN TO THE BODY. 270 degrees, one cut.", 0.9)
	await _take_single_beat(3, "a4_major_arc", ["surround_0", "surround_1", "surround_2", "surround_3", "behind"])

	await _shot("FULL COMBO · A1→A2→A3→A4", "近。 推开。 你以为安全了吗？ 回来。", 0.9)
	await _take_full_combo()

	await _shot("COMBO RESET · 停一秒就回 A1", "Stop for longer than the window: the next press is a first press.", 0.9)
	await _take_combo_reset()

	await _shot("WEAPON SWITCH · 剑 → 链 → 剑", "The sword goes home, then comes out again. The saya never disappears.", 0.9)
	await _take_weapon_switch()

	await _outro()

	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var fps := float(frame_index) / maxf(elapsed, 0.001)
	print("frames=%d  wall=%.2fs  -> ENCODE_FPS=%.3f" % [frame_index, elapsed, fps])
	_write_fps(fps)

	# THE TAKE HAS TO BE ABLE TO FAIL. Every number above is self-consistent
	# whether or not a single picture reached the disk — the run that produced
	# one repeated frame still printed `EXIT=0`, a wall time of 25 seconds and a
	# tidy `frames=` line. So the folders are read back here, and a take that is
	# missing frames or missing cells of §39-B exits non-zero.
	var missing: Array[String] = []
	for tag in _wanted_stills:
		if not _written_stills.has(tag):
			missing.append(tag)
	print("stills wanted=%d written=%d" % [_wanted_stills.size(), _written_stills.size()])
	if not missing.is_empty():
		push_error("§39-B stills missing: %s" % ", ".join(missing))
	if frame_index <= 0:
		push_error("no frames were captured at all")
	if frame_index <= 0 or not missing.is_empty():
		print("FAIL: delivery is incomplete — %d frame(s), missing %s" % [
			frame_index, "none" if missing.is_empty() else ", ".join(missing)
		])
		quit(1)
		return
	print("PASS: %d frames and all %d stills written to %s" % [
		frame_index, _written_stills.size(), output_dir
	])
	quit()


# ===========================================================================
#  THE TAKES
# ===========================================================================

## E0 → E3: the draw, with the blade seated in the saya on the first frame.
##
## THE DRAW IS NOT AN ACTIVE MOVE, and both the still predicate and the capture
## loop here have to know that.
##
## `SwordBasic.equip()` is a POSE SOURCE, not something that gets played: the
## controller samples it in `pose_snapshot()` while `equip_blend` climbs, and
## `WeaponManager` owns the clock. `DRAW_SECONDS` is no longer typed in that file
## either — it is `SwordBasic.equip().total_time()`, which is 1.75 s, the length
## of the five-beat sentence. (This comment said `DRAW_SECONDS == EQUIP_TOTAL ==
## 0.62s` for two revisions after that stopped being true, which is what a number
## written down twice does.) No
## `sb_equip` move ever reaches `active_move_id`. So a predicate waiting for
## `active_move_id == SwordBasic.EQUIP` waits for a state the design deliberately
## never produces — and because it could only ever be read as "missing still",
## the run reported it as one missing cell and nothing else. The predicate is now
## the climb itself: past halfway (E1 is 0.32 of the way, E2 is 0.68), so the
## blade is out of the mouth and legibly still moving.
##
## The same fact breaks `_capture_until_idle()` here: the controller is IDLE for
## the whole draw, so that loop returned after its 0.25s tail and the take moved
## on with the blade still half out. `_capture_until_drawn()` waits on the blend.
func _take_equip() -> void:
	await _ensure_idle()
	# One body at arm's length: the draw is the subject, and a body is what gives
	# the blade's travel something to be measured against.
	_solo(["near"])
	manager.call("equip_weapon", &"chain")
	await _capture_for(1.0)
	_set_note("Blade home in the saya. Left hand on the sheath.")
	manager.call("equip_weapon", &"sword")
	_arm_stills([{"tag": "equip_draw", "when": Callable(self, "_equip_draw_ready")}])
	await _capture_until_drawn()
	_set_note("")
	await _capture_for(0.5)


## Stands every zone target down except the named ones.
##
## WHY THE SHOTS ARE FILTERED AND THE BEATS ARE NOT. The zone's near / mid / far
## targets are COLLINEAR, which is exactly right for measuring — it is what lets
## one forward press be three different distances — and exactly wrong for
## filming. The arm's-length body is 1.8m wide at 1.9m, so it subtends about 50
## degrees; the 15m body behind it subtends 15. Every distance beat in this clip
## would otherwise be a photograph of the nearest dummy with the far one hidden
## behind it, which is what PASS 01 actually delivered.
##
## Filtering the TARGETS rather than moving them keeps every measured distance
## intact: A1 still cuts a body at 1.9m and A3 still cuts one at 15.0m, which is
## the thing the clip exists to show. §32 is what proves the unfiltered arena —
## all nine bodies at once — behaves the same way.
func _solo(ids: Array) -> void:
	for node in zone.call("all_targets"):
		var body: Node3D = node
		var key: String = String(body.name).replace("Target_", "")
		body.visible = ids.has(key)


## One beat, from a standing start, so the beat is the only thing in the shot.
func _take_single_beat(index: int, still: String, cast: Array) -> void:
	await _ensure_idle()
	_solo(cast)
	var expected: StringName = combat.moveset.light_chain[index]
	if index > 0:
		# From idle, `request` would start A1 — the sentence only reaches its
		# later beats by being played. So the earlier beats are played quickly and
		# the capture only starts once the wanted beat is running, which keeps the
		# shot about that beat.
		for i in index:
			if not await _advance_to_cancel():
				break
	await _ensure_idle()
	for i in index:
		combat.request(&"light")
		if not await _advance_to_cancel():
			break
	combat.request(&"light")
	if still != "":
		_arm_stills([{"tag": still, "when": func() -> bool:
			return combat.active_move_id == expected and _past_settle(expected)}])
	await _capture_until_idle()
	await _capture_for(0.6)


func _take_full_combo() -> void:
	await _ensure_idle()
	# The only shot that stands the whole zone up: nine bodies at once is the
	# arena §32 actually measures, and it is worth seeing once what the four beats
	# do to it.
	_solo(["near", "mid", "far", "off_axis", "surround_0", "surround_1", "surround_2", "surround_3", "behind"])
	_arm_stills([{"tag": "final_stance", "when": func() -> bool:
		return (
			combat.active_move_id == SwordBasic.A4
			and combat.state == CombatController.State.ATTACK
			and combat.state_time >= SwordBasic.a4().total_time() * 0.86
		)}])
	combat.request(&"light")
	for i in 3:
		if not await _advance_to_cancel():
			break
		combat.request(&"light")
	await _capture_until_idle()
	await _capture_for(1.0)


func _take_combo_reset() -> void:
	await _ensure_idle()
	_solo(["near"])
	combat.request(&"light")
	await _capture_until_idle()
	_set_note("Now stop. Do not press anything.")
	var seconds := combat.moveset.combo_window * 1.7
	await _capture_for(seconds)
	_set_note("Same key, one press: A1 again.")
	combat.request(&"light")
	await _capture_until_idle()
	_set_note("")
	await _capture_for(0.6)


func _take_weapon_switch() -> void:
	await _ensure_idle()
	_solo(["near"])
	_set_note("To the chain: the blade goes home first.")
	manager.call("equip_weapon", &"chain")
	await _capture_for(0.9)
	_set_note("Back to the sword: OUT OF THE SAYA, not into the hand.")
	manager.call("equip_weapon", &"sword")
	await _capture_for(1.0)
	combat.request(&"light")
	await _capture_until_idle()
	_set_note("")
	await _capture_for(0.6)


func _outro() -> void:
	shot_label.text = "SWORD BASIC ATTACK V2"
	caption_label.text = "A1 CLOSE · A2 MID WAVE · A3 LONG SPACE CUT · A4 SURROUND ARC"
	note_label.text = "Distance. Rhythm. The saya. Space. Not damage numbers."
	await _capture_for(OUTRO_SECONDS)


# ===========================================================================
#  CAPTURE
# ===========================================================================

func _capture_for(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await _capture_one()


func _capture_until_idle() -> void:
	var guard := 0
	while combat.state != CombatController.State.IDLE and guard < 900:
		await _capture_one()
		guard += 1
	await _capture_for(0.25)


## Captures until the sword has finished being taken out of the saya. Separate
## from `_capture_until_idle()` because a draw leaves the controller IDLE for its
## whole 0.62s — it is a pose blend, not a move — so the idle loop would exit
## immediately and the take would walk off mid-draw.
func _capture_until_drawn() -> void:
	var guard := 0
	while float(combat.equip_blend) < 0.999 and guard < 900:
		await _capture_one()
		guard += 1
	await _capture_for(0.25)


## Captures until `seconds` of game time have passed since the shot opened. Used by
## `_shot`, which is why it counts game time rather than frames.
func _capture_game(seconds: float) -> void:
	var until := combat.combat_time + seconds
	var guard := 0
	while combat.combat_time < until and guard < 900:
		await _capture_one()
		guard += 1


func _capture_one() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport returned no image at frame %d" % frame_index)
		return
	var err := image.save_png("%s/frame_%04d.png" % [output_dir, frame_index])
	if err != OK:
		push_error("save_png failed (%d) at frame %d" % [err, frame_index])
		return
	# COUNTED ON SUCCESS, AND THAT IS THE WHOLE POINT. This increment used to sit
	# inside the `err != OK` branch above — one indent to the left of nothing —
	# so a perfectly healthy render wrote every one of its ~700 frames to
	# `frame_0000.png`, kept `frame_index` at 0, and therefore wrote
	# `ENCODE_FPS=0.0000` and produced no stills at all, because `_copy_still`
	# bails on `frame_index <= 0`. The run printed success and the clip was one
	# repeated frame.
	#
	# `frame_index` is not a count of save attempts. It is the NAME of the
	# picture on disk, and it may only move when a picture reaches the disk.
	frame_index += 1
	_pump_stills()
	if frame_index % 60 == 0:
		print("    frame %d  game=%.2fs" % [frame_index, combat.combat_time])


# --- stills ----------------------------------------------------------------

func _arm_stills(rules: Array) -> void:
	_stills.clear()
	for rule in rules:
		rule["done"] = false
		_stills.append(rule)
		_want_still(String(rule["tag"]))


func _want_still(tag: String) -> void:
	if not _wanted_stills.has(tag):
		_wanted_stills.append(tag)


func _on_trace_resolved(index: int, _hits: int, _mark: Dictionary) -> void:
	_pending_still = "a3_cut_%d" % (index + 1)
	_want_still(_pending_still)


func _on_arc_resolved(slice_index: int, _hits: int, _from: float, _to: float) -> void:
	# The middle of the sweep, not its ends: a picture of the first slice is a
	# picture of the wind-up and a picture of the last is a picture of the finish.
	if slice_index == 2:
		_pending_still = "a4_major_arc"
		_want_still(_pending_still)


func _pump_stills() -> void:
	if _pending_still != "":
		_copy_still(_pending_still)
		_pending_still = ""
	for rule in _stills:
		if rule["done"]:
			continue
		var when: Callable = rule["when"]
		if not when.call():
			continue
		rule["done"] = true
		_copy_still(String(rule["tag"]))


func _copy_still(tag: String) -> void:
	# `frame_index` counts frames already written, so the picture for this beat is
	# the one just saved at `frame_index - 1`. A zero here means no frame has
	# reached the disk, which is a real fault and not a reason to stay quiet.
	if frame_index <= 0:
		push_error("still '%s' asked for before any frame was saved" % tag)
		return
	# FIRST WRITE WINS. A3 and A4 run twice in this clip — once in their own
	# single-beat take and again inside the full combo — and the same reach events
	# fire both times. The dedicated take is the one that was set up for the
	# picture, so it keeps the cell; the second run must not overwrite it with a
	# frame from a busier shot.
	if _written_stills.has(tag):
		return
	var from := "%s/frame_%04d.png" % [output_dir, frame_index - 1]
	var to := "%s/still_%s.png" % [output_dir, tag]
	var err := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)
	)
	if err != OK:
		push_error("still '%s' failed to copy (%d) from %s" % [tag, err, from])
		return
	_written_stills.append(tag)


# ===========================================================================
#  HARNESS
# ===========================================================================

func _shot(title: String, caption: String, seconds: float) -> void:
	shot_label.text = title
	caption_label.text = caption
	note_label.text = ""
	_segment_started_ms = Time.get_ticks_msec()
	await _capture_game(seconds)


func _set_note(text: String) -> void:
	note_label.text = text


## The draw cell's predicate, written as a METHOD, and handed over as an explicit
## `Callable(self, ...)`. Both halves of that are load-bearing and neither is
## style.
##
## `--check-only` on this file crashes with a segmentation fault (signal 11) on
## BOTH of these, which are otherwise ordinary GDScript:
##
##   1. a multi-line lambda whose body declares a local
##      (`func() -> bool: var blend := ...`), and
##   2. the bare method reference, `{"when": _equip_draw_ready}`, used as a value
##      inside the dictionary array literal that `_arm_stills()` takes, and
##   3. `StringName` literals (`&"near"`) inside a MULTI-LINE array literal used
##      as a call argument. NOT ISOLATED: that edit also replaced a nested
##      `StringName(String(...))` cast in the same commit, so one of those two is
##      the trigger and this file no longer contains either. Every call site is
##      now a single-line array of plain `String`s, which is checkable.
##
## 1 and 2 were measured on their own: version 1 crashed, version 2 crashed, and
## `Callable(self, "_equip_draw_ready")` is clean. None of the three produced a
## diagnostic of any kind — the analyzer simply exits 139 — so none can be found
## by reading an error message. The only way to catch one is to read the CHECK's
## own exit status, which is exactly what got missed here the first time: the
## earlier check was piped through `head`, and the exit status read belonged to
## `head`, not to Godot.
func _equip_draw_ready() -> bool:
	var blend := float(combat.equip_blend)
	return bool(manager.get("drawing_in")) and blend >= 0.5 and blend < 0.999


func _past_settle(move_id: StringName) -> bool:
	var move := combat.moveset.get_move(move_id)
	if move == null or combat.active_move == null:
		return false
	return combat.state_time >= move.startup + move.strike * 0.55


func _ensure_idle() -> void:
	combat.finish_action()
	await _capture_for(0.2)


func _advance_to_cancel() -> bool:
	var guard := 0
	while guard < 300:
		if combat.state == CombatController.State.IDLE:
			return false
		if combat.active_move != null and bool(combat.call("_can_cancel", &"light")):
			return true
		await _capture_one()
		guard += 1
	return false


func _warm(frames: int) -> void:
	for i in frames:
		await physics_frame


# ===========================================================================
#  OVERLAY
# ===========================================================================

func _build_overlay() -> void:
	layer = CanvasLayer.new()
	layer.name = "MovieOverlay"
	layer.layer = 4
	sandbox.add_child(layer)

	shot_label = _label(26, HORIZONTAL_ALIGNMENT_LEFT)
	shot_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	shot_label.position = Vector2(48, 40)
	layer.add_child(shot_label)

	caption_label = _label(17, HORIZONTAL_ALIGNMENT_LEFT)
	caption_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	caption_label.position = Vector2(48, 76)
	caption_label.modulate = Color(0.86, 0.93, 0.97, 0.92)
	layer.add_child(caption_label)

	note_label = _label(15, HORIZONTAL_ALIGNMENT_LEFT)
	note_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	note_label.position = Vector2(48, -72)
	note_label.modulate = Color(0.78, 0.88, 0.94, 0.92)
	layer.add_child(note_label)


func _label(size: int, align: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	# Shadowed rather than panelled, for the same reason the weapon indicator is:
	# this has to stay readable over a bright courtyard without becoming interface.
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _clear_frames() -> void:
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with("frame_") or file.begins_with("still_") or file == "fps.txt":
			dir.remove(file)


func _write_fps(fps: float) -> void:
	var file := FileAccess.open("%s/fps.txt" % output_dir, FileAccess.WRITE)
	if file == null:
		push_error("could not write fps.txt")
		return
	file.store_string("%.4f\n" % fps)
