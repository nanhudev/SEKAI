extends SceneTree
##
## SWORD AUDIO PASS 01 - the sword's new voice, captured from the real bus.
##
## TWO MODES, ONE FILE, because they share the only thing that is expensive to get
## right: what the player actually did, and in what order.
##
##   movie   Real time, first person, in the Combat Sandbox. Saves the PNG sequence
##           AND records the SFX bus to a wav in the same pass, so the picture and
##           the sound are the same take - not two runs glued together at the
##           encoder, which is how a "sync problem" gets invented that nobody can
##           reproduce.
##   cues    The cue TABLE, played alone: every cue in the director, three passes,
##           spatial cues at two placements. No rendering. This is the audition the
##           film cannot do - see `_run_cue_sheet`.
##   sheet   No rendering, no sandbox, no controller. Plays every group the SWORD
##           CUE TABLE references, one atom at a time. This is the DRY ATOM SHEET:
##           the material, not the performance.
##
## WHY THE BUS AND NOT A TIMELINE MIX. See audio_bus_capture.gd: the CONTACT layer
## is spatial, and the brief's question F is whether a hit arrives from the target's
## direction. A mono re-mix of the same cue ids would answer a different question
## and look like a pass.
##
## WHAT THIS FILE KNOWS THAT ISN'T OBVIOUS. Each of these cost a take:
##   * The combo grace window is 0.30-0.52 s. A beat that waits a full second
##     between presses does not shoot a three-hit combo; it shoots the FIRST cut
##     three times, which is the one thing this pass exists to disprove.
##   * A heavy is entered through CHARGE and released by the INPUT being let go.
##     `release_heavy()` from anywhere else does nothing at all, silently.
##   * `for .. in 3: request()` is not a combo either. The controller BUFFERS a
##     press that arrives mid-swing for 0.15 s and drops it if the cancel window
##     has not opened by then, so the take asks every frame - which is what a
##     player does - and stops asking the moment it is accepted.
##   * The dummy's AttackHitbox sits at local +Z, so `look_at` swings it AWAY from
##     the player. Every parry take in the older renderer produced zero perfect
##     guards for exactly this reason. It is aimed at the MIRROR of the player.
##
## Usage:
##   godot --path godot --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/sword_audio_pass.gd -- <out_dir> movie
##   godot --headless --path godot --audio-driver Dummy \
##         --script res://tools/sword_audio_pass.gd -- <out_dir> cues
##   godot --headless --path godot --audio-driver Dummy \
##         --script res://tools/sword_audio_pass.gd -- <out_dir> sheet
##
## NEVER with `--headless` in movie mode: the capture loop waits on the viewport's
## `frame_post_draw`, and a headless run has no rendering device, so it hangs
## forever rather than failing.

const OUT_DEFAULT := "res://../.render/sword_audio"
const PLAYER_Y := 1.15
const DUMMY_DROP := 0.55
## Where a contact prop stands in front of the player. The sword's own reach is
## ~2 m; 1.75 m puts the blade into the face of the box at full extension.
const PROP_REACH := 1.75
const PARKED := Vector3(0.0, -60.0, 0.0)
## Loaded by PATH rather than by `class_name`. This file has to run in whatever
## worktree currently holds the project, and a global class cache that has not been
## regenerated yet turns `AudioBusCapture.new()` into a null - which reads as "the
## take produced no sound" rather than as a build problem.
const BusCapture := preload("res://scripts/audio/audio_bus_capture.gd")
const AtomRegistry := preload("res://scripts/audio/sound_atom_registry.gd")
## Wall-clock ceiling on "wait until the controller accepts the input".
const CHAIN_TIMEOUT := 0.9
## How far to the player's right the off-axis contact probe puts its target.
const OFF_AXIS_YAW := 32.0
## Silence between two isolated cue plays in the cue sheet. Long enough that a cue's
## own tail is over before the next one starts - which is the entire reason the cue
## sheet exists: a film measures cues overlapped, and "this contact is 6 dB under a
## light swing" cannot be told apart from "this contact is loud and its beat included
## the previous cut's tail" until the cues are measured alone.
const CUE_GAP := 1.45

var mode := "movie"
var output_dir := ""
var frame_index := 0
var sandbox: Node3D
var player: CharacterBody3D
var combat: CombatController
var dummy: Node3D
var look_pivot: Node3D
var audio: CombatAudioDirector
var capture: RefCounted
var label: Label
var caption := ""
var props: Dictionary = {}
var notes: Array[String] = []
## One row per beat: start, end, caption, the cue the beat claims, and whether the
## recording actually contains it. This is the index a reviewer listens against.
var beats: Array[String] = []
var _cue_seq_watch := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output_dir = String(args[0]) if args.size() > 0 else ProjectSettings.globalize_path(OUT_DEFAULT)
	mode = String(args[1]) if args.size() > 1 else "movie"
	DirAccess.make_dir_recursive_absolute(output_dir)

	if mode == "sheet":
		await _run_sheet()
		return

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# A covered window stops firing frame_post_draw and the capture loop hangs. The
	# cue sheet renders nothing, so it runs headless and must not ask a headless
	# DisplayServer for window behaviour it does not have.
	if mode == "movie" and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		DisplayServer.window_move_to_foreground()
	# The machine must stay quiet while it renders. The tap sits ON the SFX bus,
	# so the recording is upstream of this and is unaffected.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

	sandbox = load("res://scenes/combat/CombatSandbox.tscn").instantiate() as Node3D
	window.add_child(sandbox)
	for i in 3:
		await process_frame

	player = sandbox.get_node("Player") as CharacterBody3D
	combat = player.get_node("CombatController") as CombatController
	dummy = sandbox.get_node_or_null("TechnicalDummy")
	look_pivot = player.get_node("CameraRig/LookPivot") as Node3D
	audio = sandbox.get_node_or_null("CombatAudioDirector") as CombatAudioDirector

	# The stage belongs to the person playing, not to the recording.
	for node_name in [&"DeveloperPanel", &"ParryDebugOverlay", &"CombatHUD", &"IaidoScreenFX"]:
		var node := sandbox.get_node_or_null(NodePath(String(node_name)))
		if node is CanvasLayer or node is Control:
			(node as Node).set("visible", false)
	var fg := sandbox.get_node_or_null("ForegroundWeaponLayer")
	if fg != null:
		fg.set("visible", true)

	if audio == null:
		_fail("no CombatAudioDirector in the sandbox - the sword has no voice to record")
		return
	audio.show_debug_overlay = false
	if dummy != null:
		dummy.set("attack_cooldown", 9999.0)
	player.set("unlimited_resources", true)
	for unit_name in [&"WindProps", &"MovementLane", &"ExecutionLab"]:
		var unit := sandbox.get_node_or_null(NodePath(String(unit_name)))
		if unit != null:
			(unit as Node).set("visible", false)

	_build_props()
	_build_caption()

	capture = BusCapture.new()
	if not capture.begin("%s/sword_performance_pass01.wav" % output_dir, &"SFX", 16.0):
		_fail(capture.error)
		return
	if mode == "cues":
		# Same file name and same beat-map shape as the film on purpose: the cue
		# sheet IS a take, and the reviewer that reads one reads both.
		await _run_cue_sheet()
		quit()
		return
	print("rendering sword audio pass 01 to: %s" % output_dir)

	await _run()
	quit()


# --------------------------------------------------------------- performance

## The take. Every beat is a caption, ONE step sequence, and the stretch of frames
## that follow it. Multi-step moments (a charge, a guard that has to be up before
## the swing arrives) are separate beats on purpose: `_advance` is the only place
## frames and audio are captured, so a beat that needed its own inner loop would
## need its own copy of that, and the copy is where a desync hides.
func _run() -> void:
	var begin := Time.get_ticks_msec()

	await _beat("IDLE · 剑在手", 1.20, &"", func() -> void:
		combat.finish_action()
		_stand(Vector3(0.0, PLAYER_Y, 0.0), 0.0, -6.0)
		_park_all())

	# --- LIGHT 1 / 2 / 3, WHIFF. THE THREE BEATS ARE ONE COMBO, and the gaps are
	# short on purpose: the style's combo grace is 0.30-0.52 s, so a take that
	# waits a second between presses is not shooting a three-hit combo at all.
	await _beat("LIGHT 1 · 挥空  — 开句：空气是身份，金属不出现", 0.34, &"sword_light_1", func() -> void:
		_park_all()
		await _chain_press(&"light"))
	await _beat("LIGHT 2 · 挥空  — 借前一刀的势", 0.34, &"sword_light_2", func() -> void:
		await _chain_press(&"light"))
	await _beat("LIGHT 3 · 挥空  — 收招：有重量，但不是爆炸", 1.30, &"sword_light_3", func() -> void:
		await _chain_press(&"light"))

	# --- THE SAME THREE, CONNECTING. The world answers, and the answer is a
	# material rather than a louder version of the air.
	await _beat("LIGHT 1 · 命中  — 空气 + 身体", 0.34, &"sword_light_1", func() -> void:
		_place_dummy(2.05)
		await _chain_press(&"light"))
	await _beat("LIGHT 2 · 命中", 0.34, &"sword_light_2", func() -> void:
		await _chain_press(&"light"))
	await _beat("LIGHT 3 · 命中  — 收招落地", 1.30, &"sword_light_3", func() -> void:
		await _chain_press(&"light"))

	# --- HEAVY IS TWO MOMENTS. The wind-up is quiet because it is the body
	# coiling; the release is where it gets wide. One cue for both is a Heavy with
	# no anticipation and nothing to release.
	await _beat("HEAVY · 蓄力  — 只有布与握把；破风还没开始", 1.00, &"sword_heavy_windup", func() -> void:
		_park_all()
		_stand(Vector3(0.0, PLAYER_Y, 0.0), 0.0, -6.0)
		_hold_heavy_charge())
	await _beat("HEAVY · 释放  — 现在才变宽", 1.70, &"sword_heavy_release", func() -> void:
		await _end_charge())

	await _beat("HEAVY · 命中 · 蓄力", 1.00, &"sword_heavy_windup", func() -> void:
		_place_dummy(2.15)
		_hold_heavy_charge())
	await _beat("HEAVY · 释放命中  — 重量之后才是材质", 1.80, &"sword_heavy_release", func() -> void:
		await _end_charge())

	# --- DEFENSE. A block and a perfect guard are the pair the brief says a player
	# must be able to tell apart with their eyes shut, so they are shot back to
	# back, from the same stand, against the same swing. The ONLY difference is
	# WHEN the swing arrives: a normal block is a guard that has been up for half a
	# second, a perfect guard is one that goes up on the same frame.
	await _beat("BLOCK · 举盾（刀还在路上）", 0.50, &"", func() -> void:
		_setup_parry_stage())
	await _beat("BLOCK · 接刀  — 钝、重、刃没咬住，尾巴很短", 1.10, &"sword_block", func() -> void:
		_enemy_hitbox(true))
	await _beat("", 0.25, &"", func() -> void:
		_enemy_hitbox(false))

	await _beat("PERFECT GUARD · 举盾与刀同一帧  — 更亮、更锐、然后就没了", 0.40, &"sword_perfect_guard", func() -> void:
		_setup_parry_stage()
		# The 0.12 s window: the swing has to arrive on the FIRST frame the guard
		# is up, so the hitbox goes live in the same breath as the state change.
		_enemy_hitbox(true))
	await _beat("", 0.25, &"", func() -> void:
		_enemy_hitbox(false))
	if combat.perfect_guard_count <= 0:
		_note("!! perfect guard never landed - the timing beat produced no success")

	# --- RIPOSTE: the advantage the perfect guard just bought, being spent. The
	# window is 0.75 s and it opens only in IDLE / PARRY, so the guard is dropped
	# first - and the beat is short, because a beat that admires the guard for
	# longer than the reward lasts is a beat with no riposte in it.
	await _beat("RIPOSTE · 反斩  — 刚才那一格挡兑现成的一刀", 1.30, &"sword_riposte", func() -> void:
		combat.finish_action()
		await _chain_press(&"light", 0.60))

	# --- MATERIAL (§PART F). Four substances, one swing each, from the same stand
	# and one combo step - the swings are a second apart, so the chain has expired
	# and all four are LIGHT 1. If the four do not read as four, the fix is in the
	# mix, not in the caption.
	await _beat("CONTACT · STONE  — 石屑 + 刃口，不是锤子", 1.40, &"sword_contact_stone", func() -> void:
		_place_prop(&"stone")
		await _chain_press(&"light"))
	await _beat("CONTACT · WOOD  — 干切 + 木裂", 1.40, &"sword_contact_wood", func() -> void:
		_place_prop(&"wood")
		await _chain_press(&"light"))
	await _beat("CONTACT · METAL  — 硬瞬态 + 短鸣", 1.40, &"sword_contact_metal", func() -> void:
		_place_prop(&"metal")
		await _chain_press(&"light"))
	await _beat("CONTACT · ICE  — 刃撞上冻结物", 1.40, &"sword_contact_ice", func() -> void:
		_place_prop(&"ice")
		await _chain_press(&"light"))

	# --- THE OFF-AXIS PROBE (question F). The same material and the same swing, with
	# the target moved 32 degrees to the player's right. If the contact layer really
	# is a point in the world, the recorded stereo changes and the right channel wins;
	# if it is a player-layer sound wearing a 3D player, this beat is a mono copy of
	# the METAL beat above and the brief's question F is answered NO.
	await _beat("CONTACT · METAL · 右侧 32°  — 刀声应当从右边来", 1.40, &"sword_contact_metal", func() -> void:
		_place_prop(&"metal", OFF_AXIS_YAW)
		await _chain_press(&"light"))

	# --- SHATTER. A frozen body broken BY A BLADE, not a window.
	await _beat("FROZEN · 冻结（还没碎）", 0.50, &"", func() -> void:
		_place_dummy(2.15)
		dummy.call("freeze_for_debug"))
	await _beat("FROZEN → HEAVY · 蓄力  — 冰层还没碎", 1.00, &"sword_heavy_windup", func() -> void:
		_hold_heavy_charge())
	await _beat("SHATTER · 是冰被砍碎，不是玻璃", 2.00, &"sword_shatter", func() -> void:
		await _end_charge())

	await _beat("IDLE · 收", 1.20, &"", func() -> void:
		_park_all()
		combat.finish_action())

	var elapsed := float(Time.get_ticks_msec() - begin) / 1000.0
	var seconds: float = capture.finish()
	var fps := float(frame_index) / maxf(elapsed, 0.001)
	print("frames=%d  wall=%.2fs  audio=%.2fs  -> ENCODE_FPS=%.3f" % [
		frame_index, elapsed, seconds, fps])
	_write_text("fps.txt", "%.4f\n" % fps)
	var report := {
		"mode": mode,
		"frames": frame_index,
		"wall_seconds": elapsed,
		"audio_seconds": seconds,
		"fps": fps,
		"perfect_guards": combat.perfect_guard_count,
		"hits_landed": combat.hits_landed,
		"cue_seq": audio.cue_seq,
		"notes": notes,
	}
	_write_beat_map("beats.tsv")
	_write_text("capture.json", JSON.stringify(report, "  "))
	print("perfect_guards=%d  hits=%d  cues=%d  notes=%d" % [
		combat.perfect_guard_count, combat.hits_landed, audio.cue_seq, notes.size()])
	for row in beats:
		print("    %s" % row)
	for note in notes:
		print("  %s" % note)


## The beat map, with its header. Column order is fixed so a reviewer can diff two
## takes against each other instead of reading them.
func _write_beat_map(name: String) -> void:
	var lines: Array[String] = ["start\tend\tbeat\texpected\tfired"]
	lines.append_array(beats)
	_write_text(name, "\n".join(lines) + "\n")


## A caption, one step sequence, and the frames that follow it. `expect` is checked
## AFTER the wait, because a cut's cue fires on `swing_started` - several frames
## after the input that asked for it - so a check made at press time would report a
## failure for every beat in the take.
##
## Every beat also writes its own SLICE OF THE RECORDED WAV into `beats.tsv`, in the
## recording's own clock rather than the wall clock. Without it, reviewing the take
## means guessing which second of 26 is the perfect guard, and "did I actually hear
## the difference" turns into "I think that was the one" - which is not a verdict.
func _beat(title: String, seconds: float, expect: StringName, action: Callable) -> void:
	if title != "":
		caption = title
		print("--- %s" % title)
	_cue_seq_watch = audio.cue_seq
	var started := _take_time()
	await action.call()
	await _wait(seconds)
	var fired := "-"
	if expect != &"":
		fired = "YES" if _expect(expect) else "NO"
	beats.append("%.2f\t%.2f\t%s\t%s\t%s" % [
		started, _take_time(), caption, String(expect), fired])


## Where the take is, in the recording's own clock. `frames_written / mix_rate` is
## the position inside `sword_performance_pass01.wav`, so a beat's numbers index the
## file a reviewer will actually open - not the wall clock, which is off by however
## long Godot took to start up before the tap opened.
func _take_time() -> float:
	return float(capture.frames_written) / float(maxi(capture.mix_rate, 1))


## One rendered frame, captured once, with the audio drained on the same tick. Every
## wait in this file goes through here so there is exactly one place that can be
## wrong about the order of "render, save, drain".
func _advance() -> void:
	if mode == "movie":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save()
	else:
		await process_frame
	capture.drain()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await _advance()


# -------------------------------------------------------------------- driving

## Press the cut the way a player does: keep asking every frame until the
## controller takes it, then stop. The controller buffers a press that arrives
## mid-swing for `tuning.input_buffer` (0.15 s) and DROPS it if the chain has not
## reopened - so asking once and trusting it is how a three-hit take becomes three
## first hits, and asking every frame is both what a mashing player does and proof
## that the chain advanced.
func _chain_press(action: StringName, timeout := CHAIN_TIMEOUT) -> void:
	# A long idle auto-sheathes the sword, and a SHEATHED cut is a different move
	# (draw + cut, scaled startup). Every light in this take has to be the same
	# technique at a different combo step, so the blade is held out first.
	combat.sheath_amount = 0.0
	var until := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < until:
		if combat.request(action):
			print("    %s accepted (kind=%s combo=%d)" % [
				String(action), String(combat.attack_kind), combat.combo_index])
			return
		await _advance()
	_note("!! %s was never accepted within %.2fs" % [String(action), timeout])


## The charge is held by the INPUT, not by us - `_process_charge` releases by itself
## the moment the action is no longer pressed and the charge is full, which is
## exactly how a held-and-released heavy works for a player. Doing it this way is
## also what gives the wind-up time to be a wind-up: a heavy nobody is holding
## releases after `heavy_tap_grace` (0.18 s) and the release lands on top of the
## cue that was supposed to precede it.
func _hold_heavy_charge() -> void:
	_press(&"heavy")
	if combat.state == CombatController.State.CHARGE:
		Input.action_press(&"heavy_attack")


func _end_charge(timeout := 0.60) -> void:
	Input.action_release(&"heavy_attack")
	var until := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < until:
		if combat.state != CombatController.State.CHARGE:
			return
		await _advance()
	_note("!! the charge never released")


func _press(action: StringName) -> void:
	if not combat.request(action):
		_note("!! %s refused" % String(action))


## Did this beat actually produce the sound it claims? The chain capture was written
## to catch exactly this failure and it caught one; the same check belongs here.
##
## Compared against a MONOTONIC sequence number rather than against "is it in the
## last eight": a take has to be able to say the cue has not happened YET, and a
## bounded ring of ids answers that with a stale match that reads like a pass.
func _expect(cue_id: StringName) -> bool:
	for entry in audio.history:
		if int(entry["seq"]) > _cue_seq_watch and String(entry["cue"]) == String(cue_id):
			return true
	_note("!! no %s - the beat had no voice" % String(cue_id))
	return false


func _stand(at: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	if look_pivot != null:
		look_pivot.rotation.x = deg_to_rad(pitch_deg)


func _place_dummy(distance: float) -> void:
	if dummy == null:
		_note("!! no TechnicalDummy")
		return
	_park_all()
	var forward := -player.global_transform.basis.z
	dummy.global_position = player.global_position + forward * distance + Vector3.DOWN * DUMMY_DROP
	dummy.set("attack_cooldown", 9999.0)
	dummy.call("reset_dummy")
	dummy.set("attack_cooldown", 9999.0)
	_aim_attack_at_player(dummy)


## Both defense beats are shot from the same stand, against the same swing, staged
## the same way - otherwise "Block vs Perfect Guard" compares two takes rather than
## two sounds.
func _setup_parry_stage() -> void:
	_park_all()
	_stand(Vector3(0.0, PLAYER_Y, 0.0), 0.0, -4.0)
	combat.finish_action()
	if dummy == null:
		return
	var forward := -player.global_transform.basis.z
	dummy.global_position = player.global_position + forward * 1.5 + Vector3.DOWN * DUMMY_DROP
	dummy.call("reset_dummy")
	dummy.set("attack_cooldown", 9999.0)
	_aim_attack_at_player(dummy)
	# `set_state` rather than `request(&"block")`: it is public, it is what the
	# combat renderer already uses, and it puts the guard up on THIS frame - which
	# is the whole difference between the two beats that follow.
	combat.set_state(CombatController.State.BLOCK)


## The dummy's AttackHitbox sits at local +Z, so `look_at` (which points -Z at its
## target) swings the hitbox AWAY from the player - the reason every parry take in
## the older renderer silently produced no perfect guard at all. Aim the node at the
## MIRROR of the player instead, so its +Z lands on them.
func _aim_attack_at_player(actor: Node3D) -> void:
	var toward_player := Vector3(
		player.global_position.x, actor.global_position.y, player.global_position.z)
	var mirror := actor.global_position * 2.0 - toward_player
	actor.look_at_from_position(actor.global_position, mirror, Vector3.UP)


func _enemy_hitbox(enabled: bool) -> void:
	if dummy == null:
		return
	var hb: CombatHitbox = dummy.get_node_or_null("AttackHitbox") as CombatHitbox
	if hb != null:
		hb.set_active(enabled)


func _park_all() -> void:
	if dummy != null:
		dummy.global_position = PARKED
	for key in props:
		(props[key] as Node3D).global_position = PARKED


func _note(text: String) -> void:
	notes.append(text)
	print("    %s" % text)


# -------------------------------------------------------------------- props

## The material system needs things to hit. These are NOT shipped content and they
## are not a scene edit: the take builds them, and each one declares itself the way
## a crate in the world would - by being in a group.
##
## That is the entire interface `CombatAudioDirector._surface_of` asks for, which is
## why the material system needed ZERO changes to combat code.
func _build_props() -> void:
	var specs := {
		&"stone": {"tint": Color(0.42, 0.42, 0.45)},
		&"wood": {"tint": Color(0.52, 0.37, 0.22)},
		&"metal": {"tint": Color(0.55, 0.58, 0.64)},
		&"ice": {"tint": Color(0.68, 0.86, 0.95)},
	}
	var size := Vector3(0.95, 2.10, 0.70)
	var root_node := Node3D.new()
	root_node.name = "AudioContactProps"
	sandbox.add_child(root_node)
	for material in specs:
		var spec: Dictionary = specs[material]
		var prop := StaticBody3D.new()
		prop.name = "Prop%s" % String(material).capitalize()
		prop.add_to_group("surface_" + String(material))
		# INTO THE TREE FIRST, before anything is positioned. A node that is not in
		# the tree has no transform and no physics server body, so an orphan prop
		# silently produces no rendering, no collision and no hurtbox overlap - and
		# the only symptom is that the four material beats have no voice, which
		# reads exactly like a broken material SYSTEM.
		root_node.add_child(prop)
		# The box is built UPWARD from the prop's origin, so a prop standing on the
		# deck at y 0 spans 0..2.1 and a cut at chest height lands in it. A centred
		# mesh with an offset collider would put the visible box half under the
		# floor, which is the kind of thing a video makes look like a physics bug.
		var lift := Vector3(0.0, size.y * 0.5, 0.0)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.position = lift
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec["tint"]
		mat.roughness = 0.8
		mesh.material_override = mat
		prop.add_child(mesh)
		var body_shape := CollisionShape3D.new()
		var body_box := BoxShape3D.new()
		body_box.size = size
		body_shape.shape = body_box
		body_shape.position = lift
		prop.add_child(body_shape)
		CombatHurtbox.build_for(prop, size, lift)
		prop.global_position = PARKED
		props[material] = prop


## `yaw_deg` swings the prop around the player: 0 = dead ahead, positive = to the
## player's RIGHT. The off-axis probe exists because the CONTACT layer's whole claim
## (PART M) is that a hit arrives FROM the target - and a target directly in front
## pans to the centre, so every spatial contact would read as a pass whether or not
## the panner was doing anything at all.
func _place_prop(material: StringName, yaw_deg := 0.0) -> void:
	_park_all()
	var prop: Node3D = props.get(material)
	if prop == null:
		_note("!! no %s prop" % String(material))
		return
	var basis := player.global_transform.basis
	var dir := -basis.z
	if not is_zero_approx(yaw_deg):
		var a := deg_to_rad(yaw_deg)
		dir = (dir * cos(a) + basis.x * sin(a)).normalized()
	prop.global_position = player.global_position + dir * PROP_REACH + Vector3.DOWN * PLAYER_Y


# ------------------------------------------------------------------- capture

func _save() -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport returned no image at frame %d" % frame_index)
		return
	_update_caption()
	var err := image.save_png("%s/frame_%04d.png" % [output_dir, frame_index])
	if err != OK:
		push_error("save_png failed (%d) at frame %d" % [err, frame_index])
	frame_index += 1
	if frame_index % 120 == 0:
		print("    frame %d" % frame_index)


func _write_text(name: String, text: String) -> void:
	var file := FileAccess.open("%s/%s" % [output_dir, name], FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _build_caption() -> void:
	label = Label.new()
	label.position = Vector2(48.0, 44.0)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.90))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(label)


func _update_caption() -> void:
	if label != null:
		label.text = caption


# ---------------------------------------------------------------- cue sheet

## THE AUDITION A FILM CANNOT DO.
##
## A performance take measures each cue as it arrives: overlapped with the one before
## it, sitting on that cue's tail, at whatever level the beat left behind. That is the
## right way to judge the FILM and the wrong way to judge the TABLE. A contact cue
## that measures 6 dB under a light swing is either a quiet contact or a loud contact
## whose beat included the previous cut's tail, and the film cannot say which.
##
## So this plays every cue in the table ALONE, three times, and writes the same
## `beats.tsv` the film writes so `audio_source/tools/review_take.py` reads both.
##
## Three passes because a cue picks one variant per atom per play - the cursor is a
## round robin - so a single play of `sword_light_2` only ever shows one of its three
## seeds, and pass 01 measured a family where one seed was a different sound.
##
## Placement is per cue: a SPATIAL cue is played both dead ahead and 32 degrees right.
## The dead-ahead reading is a control, and it is the only thing that makes the
## off-axis reading mean anything - 0.0 dB there says the panner is alive, and a
## non-zero reading there says the "direction" was never the source's doing.
func _run_cue_sheet() -> void:
	_stand(Vector3(0.0, PLAYER_Y, 0.0), 0.0, 0.0)
	var basis := player.global_transform.basis
	var ahead := player.global_position + (-basis.z) * PROP_REACH
	var angle := deg_to_rad(OFF_AXIS_YAW)
	var off := player.global_position \
		+ ((-basis.z) * cos(angle) + basis.x * sin(angle)) * PROP_REACH

	var ids := audio.cue_ids()
	var plays := 0
	var missing: Array[String] = []
	var layer_lines: Array[String] = []
	print("--- CUE SHEET (%d cues, %d passes)" % [ids.size(), 3])
	for cue_id in ids:
		var cue := audio.cues.get(cue_id) as SfxCue
		if cue == null:
			missing.append(String(cue_id))
			continue
		var spots: Array[Vector3] = [ahead]
		if cue.spatial:
			spots.append(off)
		for pass_index in 3:
			for spot in spots:
				var label := String(cue_id)
				if spots.size() > 1:
					label += "  @%s" % ("ahead" if spot == ahead else "right")
				# The PASS is part of the caption, not just of the console line. A
				# cue label alone is ambiguous: three passes are three different mixes
				# (each play advances the variant cursor), and a reviewer - or a tool -
				# that groups by label silently sums all three.
				var caption := "%s  pass %d" % [label, pass_index + 1]
				_cue_seq_watch = audio.cue_seq
				var started := _take_time()
				audio.play_cue_at(cue_id, spot)
				await _wait(CUE_GAP)
				var fired := "YES" if _expect(cue_id) else "NO"
				beats.append("%.2f\t%.2f\t%s\t%s\t%s" % [
					started, _take_time(), caption, String(cue_id), fired])
				# THE RESOLVED MIX, not the authored one. `fired = YES` only says the
				# cue was REQUESTED; a layer can be silently skipped (no atoms in its
				# group, no stream, no free voice) and the cue still counts as fired.
				# A cue that measures dark cannot be diagnosed from the table alone -
				# the table says air_fast sits at 0 dB, and the recording says
				# metal_body is what you hear.
				for sounded in audio.sfx.last_layers:
					layer_lines.append("%s\t%s\t%s\t%.2f\t%.3f\t%.3f" % [
						caption, String(sounded["group"]), String(sounded["atom"]),
						float(sounded["gain_db"]), float(sounded["pitch"]),
						float(sounded["delay"])])
				plays += 1
				print("  %-34s pass %d  %s" % [label, pass_index + 1, fired])
	_write_beat_map("beats.tsv")
	_write_text("layers.tsv", "cue\tgroup\tatom\tgain_db\tpitch\tdelay\n"
		+ "\n".join(layer_lines) + "\n")
	# Let the last cue's tail land inside the recording rather than after it.
	await _wait(CUE_GAP)
	var seconds: float = capture.finish()
	_write_text("cues.txt", "cues=%d\nplays=%d\nmissing=%s\nnotes=%s\nseconds=%.2f\n" % [
		ids.size(), plays, ", ".join(missing) if not missing.is_empty() else "-",
		"\n".join(notes) if not notes.is_empty() else "-", seconds])
	print("cues=%d  plays=%d  seconds=%.2f  -> %s/sword_performance_pass01.wav" % [
		ids.size(), plays, seconds, output_dir])
	for name in missing:
		print("  MISSING CUE: %s" % name)


# ---------------------------------------------------------------- dry sheet

## Audition sheet: the material, group by group, before any performance is trusted.
## The group list is read from the CUE TABLE rather than kept here, so "a group the
## language asks for but the library does not have" is a printed failure instead of
## a silent one, and a layer added to a cue shows up in the sheet the next time it
## runs without anyone remembering to add it here.
func _run_sheet() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var registry: Node = AtomRegistry.new()
	registry.name = "SoundAtomRegistry"
	root.add_child(registry)
	await process_frame

	capture = BusCapture.new()
	if not capture.begin("%s/sword_atoms_dry.wav" % output_dir, &"SFX", 16.0):
		_fail(capture.error)
		return

	var player_2d := AudioStreamPlayer.new()
	player_2d.bus = &"SFX"
	root.add_child(player_2d)

	var wanted := {}
	for cue in CombatAudioCues.build().values():
		for layer in (cue as SfxCue).layers:
			wanted[layer.group] = true
	var groups: Array = wanted.keys()
	groups.sort()

	var absent: Array[String] = []
	for group in groups:
		if not registry.has_group(group):
			absent.append(String(group))

	var played := 0
	print("--- DRY ATOM SHEET (%d sword groups, %d missing)" % [groups.size(), absent.size()])
	for group in groups:
		var ids: Array = registry.group_ids(group)
		if ids.is_empty():
			print("  %-22s MISSING - the cue asks for it and the library has nothing" % String(group))
			continue
		print("  %-22s %d atom(s)" % [String(group), ids.size()])
		for atom_id in ids:
			var atom: SoundAtom = registry.atom(atom_id)
			if atom == null or atom.stream == null:
				continue
			player_2d.stream = atom.stream
			# `base_gain_db` is the perceptual trim, so every atom in the sheet is
			# compared at the same loudness it will have in a cue. Playing the raw
			# file would make the sheet a tour of which render peaked hottest.
			player_2d.volume_db = atom.base_gain_db
			player_2d.pitch_scale = 1.0
			player_2d.play()
			played += 1
			await _wait(0.52)
		await _wait(0.42)

	var seconds: float = capture.finish()
	_write_text("sheet.txt", "groups=%d\natoms=%d\nmissing=%s\nseconds=%.2f\n" % [
		groups.size(), played, ", ".join(absent) if not absent.is_empty() else "-", seconds])
	print("atoms=%d  missing=%d  seconds=%.2f  -> %s/sword_atoms_dry.wav" % [
		played, absent.size(), seconds, output_dir])
	for name in absent:
		print("  MISSING GROUP: %s" % name)
	quit()


func _fail(why: String) -> void:
	push_error("sword audio pass: %s" % why)
	print("sword audio pass FAILED: %s" % why)
	quit()
