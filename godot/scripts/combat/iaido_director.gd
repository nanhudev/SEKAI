extends Node
class_name IaidoDirector
# SEKAI · Iaido / 聚合斩 — signature skill director (V4).
#
#    0.00  A  WORLD SILENCE         the world is switched off
#    0.30  B  RETURN TO HIP         the blade walks home to a real saya
#    1.30  C  REVERSE COMPRESSION   three shells, each faster than the last
#    2.75  D  ABSOLUTE STILLNESS    0.60s of nothing. this is the point.
#    3.29  E  SEAT                  the last 5cm go home against the mouth
#    3.35  E  SHEATH CLICK          click, then 120ms of silence
#    3.47  F  INSTANT DRAW          100ms, against three seconds of waiting
#    3.57  G  WORLD SPLIT           a slit opens and the halves slide
#    4.05  H  VOID READABLE         the wound, exposed
#    4.45  I  HERO FREEZE FRAME     150ms. this frame has to work as a still.
#    4.60  J  STRESS                cracks grow; 3 panes come loose at 5.05
#    5.00  K  TWO WRIST ARCS        wide+fast, then tight+slow
#    6.20  L  RETURN TO SHEATH      the last 7cm crawl into the mouth
#    7.30  M  FINAL CLICK           then the glass collapses. not before.
#    8.05  N  RESTORE               drawn back in, reality reconnects
#
# The draw is one tenth of the runtime. Everything else exists to make that one
# tenth land. Do not "optimise" this by removing the holds.
#
# --- WHAT CHANGED IN V4 -----------------------------------------------------
#
# THE SWORD IS DRIVEN ALONG A BORE, NOT BETWEEN TWO POSES.
#
# V3 lerped the sword between `sheath_position` and `drawn_position`. Those are
# two pretty pictures, and a lerp between two pictures passes through neither a
# scabbard mouth nor anything else real — so the blade was "sheathed" by setting
# `blade.visible = false`, which is why the second half of the ceremony looked
# like a bug rather than like a sword going home.
#
# V4 anchors a real koiguchi at the left hip and parameterises the whole hip
# section by INSERTION DEPTH along the bore axis. At depth 1 the tsuba rests on
# the mouth and the blade is inside the tube — hidden by the scabbard's own
# walls, because the scabbard is a closed opaque mesh. Nothing is switched off.
# C2B-05 in docs/asset_briefs/ specifies the asset that drops into this anchor.

@export var tuning: IaidoTuning = preload("res://resources/tuning/IaidoTuning.tres")
@export var combat_tuning: IaidoTuning = preload("res://resources/tuning/IaidoCombatTuning.tres")
var _demo_tuning: IaidoTuning
var combat_cast := false
signal phase_changed(phase: StringName)
var combat_phase: StringName = &"Iaido_End"

## The measured seating geometry of the weapon being seated. See `_weapon_id()`.
const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var sword: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")
@onready var iaido_fx: IaidoScreenFX = get_parent().get_node("IaidoScreenFX")
@onready var glass_layer: IaidoGlassLayer = get_parent().get_node("IaidoGlassLayer")
@onready var audio_timeline: IaidoAudioTimeline = get_parent().get_node("IaidoAudioTimeline")
@onready var screen_fx: CombatScreenFX = get_parent().get_node("CombatScreenFX")
@onready var audio_state: AudioStateController = get_parent().get_node("AudioStateController")
@onready var pause_manager: WorldPauseManager = get_parent().get_node("WorldPauseManager")
@onready var sheath_anchor: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/SheathAnchor")
@onready var time_effects: TimeEffectManager = get_parent().get_node("TimeEffectManager")
@onready var collector: IaidoTargetCollector = get_parent().get_node("IaidoTargetCollector")
@onready var tear: IaidoTear3D = get_parent().get_node("IaidoTear3D")

var active := false
var elapsed := 0.0

# --- ABLATION SWITCHES ------------------------------------------------------
#
# §29 and §30 of the reality-crack brief ask for two tests that can only be run
# by TURNING THE EFFECT OFF:
#
#   TEST A  no crack network. If the split is still legible as a world cut in
#           two, pass. If it needs the cracks to be understood, the effect has
#           failed no matter how good the cracks are.
#   TEST B  no panes either — only the two halves, the hole and the broken edge.
#
# They are environment switches rather than tuning edits because the alternative
# is editing a number, rendering, and remembering to put it back, which is how a
# temporary hack ends up shipped. Both default to off, and neither changes any
# value that ships: with the variables unset the frame function is identical.
var suppress_crack := false
var suppress_glass := false
var suppress_vfx := false
# The split, as the world pass is drawing it this frame. The panes have to move
# with the same displacement or the glass heals the wound the moment it takes
# over the picture — which is exactly the bug that shipped: an uncut glass
# mosaic over a cut world.
var last_separation_px := 0.0
var last_split_shear := 0.50
var hold_time := -1.0
var playback_speed := 1.0
var target: Node3D
var targets: Array[Node3D] = []
# ---- 聚合斩 · EXECUTION ------------------------------------------------------
#
# ONE PLANE, TAKEN ONCE, AT THE INSTANT OF THE CUT.
#
# It is taken here because this is the only place that knows what the blade did:
# the world pass draws the cut as a screen line through `cut_center` at
# `cut_angle_degrees`, and `IaidoCutPlane` is that line's preimage in the world.
# Both the enemy's cross-section and the cut marks are then built from THIS, so
# "the world was cut on a diagonal and the enemy was cut at the waist" — the
# fault §B §2 names — is not a thing that can be authored by accident.
var cut_plane := IaidoCutPlane.none()
var executions: Array[IaidoExecution] = []
# §N · the three cues AUDIO asked for, drained by whoever owns sound.
var execution_events: Array[StringName] = []
# DEBUG ONLY. 0 = the timeline decides, 1 = force the signature to be lethal,
# 2 = force it not to be. The developer panel needs to be able to see both
# halves of §C and §G without editing an enemy's health by hand.
var debug_lethality := 0
var start_position := Vector3.ZERO
var previous_modes: Dictionary = {}
var events: Dictionary = {}
var target_marks: Array[MeshInstance3D] = []
var initial_sword_position := Vector3.ZERO
var initial_sword_rotation := Vector3.ZERO
var ceremony_scabbard: MeshInstance3D
var hud: CombatHUD

## The sword language's own saya (`SwordSayaRig`), if this player has one. See
## `_set_scabbard` — the ceremony and the basic-attack language are two owners
## of the same waist, and a live probe caught them both wearing it at once.
## Held so the path is walked once rather than every time the ceremony opens.
var _understudy_saya: Node3D = null

# The koiguchi, in WeaponRoot space. Rebuilt from the tuning resource rather
# than read off the scene, so retuning the wear angle does not require opening
# Player.tscn.
var seat_origin := Vector3.ZERO
var seat_basis := Basis.IDENTITY
var seat_euler := Vector3.ZERO

# PROBE SURFACE ONLY. Nothing in the ceremony reads these back; they exist so
# `tools/probe_iaido_recovery.gd` can tell the two halves of PHASE K apart --
# see §23, which says the blade is brought ONTO the bore and THEN the edge is
# brought to the slot. Those are the two numbers below, in degrees. Reading
# them separately is the difference between "the turn is the wrong size" and
# "the turn is about the wrong axis", and those two need opposite fixes.
var dbg_recovery_repoint_deg := 0.0
var dbg_recovery_roll_deg := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	playback_speed = tuning.debug_speed
	ceremony_scabbard = sheath_anchor.get_node_or_null("CeremonyScabbard") as MeshInstance3D
	hud = get_parent().get_node_or_null("CombatHUD") as CombatHUD
	# THE ABLATION SWITCHES, read once. See `suppress_crack` / `suppress_glass`.
	suppress_crack = OS.get_environment("SEKAI_NO_CRACK") != ""
	suppress_glass = OS.get_environment("SEKAI_NO_GLASS") != ""
	# One switch, both surfaces. The panes draw the same network the world pass
	# does, so an ablation that reaches only one of them is not an ablation.
	glass_layer.suppress_crack = suppress_crack
	_refresh_seat()
	_set_scabbard(false)


# The scabbard's frame is DERIVED, not authored as three opaque euler numbers:
# +Y is the bore (the direction the blade travels to go home) and -X is the side
# the cutting edge lies against. IaidoTuning.scabbard_basis() states that
# relationship, and this is the only place it is applied.
func _refresh_seat() -> void:
	seat_basis = tuning.scabbard_basis()
	seat_euler = seat_basis.get_euler()
	seat_origin = tuning.sheath_position
	sheath_anchor.position = seat_origin
	sheath_anchor.rotation = seat_euler


func start_iaido(use_combat_profile := false) -> void:
	if active:
		return
	combat_cast = use_combat_profile
	_demo_tuning = tuning
	if combat_cast:
		tuning = combat_tuning
	audio_timeline.configure(tuning, combat_cast)
	combat_phase = &"Iaido_Prepare"
	phase_changed.emit(combat_phase)
	if combat.sword_vfx != null:
		combat.sword_vfx.emit_weapon_event(&"IAIDO_START",{"duration":tuning.restore_end})
	_refresh_seat()
	time_effects.reset()
	targets = collector.collect_targets(player, camera)
	target = targets[0] if not targets.is_empty() else null
	# A new ceremony cuts a new plane. Anything left over from an aborted run is
	# resolved by `_hard_reset`, which is also what guarantees no body is still
	# standing when this line runs.
	cut_plane = IaidoCutPlane.none()
	execution_events.clear()
	start_position = player.global_position
	player.velocity = Vector3.ZERO
	elapsed = 0.0
	events.clear()
	active = true
	initial_sword_position = sword.position
	initial_sword_rotation = sword.rotation
	iaido_fx.reset_iaido_fx()
	glass_layer.build(tuning)
	audio_timeline.reset()
	tear.global_transform = Transform3D(camera.global_basis, camera.global_position)
	for node in [camera_feedback, sword]:
		previous_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_ALWAYS
	_set_scabbard(true)
	if sword.has_method("set_ceremony_mode"):
		sword.call("set_ceremony_mode", true)
	# Ambience is pulled out fast, then the world and music are frozen.
	# stream_paused keeps the music's playback position, so resume continues
	# from the exact bar where the world disappeared.
	audio_state.pause_music()
	audio_state.duck_world_audio()
	pause_manager.acquire()


func _process(delta: float) -> void:
	if not active:
		return
	if float(player.get("health")) <= 0.0:
		finish_iaido()
		return
	elapsed = hold_time if hold_time >= 0.0 else elapsed + delta / maxf(Engine.time_scale, 0.001) * playback_speed
	combat.state_time = elapsed
	var phase: StringName = &"Iaido_Prepare"
	if elapsed >= tuning.restore_end:
		phase = &"Iaido_End"
	elif elapsed >= tuning.spin_start:
		phase = &"Iaido_Sheath"
	elif elapsed >= tuning.cut_start:
		phase = &"Iaido_Strike"
	elif elapsed >= tuning.draw_start:
		phase = &"Iaido_Draw"
	if phase != combat_phase:
		combat_phase = phase
		phase_changed.emit(phase)
		if combat.sword_vfx != null:
			var event_name: StringName = {&"Iaido_Draw":&"IAIDO_DRAW",&"Iaido_Strike":&"IAIDO_SLASH",&"Iaido_Sheath":&"IAIDO_SHEATH"}.get(phase,&"")
			if event_name != &"":
				combat.sword_vfx.emit_weapon_event(event_name,{"timeline_time":elapsed})
	player.global_position = start_position
	player.velocity = Vector3.ZERO

	_update_camera()
	_update_world()
	_stage_executions()
	_apply_weapon_pose(elapsed)
	tear.global_transform = Transform3D(camera.global_basis, camera.global_position)
	tear.stage(elapsed, tuning)
	# TEST B — and §4's "only WORLD A / WORLD B / BLUE VOID" — needs the panes
	# gone. Set every frame rather than once, so it cannot be undone by whatever
	# else touches the layer's visibility.
	glass_layer.visible = not suppress_glass
	if not suppress_glass:
		glass_layer.stage(elapsed, tuning, last_separation_px, last_split_shear)
	audio_timeline.update(elapsed)
	_fire_events()
	if suppress_vfx:
		iaido_fx.visible = false
		screen_fx.visible = false
		glass_layer.visible = false
		tear.visible = false
		sword.click_flash.visible = false
	if elapsed >= tuning.restore_end and hold_time < 0.0:
		finish_iaido()


# --- camera ---------------------------------------------------------------
# The camera does NOT shake here. It goes unnaturally still: no bob, no sway,
# no micro tremor. The contrast with the fight a moment ago is the effect, and
# the only three impulses in the whole performance are the three story beats.

func _update_camera() -> void:
	var t := elapsed
	camera_feedback.iaido_still = _ctrack(t, _keys_still(), &"in_out")
	camera_feedback.fov_hold = _ctrack(t, _keys_fov(), &"in_out")
	# A half-degree breath into the draw, and it is measured on the STOPPED clock.
	#
	# This line has now been wrong in two different ways, and the second one is
	# the interesting one. It first ran from `hold_start`, so it was mid-ramp
	# while the world was supposed to be dead. Moving the start to
	# `time_stop_end` fixed THAT window and left the other one: the ramp then ran
	# 3.58 -> 4.78, which simply contains the second dead window (3.68-4.68), so
	# a half-degree tilt carried on through the one second that is supposed to be
	# absolutely nothing.
	#
	# It was caught by a pixel diff, not by reading the code: the grey+stop
	# window measured 0.00% of pixels moving and the one second measured 0.78%,
	# with every changed pixel sitting on a silhouette edge. Edge-only change
	# with flat regions untouched is a sub-pixel CAMERA shift and cannot be
	# anything else.
	#
	# Both the elapsed and the total are therefore taken on the stopped clock.
	# `since` is constant across a dead window, so the breath HOLDS at whatever
	# value it had when the window opened instead of running through it — which,
	# because the free time before the window is the free time after it, puts the
	# hold exactly at the half-degree peak. The camera takes a breath, the world
	# dies holding it, and it exhales into the draw. The shape is unchanged; only
	# the clock is.
	var breath_free := maxf(
		tuning.since(tuning.fov_pull_end, tuning.fov_pull_start), 0.0001)
	camera_feedback.iaido_pitch = deg_to_rad(0.45) * sin(
		clampf(tuning.since(t, tuning.fov_pull_start) / breath_free, 0.0, 1.0) * PI)
	# ---- THE THREE IMPULSES, EVALUATED FROM THE TIMELINE --------------------
	#
	# There are exactly three camera impulses in the whole ceremony and no
	# others: the vacuum at the end of the compression, the slash, and the
	# collapse. They used to be ADDED into an accumulator that decayed on real
	# frame delta, which was wrong twice over:
	#
	#   * the accumulator kept decaying through the time stops, so a camera that
	#     is supposed to stop dead mid-move carried on settling;
	#   * it made the frame a function of WALL time, so two renders of the same
	#     ceremony instant differed and the frozen windows could never be proven
	#     frozen — a pixel diff of the stop came back the same as a window where
	#     things are supposed to move.
	#
	# Summing the impulses on the ceremony clock fixes both, and it is cheaper.
	var framed := Vector2.ZERO
	for impulse in [
			[tuning.suck_end, Vector2(0.35, -0.65), tuning.wave_impulse],
			[tuning.draw_end, Vector2(0.55, -0.84), tuning.slash_impulse],
			[tuning.final_click, Vector2(0.58, -0.82), tuning.collapse_impulse]]:
		var at := float(impulse[0])
		if t < at:
			continue
		var falloff := exp(-tuning.since(t, at) * tuning.camera_impulse_decay)
		framed += (impulse[1] as Vector2).normalized() * float(impulse[2]) * falloff
	# ---- §J · THE ONE FRAMING BIAS THE DESIGN ALLOWS -------------------------
	#
	# After the click, the camera leans a few hundredths of a degree toward what
	# it killed, for a few frames, and then forgets. It never takes control: it
	# is capped, it decays, and — §J §10 — if the body is not already near the
	# frame it does NOT happen at all, because dragging the picture to something
	# the player was not looking at is the one thing that would make the ceremony
	# feel like it had stopped watching through their eyes.
	framed += _execution_settle(t)
	camera_feedback.iaido_frame = framed
	# The camera is pinned for EVERY dead window — both time stops and the hero
	# freeze frame. A stop that leaves the camera breathing is not a stop; a
	# frozen frame with a live camera is not a still.
	camera_feedback.iaido_frozen = tuning.clock_held(t)


# §J · the framing bias described above, evaluated from the timeline like every
# other camera quantity — so it freezes inside a dead window and two renders of
# the same instant agree.
func _execution_settle(t: float) -> Vector2:
	if executions.is_empty() or t < tuning.final_click:
		return Vector2.ZERO
	var body: Node3D = executions[0].actor
	if body == null or not is_instance_valid(body):
		return Vector2.ZERO
	var half := camera.get_viewport().get_visible_rect().size * 0.5
	var offset := (camera.unproject_position(body.global_position + Vector3.UP) - half) / maxf(half.length(), 1.0)
	# §J §10 — NOT IN FRAME, NOT PULLED. Measured, not guessed: the body has to
	# already be inside the middle of the picture for the lean to be allowed.
	if offset.length() > tuning.execution_settle_offset_limit:
		return Vector2.ZERO
	var falloff: float = exp(-tuning.since(t, tuning.final_click) * tuning.camera_impulse_decay)
	return offset.limit_length(1.0) * tuning.execution_settle * falloff


func _keys_still() -> Array[Vector2]:
	return [
		Vector2(tuning.silence_start, 0.0),
		Vector2(tuning.silence_end, 1.0),
		Vector2(tuning.restore_start, 1.0),
		Vector2(tuning.restore_end, 0.0),
	]


# The FOV steps with the compression instead of gliding: each shell that gets
# swallowed pushes the frame out a little further, and the last push is the
# sheath lock.
func _keys_fov() -> Array[Vector2]:
	return [
		Vector2(tuning.silence_start, 0.0),
		Vector2(tuning.silence_end, tuning.silence_fov),
		Vector2(tuning.ring1_end, tuning.silence_fov + 1.6),
		Vector2(tuning.ring2_end, tuning.silence_fov + 3.2),
		Vector2(tuning.ring3_end, tuning.silence_fov + 4.4),
		Vector2(tuning.suck_end, tuning.hold_fov),
		Vector2(tuning.fov_pull_end, tuning.draw_fov),
		Vector2(tuning.restore_start, tuning.draw_fov),
		Vector2(tuning.restore_end, 0.0),
	]


# --- world / screen --------------------------------------------------------

func _update_world() -> void:
	var t := elapsed
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var anchor_uv := camera.unproject_position(sheath_anchor.global_position) / viewport_size.max(Vector2.ONE)
	anchor_uv.x = clampf(anchor_uv.x, -0.5, 1.5)
	anchor_uv.y = clampf(anchor_uv.y, -0.5, 1.5)
	# THE GLASS CONTINUES THE SPLIT, SO IT READS THE SPLIT FROM HERE.
	#
	# _process stages the panes after this returns, carrying the exact values
	# the frame dict pushes at the world pass. Recomputing the track in the
	# glass layer would be a second clock for a thing that has one.
	last_separation_px = 0.0
	last_split_shear = tuning.split_shear

	# ---- THE COLOUR LEAVES THE WORLD FROM THE KOIGUCHI ---------------------
	#
	# 蓄力的同时让世界的色彩以刀鞘连接处为中心逐渐褪去.
	#
	# Both numbers run over the CHARGE and finish exactly where the stop begins.
	# The charge is the cause of the grey, so the two are not allowed to be on
	# separate schedules — a drain that starts when the charge ends is a filter,
	# and the whole point of the two-second hold is that it is visibly DOING
	# something.
	#
	# `drained`  how far the grey has spread from the koiguchi, 0..1 of frame
	# `focus`    how much colour is gone where the grey has arrived
	var drained := IaidoTuning.ease_in_out(clampf(
		tuning.since(t, tuning.wave_start) / maxf(tuning.grey_end - tuning.wave_start, 0.0001),
		0.0, 1.0))
	var desaturation := _ctrack(t, [
		Vector2(tuning.silence_start, 0.0),
		Vector2(tuning.silence_end, tuning.silence_desaturation),
		Vector2(tuning.wave_start, tuning.silence_desaturation),
		Vector2(tuning.grey_end, tuning.hold_desaturation),
		Vector2(tuning.cut_end, tuning.cut_desaturation),
		Vector2(tuning.restore_start, tuning.cut_desaturation),
		Vector2(tuning.restore_end, 0.0),
	], &"out")
	screen_fx.set_world_drain(desaturation)

	# 蓄力的扭曲空间不要断了. The charge opens three shells, each shorter than the
	# last, then a vacuum that swallows whatever is left — and it is not allowed
	# to stop until the grey has landed, because the two beats are the same
	# beat. The dead spot the user reported was the lull between one shell's ring
	# collapsing into the mouth and the next one opening; the windows now overlap
	# so that at every instant at least one shell, or a shell and the vacuum, is
	# still travelling. `compression_at` holds the arithmetic, and the
	# integration test asserts the overlap directly.
	#
	# 收刀前没有扭曲 was an earlier note, and PASS 4.1 retires the answer to it.
	#
	# The return used to open the SAME three shells a second time, stretched and
	# weaker, while the blade was walked back to the mouth. The user's note on
	# PASS 4.1 is 不要再第二次重力波, and the wave they meant is that one: it
	# made the walk home a second performance instead of the tail of the first.
	# The call is gone, so `waves` is always the charge, and the second half of
	# the ceremony now carries exactly one wave and then the surface's weight.
	#
	# `tuning.return_wave_*` still exists (see the group comment in the tuning
	# resource) — restoring the wave is putting this one call back.
	var waves := tuning.compression_at(t, tuning.wave_start, 1.0, 1.0)
	var wave_a := float(waves["a"])
	var wave_b := float(waves["b"])
	var wave_c := float(waves["c"])
	var wave_suck := float(waves["suck"])
	var wave_strength := float(waves["strength"])

	var void_open := _ctrack(t, [
		Vector2(tuning.cut_start - 0.01, 0.0),
		Vector2(tuning.cut_start + 0.01, 1.0),
		Vector2(tuning.restore_end - 0.10, 1.0),
		Vector2(tuning.restore_end, 0.0),
	], &"linear")
	# ---- THE SPLIT ---------------------------------------------------------
	#
	# THE DISPLACEMENT IS THE EFFECT. THE HOLE IS DERIVED FROM IT.
	#
	# Per half, along the cut normal. The two images misregister by twice this
	# wherever an edge crosses the wound, and that step — not any drawn line, and
	# not the hole — is the whole "the world was cut in two" tell.
	#
	# It ramps over [cut_start, cut_end] and then holds. The hero hold sits at
	# the end of this ramp, with the two halves as far apart as they ever get and
	# nothing else in the ceremony allowed to move.
	var separation_px := _ctrack(t, [
		Vector2(tuning.cut_start, 0.0),
		Vector2(tuning.cut_end, tuning.separation_px),
		Vector2(tuning.restore_start, tuning.separation_px),
		Vector2(tuning.restore_end, 0.0),
	], &"out")
	last_separation_px = separation_px
	# 0..1 over the same window. Drives the differential rotation between the two
	# halves — the term that stops them being provably the same picture.
	var split_amount := _ctrack(t, [
		Vector2(tuning.cut_start, 0.0),
		Vector2(tuning.cut_end, 1.0),
		Vector2(tuning.restore_start, 1.0),
		Vector2(tuning.restore_end, 0.0),
	], &"out")
	# THE OPENING IS NOT AUTHORED. IT IS DERIVED.
	#
	# One knob (`separation_px`), one ratio (`gap_ratio`), so the hole can never
	# invert its relationship with the displacement that reveals it. V1 shipped a
	# 50px lit band over a 12px step: the hole WAS the picture, and no colour of
	# it reads as anything but a beam. Making the hole a function of the
	# separation rather than a second track that has to be kept in step by hand
	# removes the failure rather than guarding against it.
	var gap_px := maxf(separation_px * tuning.gap_ratio, tuning.gap_min_px)
	# The collapse is the one moment the opening is ALLOWED to beat the
	# displacement: reality is letting go, not being cut.
	gap_px = maxf(gap_px, tuning.collapse_gap_px * IaidoTuning.ease_in_out(
		IaidoTuning.span(t, tuning.collapse_start, tuning.collapse_end)))
	# Gravity on the world surface starts the moment the blade turns for home.
	#
	# PASS 4.1: this used to wait for `collapse_start` (the final click), which
	# left the fully-cracked surface held up for 1.1s of walk-home — the
	# 玻璃浮起来 the user reported. `settle_start` is `slow_sheathe_start`, the
	# instant `fracture_at()` declares the surface vitrified, so the front
	# finishing and the surface losing its support are the same beat.
	var slide_px := _ctrack(t, [
		Vector2(tuning.settle_start, 0.0),
		Vector2(tuning.restore_start, tuning.post_break_slide_px),
		Vector2(tuning.restore_end, 0.0),
	], &"in")
	var restore_pull := sin(IaidoTuning.span(t, tuning.restore_start, tuning.restore_end) * PI) * 8.0
	# ---- THE GLASSIFICATION STREAM -----------------------------------------
	#
	# 斩击同步进行流式的玻璃化，顺着斩击方向一步一步碎裂.
	#
	# `stream` is how far the glassification front has travelled ALONG the slash,
	# 0 at the end the blade entered and 1 at the end it left. Everything reads
	# it: the crack network appears where it has passed, the surface turns to
	# glass where it has passed, and the world is consumed where it has passed.
	# ONE front, three readings — which is the only way the three can be
	# guaranteed to agree, and agreement is what makes the pane read as the part
	# of the surface that came away rather than as a pane laid over a picture.
	#
	# It starts at `cut_start` and slows out, so the first panes land almost with
	# the blade and the last ones arrive after it has come to rest. The curve
	# lives in IaidoTuning.stream_at() because the GLASS LAYER needs the same one
	# to decide when each pane lets go — see the note on that function.
	var stream := tuning.stream_at(t)
	# THE FRACTURE STRESS COMES FROM THE ONE PLACE IT IS DEFINED.
	#
	# The world shader, the panes and this all read the same curve, so the two
	# layers of the crack network cannot open at different rates. They used to:
	# the panes ran a fast ease of their own while the world ran this one, so a
	# region could be weak in one layer and strong in the other on the same
	# frame — the same disagreement the shared UE5 bake was adopted to delete,
	# one level up.
	var fracture := tuning.fracture_at(t)
	var shatter := tuning.shatter_at(t)
	var dissolve := IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.restore_start, tuning.restore_end))
	# TEST A. What this removes, exactly: the seam network (`crack`), the
	# per-micro-cell displacement across it (`push`), the chromatic split that
	# rides on that displacement, and the vitrification sheen — because all four
	# are the same `fracture` term read four ways, and pretending otherwise would
	# make the ablation a lie. What is left is WORLD A, WORLD B, the hole, the
	# void's own depth and the broken edge. If that is not legible as a world cut
	# in two, the cracks were carrying the effect and the effect has failed.
	if suppress_crack:
		fracture = 0.0
		shatter = 0.0
	var flash := 0.0
	if t >= tuning.first_click:
		flash = tuning.ivory_flash_strength * (1.0 - IaidoTuning.span(t, tuning.first_click, tuning.first_click + tuning.ivory_flash_duration))
	# THE BLADE'S PASSAGE IS AT THE DRAW, NOT AT THE SPLIT.
	#
	# This used to key off `cut_start`, which was the same instant as the end of
	# the draw. Now that the world's reaction is deliberately late, keying it
	# there would put the one line this shader is allowed to draw a quarter of a
	# second after the blade had already left the scabbard — a flash with nothing
	# to cause it, in the middle of the beat that is supposed to have no cause.
	var blade_flash := 0.0
	if t >= tuning.draw_end:
		blade_flash = 1.0 - IaidoTuning.span(
			t, tuning.draw_end, tuning.draw_end + tuning.blade_flash_duration)

	# ---- TIME STOP ---------------------------------------------------------
	# TWO dead windows, and they are declared in ONE place (IaidoTuning.time_stops)
	# so nothing can disagree about when the ceremony clock is off.
	#
	# The first is the grey: the charge has been paid, the colour has left the
	# world, and everything — including the thing behind reality — stops dead
	# through the seat. The second is the full second after the blade is home,
	# which is the last chance the player gets to not be here for the cut.
	#
	# `stopped_clock` is the ceremony clock with both windows SUBTRACTED, so the
	# void freezes for exactly the length of each pause and then carries on from
	# the value it stopped at. Reading wall time instead kept the void drifting
	# through the pause, and the stop did not land.
	var void_clock := tuning.stopped_clock(t)

	# ---- THE DEVOUR --------------------------------------------------------
	#
	# 收刀后吞噬. It runs AFTER the blade is home, and it finishes the job the
	# stream started: the corners the wedge never reached are eaten, and the
	# emptiness closes over the frame. V5 had this before the sheathe, which put
	# the world's disappearance in the middle of the one beat that is supposed to
	# be about the sword going home.
	# THE ONE DEVOUR CURVE, and it no longer starts at the click — see
	# `devour_ramp_delay`. PASS 4.1: the click reveals what it broke before it
	# takes the picture away.
	var world_drain := tuning.devour_at(t)
	world_drain *= 1.0 - IaidoTuning.ease_in_out(
		IaidoTuning.span(t, tuning.restore_start, tuning.restore_end))

	iaido_fx.present({
		"resolution": viewport_size.max(Vector2.ONE),
		"cut_center": tuning.cut_center,
		"cut_angle": tuning.cut_angle_degrees,
		# The shader has no use for wall time any more — the void reads its own
		# clock and nothing else drifts. Kept bound, and bound to the ceremony
		# clock, so the frame dictionary stays a pure function of `t` and two
		# renders of the same instant are identical.
		"time": t,
		"void_clock": void_clock,
		"stream": stream,
		"world_drain": world_drain,
		"drained_world_color": tuning.drained_world_color,
		"drained_world_deep": tuning.drained_world_deep,
		"drain_crack_fade": tuning.drain_crack_fade,
		"focus": desaturation,
		"grey_spread": drained,
		"void_open": void_open,
		"gap_px": gap_px,
		"separation_px": separation_px,
		"depth_parallax": tuning.depth_parallax,
		# The two halves do not move alike and they do not stay parallel.
		"split_amount": split_amount,
		"split_bias": tuning.split_bias,
		"split_shear": tuning.split_shear,
		"split_rotation_a_deg": tuning.split_rotation_a_deg,
		"split_rotation_b_deg": tuning.split_rotation_b_deg,
		# The band of changed material on the world's side of the hole.
		"edge_band_px": tuning.edge_band_px,
		"edge_refract_px": tuning.edge_refract_px,
		"edge_spec_strength": tuning.edge_spec_strength,
		"edge_spec_low": tuning.edge_spec_low,
		"edge_spec_high": tuning.edge_spec_high,
		"edge_spec_color": tuning.edge_spec_color,
		"restore_pull": restore_pull,
		"slide_px": slide_px,
		"ivory_flash": flash,
		"blade_flash": blade_flash,
		"void_life": tuning.void_life,
		"void_speed": tuning.void_speed,
		"void_back_color": tuning.void_back_color,
		"void_deep_color": tuning.void_deep_color,
		"void_lip_color": tuning.void_lip_color,
		"void_core_color": tuning.void_core_color,
		"void_edge_width_px": tuning.void_edge_width_px,
		"fracture": fracture,
		"shatter": shatter,
		"dissolve": dissolve,
		"refract_px": tuning.refract_px,
		"shatter_px": tuning.shatter_px,
		"wave_strength": wave_strength,
		"wave_a": wave_a,
		"wave_b": wave_b,
		"wave_c": wave_c,
		"wave_suck": wave_suck,
		"sheath_uv": anchor_uv,
	})

	# The weapon stays in the scene: a cold rim while the void is exposed.
	var exposure := _ctrack(t, [
		Vector2(tuning.cut_start, 0.0),
		Vector2(tuning.cut_end, 0.85),
		Vector2(tuning.slow_sheathe_start, 0.85),
		Vector2(tuning.restore_start, 0.45),
		Vector2(tuning.restore_end, 0.0),
	], &"in_out")
	sword.set("void_exposure", exposure)

	# ---- 吞噬可以让手和剑这个图层也消失 ------------------------------------
	#
	# The blade and the hand are the NEAREST things to the void, and the devour
	# is the void closing over the frame. If the world goes and the weapon stays,
	# the weapon stops being inside the shot and becomes a sticker on top of it —
	# the one object in the frame that the emptiness cannot reach, which is
	# exactly backwards for a cut that is supposed to have gone through
	# everything. It is therefore swallowed by the SAME devour, led slightly so
	# the nearest layer goes in first, and it comes back on the restore curve
	# because the restore puts the world back and the weapon is part of it.
	# Led by 100ms of the SAME curve rather than by a 1.3x faster copy of it, so
	# the nearest layer going in first cannot drift into a different shape from
	# the world leaving behind it.
	var swallow := tuning.devour_at(t, 0.10)
	swallow *= 1.0 - IaidoTuning.ease_in_out(
		IaidoTuning.span(t, tuning.restore_start, tuning.restore_end))
	sword.set("swallowed", swallow)

	# The HUD gets out of the way: a signature skill is not read off a bar.
	var hud_dip := (
		IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.silence_start + 0.10, tuning.silence_end + 0.20))
		* (1.0 - IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.restore_start, tuning.restore_end)))
	)
	if hud != null:
		hud.set_iaido_presence(lerpf(1.0, tuning.hud_presence, hud_dip))


# --- the scabbard ----------------------------------------------------------
#
# One parameter describes the whole hip section: how far the blade is home.
#
#   depth 1.0  the tsuba rests on the mouth; the blade is inside the tube
#   depth 0.0  the tip is exactly at the mouth, the blade fully outside it
#
# Everything between the two is a pure translation ALONG THE BORE, which is the
# only motion that can be called "the blade entering the scabbard". The exposed
# length of blade is `(1 - depth) * blade_reach` at every instant, so the slow
# final centimetres are authored directly as a depth curve.

func _bore_pose(depth: float) -> Dictionary:
	var d := clampf(depth, 0.0, 1.0)
	var id := _weapon_id()
	var back := SwordClasses.guard_setback(id) \
		+ (1.0 - d) * SwordClasses.blade_reach(id)
	return {
		"position": seat_origin - seat_basis.y * back,
		"rotation": seat_euler,
	}


# WHERE THE BLADE IS ON ITS ONE WALK HOME.
#
# Parameterised by ARC LENGTH, not by time spent in each leg. The path is two
# straight legs — from wherever the sword is resting to the mouth, then down
# the bore to fully seated — and `u` is the fraction of the TOTAL length walked
# so far. That is what makes the tip travel at one constant speed for the whole
# two and a half seconds: no acceleration off the rest pose, no deceleration
# into the mouth, no pause at the mouth. 线性, and visibly so.
#
# Splitting `u` evenly between the two legs would look linear on paper and
# wrong on screen: the alignment leg is most of a metre and the bore leg is
# `blade_reach`, so equal time per leg means the last third of the travel —
# the part inside the scabbard, the part that should be the slowest — happens
# at three times the speed of the part in open air.
func _sheath_at(u: float) -> Dictionary:
	var mouth := _bore_pose(0.0)
	var leg_align := maxf(initial_sword_position.distance_to(mouth["position"]), 0.0001)
	var leg_bore := maxf(absf(tuning.sheath_depth) * SwordClasses.blade_reach(_weapon_id()), 0.0001)
	var walked := clampf(u, 0.0, 1.0) * (leg_align + leg_bore)
	if walked <= leg_align:
		var w := walked / leg_align
		return {
			"position": initial_sword_position.lerp(mouth["position"], w),
			"rotation": _slerp_euler(initial_sword_rotation, mouth["rotation"], w),
		}
	return _bore_pose((walked - leg_align) / leg_bore * tuning.sheath_depth)


## What fraction of the walk home is spent travelling TO the mouth rather than
## down the bore.
##
## Exposed because a linearity assertion has to compare like with like: the
## straight line between two poses that straddle the mouth is SHORTER than the
## distance the tip actually walked to get from one to the other, so comparing
## the two halves of the walk directly reports a correct constant speed as an
## ease — it did, 1.202m against 0.793m, for two halves that are equal by
## construction.
func sheath_leg_split() -> float:
	var mouth := _bore_pose(0.0)
	var leg_align := maxf(initial_sword_position.distance_to(mouth["position"]), 0.0001)
	var leg_bore := maxf(absf(tuning.sheath_depth) * SwordClasses.blade_reach(_weapon_id()), 0.0001)
	return leg_align / (leg_align + leg_bore)


# WHICH SWORD THIS CEREMONY IS SEATING.
#
# The seating geometry -- how far up its own origin the tsuba sits, and how far
# the tip is from the tsuba face -- is a property of the ASSET, not of the
# ceremony, and `SwordClasses` already measures it per weapon class. The
# ceremony used to carry its own copy in `IaidoTuning` (`blade_reach 0.95`,
# `guard_setback 0.045`) and the copy was for a different sword: 41 mm of
# guard set-back that this asset does not have, and a 950 mm blade against this
# one's 765. The visible result was the habaki and the first 41 mm of blade
# root standing outside the mouth at the moment the ceremony clicked "home".
#
# Read off the rig that owns the weapon rather than a constant, so a second
# weapon class is seated correctly by existing rather than by being remembered.
func _weapon_id() -> StringName:
	if combat != null and combat.saya_rig != null:
		return combat.saya_rig.weapon_id
	return SwordBasic.WEAPON_ID


# Insertion depth at time t through phase L. Four segments, each physically
# slower than the last: the last ~7cm take a quarter of the phase and are the
# slowest thing in the entire performance, which is what makes the final click
# land instead of just happening.
func _insertion_at(t: float) -> float:
	var w := IaidoTuning.span(t, tuning.final_insert_start, tuning.slow_sheathe_end)
	if w < 0.24:
		return IaidoTuning.smooth(w / 0.24) * 0.72
	if w < 0.48:
		return 0.72 + IaidoTuning.smooth((w - 0.24) / 0.24) * 0.18
	if w < 0.74:
		return 0.90 + IaidoTuning.smooth((w - 0.48) / 0.26) * 0.06
	return 0.96 + IaidoTuning.smooth((w - 0.74) / 0.26) * 0.04


func _sheathed_hip_pose(depth: float) -> Dictionary:
	return _bore_pose(depth)


# --- sword -----------------------------------------------------------------

func _apply_weapon_pose(t: float) -> void:
	var p := initial_sword_position
	var r := initial_sword_rotation
	var drawn := tuning.drawn_position
	var drawn_rot := tuning.drawn_rotation

	if t < tuning.sheath_start:
		# PHASE A: the arm does not move. Only the world changes.
		pass
	elif t < tuning.seat_start:
		# PHASE B/C/D: ONE LINEAR SHEATH, COVERING THE WHOLE CHARGE.
		#
		# 不要单独出现收刀了，蓄力过程中慢慢收刀，蓄力完成之后就收完全，线性.
		#
		# `sheath_start -> sheath_end` is a raw linear span (not an ease), and
		# `sheath_end` is `time_stop_start`, so the blade is still walking home
		# for the entire two seconds the world is being pulled in and arrives
		# exactly as everything stops. After that the span is 1.0 and the sword
		# is simply home — there is no parked pose and no separate seat, which
		# is what "不要单独出现收刀" asks for: the sheathe is no longer a beat in
		# front of the charge, it IS the charge.
		var walked := clampf(IaidoTuning.span(t, tuning.sheath_start, tuning.sheath_end), 0.0, 1.0)
		var pose := _sheath_at(walked)
		p = pose["position"]
		r = pose["rotation"]
	elif t < tuning.first_click:
		# PHASE E: the blade has been home for a third of a second. Nothing
		# moves here any more — the seat used to be where the last 5cm went in,
		# and the only thing the phase has left to do now is the click.
		var target := _bore_pose(tuning.sheath_depth)
		p = target["position"]
		r = target["rotation"]
	elif t < tuning.draw_start:
		var target := _bore_pose(1.0)
		p = target["position"]
		r = target["rotation"]
	elif t < tuning.draw_end:
		# PHASE F: three seconds of restraint released in 100ms. The first part
		# is pure extraction along the bore — the blade has to leave the mouth
		# before it can go anywhere. Only then does it leave the axis and arc
		# away. A straight lerp between the seated and drawn poses skips the
		# extraction, and the extraction is the part that reads as a draw.
		var raw := IaidoTuning.span(t, tuning.draw_start, tuning.draw_end)
		if raw < tuning.draw_axial_share:
			var u := raw / maxf(tuning.draw_axial_share, 0.001)
			var target := _bore_pose(1.0 - IaidoTuning.ease_in_accel(u))
			p = target["position"]
			r = target["rotation"]
		else:
			var u := IaidoTuning.ease_out_cubic((raw - tuning.draw_axial_share) / (1.0 - tuning.draw_axial_share))
			var from := _bore_pose(0.0)
			p = from["position"].lerp(drawn, u)
			r = _slerp_euler(from["rotation"], drawn_rot, u)
	elif t < tuning.spin_start:
		p = drawn
		r = drawn_rot
	elif t < tuning.spin_end:
		# PHASE K: ONE controlled rotation, and it has a JOB.
		#
		# =====================================================================
		# §21-§22 · THE TWO SPINS ARE RETIRED
		# =====================================================================
		# This used to be `TAU * (first + second)`: two full revolutions, the
		# first wide and quick, the second tighter and slower, written to read as
		# a controlled wrist rather than a weapon-inspect animation. It read as
		# neither. Two revolutions is 720 degrees of a sword with no weight in
		# it, and the beat the player is being shown is 收刀 -- a hand putting a
		# blade away.
		#
		# A hand doing this turns the blade for ONE reason, and §22 names it: the
		# edge comes out of the last cut facing wherever the cut left it, and the
		# koiguchi is a slot. So the wrist turns once, by the number of degrees
		# that takes, and stops. `spin_turns` is that number -- 0.85 of a turn,
		# 306 degrees, inside §22's 270-360 band.
		#
		# =====================================================================
		# ...AND IT IS ABOUT THE BLADE'S OWN AXIS, WHICH IS THE WHOLE POINT
		# =====================================================================
		# §22 does not say "swing the sword around", it says RESET THE EDGE
		# ORIENTATION. Those are different rotations and only one of them is a
		# hand putting a blade into a slot. The authored sweep was `Rz` inside
		# the euler, and `+Y` is the tip -- so the euler's Z is TRANSVERSE to the
		# blade, and the sweep was a wide cone: the tip walked 376 degrees of
		# path to cover a 306 degree turn, and it finished 54 degrees away from
		# where it started. Measured by `tools/probe_iaido_recovery.gd`:
		#
		#     Rz transverse (authored)        leaves 168.0 deg = 149.6 repoint + 133.0 roll
		#     roll about the blade's own axis leaves 132.1 deg = 130.3 repoint +  29.9 roll
		#     the tip ends 0.0000 deg from where it started under the roll,
		#                            54.0 deg under the authored sweep
		#
		# So the turn that "resets the edge" moves the tip NOT AT ALL, and the
		# same 306 degrees of wrist does four times as much of §23's alignment as
		# a cone does. The cone was never doing the job; it was decoration on top
		# of the job, and the job was being done afterwards by a 149-degree
		# blend. This is the same finding as the probe's `argmin` -- "no count of
		# THIS rotation finishes the alignment" -- arriving from the other side.
		#
		# The 130.3 degrees that REMAIN is the drawn pose's own pointing error
		# (the blade leaves the draw 130 degrees off the bore, which is where a
		# drawn sword is), and it is §23's Mouth Catch that is supposed to take
		# it: the blade comes onto the bore, THEN the edge goes to the slot. Both
		# of those are now short, and neither is near the 180 that `slerp` cannot
		# do -- which is what the split was for.
		#
		# =====================================================================
		# AND ONE CLOCK INSTEAD OF THREE
		# =====================================================================
		# The old shape was not two spins, it was two spins AND an arc radius AND
		# an aim blend, all keyed on `first`/`second`, so the second revolution
		# could not be deleted without deleting the radius shrink and the slerp
		# with it. They are all one `u` now, which is also the part that makes it
		# read as one movement: the arc tightens as the wrist closes, and the
		# last third slerps the blade onto the bore's own axis so phase L is a
		# translation rather than a second guess at the rotation (§23's Mouth
		# Catch, kept because it was the good half).
		#
		# =====================================================================
		# AND IT IS CONTINUOUS AT BOTH ENDS (§18, no orientation pop)
		# =====================================================================
		# The wrist's own tilt used to be unconditional, so at `spin_start` the
		# phase opened on `drawn_rot + (0, 0.11, 0)` while the phase before it
		# ended on `drawn_rot` -- a 6.3 degree step at a boundary, which is
		# exactly the "cut a Transform" the brief is about. A per-revolution
		# wobble is a cycle, so it takes a window that is zero at both ends:
		# `sin(PI * u)`. The end is already handled by the aim blend (at u = 1
		# the blend is 1 and the result IS `seat_basis`), but a term that is
		# only correct because something else overwrites it is a term waiting to
		# be wrong.
		#
		# ...AND IT IS SMALL NOW, BECAUSE IT IS BEING COUNTED. `sin(PI * u)`
		# fixes the ends; it does not fix the middle, and in the middle a lean
		# of a fifth of a radian is eleven degrees of tip swing four times a
		# second. `tools/probe_iaido_recovery.gd` books that as rotation, and it
		# should: an eleven-degree swing IS eleven degrees of movement, and §22
		# puts a ceiling on how much movement this phase contains. Measured with
		# the old amplitudes the phase spent 381 degrees of rotation to deliver
		# a 306 degree turn -- twenty per cent flourish on a beat the brief
		# describes as a hand putting a blade away. 0.06 and 0.04 are a settle
		# the wrist would actually have: three degrees and two, not a twirl.
		var u := IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.spin_start, tuning.spin_end))
		# =====================================================================
		# ONE TURN, AND THEN A CATCH
		# =====================================================================
		# §22's rotation finishes at `spin_turn_share`; what is left of the phase
		# is §23's catch, which is a different movement about different axes.
		# Running the two off one clock (which is what this phase did) is wrong
		# twice over. It reads as one undifferentiated smear rather than as "she
		# turns the blade, then she brings it to the mouth" -- and it makes the
		# phase un-measurable, because the catch's 130 degrees of pointing get
		# counted against the turn's 270-360 budget. A gate that cannot tell the
		# two apart will happily pass two spins that hide behind a catch.
		var turn_u := minf(u / maxf(tuning.spin_turn_share, 0.0001), 1.0)
		var turns := TAU * tuning.spin_turns * IaidoTuning.ease_in_out(turn_u)
		# =====================================================================
		# A WINDOW ON THE TRAVEL, NOT ONLY ON THE ANGLE (§18 in translation)
		# =====================================================================
		# The brief's complaint is about orientation being cut rather than
		# travelled, and every test in this file measures orientation -- so the
		# two TRANSLATIONAL pops at this phase's edges went unnoticed:
		#
		#   at `spin_start` the phase opened on `drawn + (0.038, 0.004, 0)` while
		#   the draw had left the sword at exactly `drawn` -- 38 mm, in one frame;
		#   at `spin_end` it closed 10 mm off `drawn`, which is where phase L
		#   starts its walk to the mouth from.
		#
		# Both are the same fault as a cut rotation and both are fixed the same
		# way: the flourish is a cycle, so it gets a window that is zero at both
		# ends. `sway` is that window, and it multiplies the RADIUS and the lift
		# as well as the lean -- a lift that starts at 4 mm and ends at 4 mm is a
		# step, not a lift.
		var sway := sin(PI * turn_u)
		var arc := lerpf(tuning.spin_radius_first, tuning.spin_radius_second, turn_u) * sway
		p = drawn + Vector3(cos(turns) * arc,
			sin(turns) * arc * 0.76 + tuning.spin_lift * sway, 0.0)
		# The blade's own axis, in the frame the rotation is written in: it is
		# the DRAWN pose's `+Y`, so it is a constant of the tuning and not a
		# function of `t`. A roll about it is a WORLD-space rotation composed on
		# the left -- `Basis(axis, a) * pose`. Composing on the right would turn
		# the pose's own local frame instead, which is a different rotation
		# unless the axis happens to be an eigenvector; both agree at zero, so
		# the mistake is invisible at `spin_start` and grows to 54 degrees of
		# misplaced tip by `spin_end`.
		var drawn_basis := Basis.from_euler(drawn_rot)
		var own_axis := (drawn_basis * Vector3.UP).normalized()
		var spin := Basis(own_axis, -turns) * Basis.from_euler(drawn_rot + Vector3(
			sin(turns) * 0.06 * sway, cos(turns) * 0.04 * sway, 0.0
		))
		var aim := IaidoTuning.smooth(IaidoTuning.span(u, tuning.spin_turn_share, 1.0))
		# =====================================================================
		# THE RESIDUAL, NOT A SECOND REORIENTATION (§18's "real arc")
		# =====================================================================
		# This was `spin.slerp(seat_basis, aim)`, and that is a slerp between two
		# poses that pass within a hair of 180 degrees of each other as the turn
		# sweeps past the halfway point. Godot's `Quaternion::slerp` divides by
		# `sin(omega)`, which goes to ZERO there, so the pair is ill-conditioned
		# exactly when the blade is upside down -- and the result was a genuine
		# discontinuity, not a small one.
		#
		# Measured by `tools/probe_iaido_recovery.gd`: **16.2 degrees in under a
		# millisecond at t = 7.166 s**, reported as 13.4x its own neighbourhood on
		# a 4.2 ms grid, 32.8x on a 2 ms grid and 71.8x on a 1 ms grid. The step's
		# SIZE does not move with the grid, which is the signature of a real
		# break; a sampling artefact shrinks as the grid refines.
		#
		# The cure is not a smaller step, it is a different pair. What the hand
		# has left to do after a full turn is ALIGN A RESIDUAL: the difference
		# between where one turn leaves the blade and where the bore points. That
		# difference is a FIXED rotation -- `landed` is a constant of the tuning
		# -- so the blend can run from the identity to it instead of from the
		# spinning blade to the bore. Identity-to-small never approaches the
		# singularity, and both ends stay exact: at `aim = 0` the result is `spin`
		# unchanged, and at `aim = 1` it is `landed * landed⁻¹ * seat_basis`, which
		# is `seat_basis` by construction rather than by arithmetic luck.
		#
		# It also makes `spin_turns` ACCOUNTABLE. The residual is what one turn
		# failed to line up, so a turn count that is wrong shows up here as a big
		# number instead of being silently absorbed by a 180-degree blend.
		#
		# `landed` is `spin` at `u = 1` -- the wobble is zero there and the roll
		# has run its whole author'd angle -- and it has to be written the same
		# way `spin` is, or the residual is measured against a pose the ceremony
		# never passes through.
		var landed := Basis(own_axis, -TAU * tuning.spin_turns) * drawn_basis
		# ...AND IT IS TWO SHORT ROTATIONS, NOT ONE LONG ONE.
		#
		# `landed⁻¹ * seat_basis` is the whole residual and it is 168 degrees of
		# this tuning -- two thirds of the way to the 180 that `Quaternion::slerp`
		# cannot do. Blending that as one pair works today and is one authored
		# number away from not working, which is how the fault above got in.
		#
		# §23 already says what the catch IS, in order: the blade is brought onto
		# the bore, and THEN the edge is brought to the slot. Those are two
		# rotations about two different axes, and writing them as two keeps each
		# one short: the first is the shortest arc between two DIRECTIONS (short
		# unless the blade is pointing exactly backwards), the second is a ROLL
		# about the bore (short unless the edge is exactly opposite the slot).
		# Neither can approach 180 for any reason the ceremony would want.
		#
		# At `aim = 1` the product is `landed⁻¹ * seat_basis` exactly, so the
		# arrival is still `seat_basis` by construction; at `aim = 0` both factors
		# are the identity, so the sweep is untouched until the catch begins.
		#
		# ...AND BOTH FACTORS GO ON THE LEFT. This is the part that is easy to
		# write backwards, and writing it backwards costs the continuity at BOTH
		# ends of the phase. `spin` carries the blade to `blade_dir`; the
		# correction that takes `blade_dir` onto `bore_dir` is a rotation of the
		# FRAME THE BLADE SITS IN, so it has to be applied to `spin` rather than
		# hung off it: `repoint * spin`, not `spin * repoint`. The two agree only
		# where they are both the identity. Measured: right-multiplied, the end
		# of phase K landed somewhere other than `seat_basis`, and phase L's
		# first frame (`_bore_pose`, which IS `seat_euler`) snapped to it --
		# 897x its neighbourhood at t = 7.300 s. The neighbourhood is tiny there
		# because both the turn and the wobble have flattened out, so the
		# signature of the fault is a large multiple of a very small number.
		var bore_dir := seat_basis * Vector3.UP
		var blade_dir := landed * Vector3.UP
		var repoint := Basis.IDENTITY
		var cross := blade_dir.cross(bore_dir)
		if cross.length() > 0.0001:
			repoint = Basis(cross.normalized(), blade_dir.angle_to(bore_dir))
		# The spine is the basis's own X -- the convention `aim_euler` builds --
		# so the roll is the signed angle that takes one spine onto the other
		# about the bore, and it is a pure roll by construction.
		var aimed := repoint * landed
		var from_spine := aimed * Vector3.RIGHT
		var to_spine := seat_basis * Vector3.RIGHT
		var plane_from := (from_spine - bore_dir * from_spine.dot(bore_dir)).normalized()
		var plane_to := (to_spine - bore_dir * to_spine.dot(bore_dir)).normalized()
		var roll := Basis(bore_dir, atan2(
			bore_dir.dot(plane_from.cross(plane_to)), plane_from.dot(plane_to)))
		dbg_recovery_repoint_deg = rad_to_deg(blade_dir.angle_to(bore_dir))
		dbg_recovery_roll_deg = rad_to_deg(plane_from.angle_to(plane_to))
		r = (Basis.IDENTITY.slerp(roll, aim)
			* Basis.IDENTITY.slerp(repoint, aim)
			* spin).get_euler()
	elif t < tuning.slow_sheathe_end:
		# PHASE L: the return. Bring the tip to the mouth, then slide home.
		var approach_end := tuning.final_insert_start
		if t < approach_end:
			var u := IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.slow_sheathe_start, approach_end))
			var target := _bore_pose(0.0)
			# The spin left the blade pointing down the bore already, so this
			# is a translation: the tip leads the hand into the mouth.
			var start_pos := drawn
			p = start_pos.lerp(target["position"], u)
			r = target["rotation"]
		else:
			var target := _bore_pose(_insertion_at(t))
			p = target["position"]
			r = target["rotation"]
	else:
		var settle := IaidoTuning.ease_in_out(IaidoTuning.span(t, tuning.restore_start, tuning.restore_end))
		var seated := _bore_pose(1.0)
		p = seated["position"].lerp(sword.IDLE_POSITION, settle)
		r = _slerp_euler(seated["rotation"], sword.IDLE_ROTATION, settle)

	sword.position = p
	sword.rotation = r
	# NOTE: the blade is never hidden. It goes inside a real scabbard and the
	# scabbard's own walls occlude it, which is the difference between a sheathe
	# and a `visible = false`.
	sword.click_flash.visible = (
		(t >= tuning.first_click and t < tuning.first_click + 0.035)
		or (t >= tuning.final_click and t < tuning.final_click + 0.04)
	)


# Euler angles cannot be lerped safely across a large rotation — the two arcs
# and the hip alignment routinely span more than half a turn. Everything that
# turns the blade goes through a quaternion.
func _slerp_euler(from: Vector3, to: Vector3, weight: float) -> Vector3:
	return Basis.from_euler(from).slerp(Basis.from_euler(to), weight).get_euler()


## Opens and closes the ceremony's scabbard. The ONE place that decision is
## made: `_ready` starts it closed, `start_iaido` opens it, and every exit —
## normal end, death, abort, teardown — comes through `_hard_reset`, which closes
## it. Nothing else in the project writes `ceremony_scabbard.visible`.
##
## ===========================================================================
## AND IT IS ALSO THE ONE PLACE THAT CAN STAND THE OTHER SAYA DOWN
## ===========================================================================
## The basic-attack language wears a saya of its own (`SwordSayaRig`), sized and
## seated from the sword's own pose. Both are real, and a probe over a live
## session found BOTH on screen for the whole ceremony: two mouths, one blade.
##
## The hand-off cannot live in `CombatController._drive_saya` — the per-frame
## judge for that rig — because `start_iaido` pauses the tree and the controller
## is PAUSABLE, so its `_process` does not run again until the blade is already
## home. A rule evaluated per frame would be evaluated one frame too late, and
## the artifact would be on screen for eight seconds. So the stand-down happens
## here, on the frame the ceremony takes the sash.
##
## ONLY THE STAND-DOWN. Coming back is not this function's call: the sword
## language's own rule re-evaluates on the first unpaused frame, and it knows two
## things this director does not — whether the chain is in hand, and whether the
## style wants a scabbard of its own (藏锋 does). Restoring from here would have
## to guess both, and would be wrong about the style for a frame.
func _set_scabbard(shown: bool) -> void:
	if ceremony_scabbard != null:
		ceremony_scabbard.visible = shown
	if not shown:
		return
	var understudy := _sword_language_saya()
	if understudy != null:
		understudy.visible = false


## Resolved by path and lazily, because this director also runs in stages that
## never build a `CombatController` — there, the node is simply not there and
## the ceremony plays exactly as it did before.
func _sword_language_saya() -> Node3D:
	if _understudy_saya == null or not is_instance_valid(_understudy_saya):
		var root := sheath_anchor.get_parent()
		if root != null:
			_understudy_saya = root.get_node_or_null("SwordSayaRig") as Node3D
	return _understudy_saya


# --- events ----------------------------------------------------------------

func _fire_events() -> void:
	var t := elapsed
	if t >= tuning.damage_time and not events.has("impact"):
		events["impact"] = true
		_apply_impact()
	if t >= tuning.damage_time + 0.11:
		_clear_target_marks()
	# Freeze the world surface once, at the INSTANT OF THE CUT and before the
	# stream has eaten any of it. The glass samples this capture, so every pane
	# carries the piece of building / ground / sky it was cut out of instead of a
	# grey tint — and instead of a picture of the void, which is what a capture
	# taken at the hero frame would now give, since the drain is well under way
	# by then.
	#
	# ARM, THEN TAKE. The capture no longer reads the root viewport — that is the
	# finished composite, foreground weapon layer included, and welding the
	# player's own sword into the panes is what put 两层刀 on screen. It reads a
	# rig of its own now (see `IaidoGlassLayer.capture_viewport`), and a rig has
	# to be given a frame to draw before its picture can be taken.
	#
	# The lead is free: `capture_time` sits inside the hero hold, which is a dead
	# window, so the frame the rig draws while arming is the same frame it is
	# asked for.
	if t >= tuning.capture_time - tuning.capture_arm_lead and not events.has("capture_arm"):
		events["capture_arm"] = true
		glass_layer.begin_capture(iaido_fx.focus_material)
	if t >= tuning.capture_time and not events.has("capture"):
		events["capture"] = true
		glass_layer.capture_world()
	# NOTE: the three camera impulses are no longer fired from here. They are
	# evaluated from the timeline in _update_camera(), which is what makes them
	# freeze with everything else instead of settling on wall time.


func _apply_impact() -> void:
	# ONE PLANE FOR EVERYTHING THE BLADE TOUCHED. Taken at the instant of the cut
	# and then frozen: the camera takes three small impulses across the ceremony
	# and a plane recomputed later would describe a different slash from the one
	# on screen. See `IaidoCutPlane`.
	cut_plane = IaidoCutPlane.from_camera(camera, tuning.cut_center, tuning.cut_angle_degrees)
	var line := cut_plane.line_direction(camera)
	var primary := tuning.execution_damage
	var splash := tuning.execution_damage_splash
	match debug_lethality:
		1:
			primary = tuning.execution_damage * 10.0
			splash = tuning.execution_damage * 10.0
		2:
			primary = 1.0
			splash = 1.0
	# Pass one: the blow lands on everything. THE DAMAGE IS SETTLED HERE, at the
	# cut — which is what lets the enemy be logically dead three and a half
	# seconds before it is visually dead (§O).
	for i in targets.size():
		var actor := targets[i]
		if not is_instance_valid(actor) or not actor.visible:
			continue
		var hurtbox := actor.get_node_or_null("Hurtbox") as CombatHurtbox
		if hurtbox == null:
			continue
		hurtbox.receive_hit({
			"damage": primary if i == 0 else splash,
			"poise_damage": 70.0 if i == 0 else 42.0,
			"element": &"physical",
			"impulse": 0.0,
			"source": player,
			"iaido": true,
			# Everything downstream of the cut — the cross-section, the deep-slash
			# mark, and the VFX — gets the same two vectors, so a single fact can
			# be drawn on the world and on a body without either re-deriving it.
			"cut_normal": cut_plane.normal,
			"cut_line": line,
		})
		_add_target_mark(actor)
	# Pass two: whichever bodies answered "yes, and it killed me" are taken over.
	# Deliberately a second pass — `IaidoExecution.begin()` hides the body, and a
	# single pass would therefore hide a later target from the loop above.
	for i in targets.size():
		var actor := targets[i]
		if not is_instance_valid(actor):
			continue
		if actor.has_method("expects_iaido_execution") and bool(actor.call("expects_iaido_execution")):
			_spawn_execution(actor, i)


## Hand a body to an `IaidoExecution`. The enemy decided lethality and support;
## the plane came from the world; the clock stays here.
func _spawn_execution(actor: Node3D, ordinal: int) -> void:
	var profile: IaidoExecutionProfile = null
	if actor.has_method("iaido_execution_profile"):
		profile = actor.call("iaido_execution_profile") as IaidoExecutionProfile
	var node := IaidoExecution.new()
	node.name = "IaidoExecution%d" % ordinal
	get_parent().add_child(node)
	var accepted := node.begin(
		actor, camera, cut_plane, profile,
		tuning.damage_time, tuning.final_click, ordinal)
	if accepted:
		executions.append(node)
	else:
		if node.has_method("force_resolve"):
			node.call("force_resolve")
		node.queue_free()


# THE EXECUTION'S OWN CLOCK IS THIS ONE. The runtime is a pure function of the
# ceremony time, so the held body, the creep and the fall are all evaluated at
# whatever instant the ceremony is at — including an instant the reviewer's scrub
# jumped to. See the header of `iaido_execution.gd`.
func _stage_executions() -> void:
	if executions.is_empty():
		return
	var index := executions.size() - 1
	while index >= 0:
		var execution: IaidoExecution = executions[index]
		if execution == null or not is_instance_valid(execution):
			executions.remove_at(index)
			index -= 1
			continue
		execution.stage(elapsed)
		for name in execution.take_events():
			execution_events.append(name)
		if execution.is_finished(elapsed):
			execution.force_resolve()
			execution.queue_free()
			executions.remove_at(index)
		index -= 1


## §N · read-and-clear. AUDIO subscribes to three events rather than to one
## "enemy died" so that the cut mark, the release and the falling material can be
## different sounds — and so none of them is a generic anime slash.
func take_execution_events() -> Array[StringName]:
	var out := execution_events.duplicate()
	execution_events.clear()
	return out


## DEBUG ONLY — see `debug_lethality`. 0 auto, 1 force lethal, 2 force non-lethal.
func set_debug_lethality(mode: int) -> void:
	debug_lethality = clampi(mode, 0, 2)


func _add_target_mark(actor: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.4, 0.018, 0.014)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(1.0, 0.96, 0.82)
	mesh.material = material
	var mark := MeshInstance3D.new()
	mark.mesh = mesh
	get_parent().add_child(mark)
	# LAID ON THE PLANE, NOT ON THE SCREEN. The strip's long axis is the wound's
	# own direction and its face is the wound's normal, so the mark a body wears
	# and the line across the world are the same slash at two scales.
	var along := cut_plane.line_direction(camera)
	var normal := cut_plane.normal
	var centre := actor.global_position + Vector3.UP * 1.05
	mark.global_transform = Transform3D(Basis(along, normal.cross(along), normal), centre)
	target_marks.append(mark)


func _clear_target_marks() -> void:
	for mark in target_marks:
		if is_instance_valid(mark):
			mark.queue_free()
	target_marks.clear()


## Let every held body go. Called from `_hard_reset` and from `_exit_tree`, and it
## is idempotent on purpose: it runs on the happy path and on every failure path,
## and a failure path that had to know whether the happy path had already run is
## the kind of coupling this whole ceremony is written to avoid.
func _release_executions() -> void:
	for execution in executions:
		if is_instance_valid(execution):
			execution.force_resolve()
			execution.queue_free()
	executions.clear()
	execution_events.clear()


# --- debug -----------------------------------------------------------------

func set_debug_hold(time: float) -> void:
	hold_time = time
	if not active:
		combat.iaido_ready_at = 0.0
		combat.request(&"iaido")
	if active:
		elapsed = time
		audio_timeline.seek(time)
		_process(0.0)


func release_debug_hold() -> void:
	hold_time = -1.0


func set_debug_speed(speed: float) -> void:
	playback_speed = clampf(speed, 0.25, 2.0)


# --- lifecycle / fail-safe --------------------------------------------------

func finish_iaido() -> void:
	if not active:
		_hard_reset()
		return
	active = false
	hold_time = -1.0
	_hard_reset()
	combat.finish_action()
	# Reality reconnect pulse: tiny, never a shake.
	camera_feedback.add_impulse(Vector2(0.0, 0.012))


func _hard_reset() -> void:
	tear.visible = false
	# §12 · THE FORCE-RESOLVE. Every exit from the ceremony passes through here —
	# a normal end, a player death, an abort, a scene being torn down — and a body
	# being held by an execution has to be let go on ALL of them. Leaving it held
	# would put a corpse in the world that is logically dead, cannot be hit, and
	# is standing up forever: the single worst failure this system can have.
	_release_executions()
	_clear_target_marks()
	iaido_fx.reset_iaido_fx()
	glass_layer.reset()
	audio_timeline.stop_all()
	audio_timeline.reset()
	screen_fx.reset()
	camera_feedback.fov_hold = 0.0
	camera_feedback.iaido_pitch = 0.0
	camera_feedback.iaido_frame = Vector2.ZERO
	camera_feedback.iaido_still = 0.0
	camera_feedback.iaido_frozen = false
	sword.set("void_exposure", 0.0)
	# The weapon layer has to be put back by hand: if the ceremony is cut off
	# mid-devour the script stops running, and whatever it swallowed last stays
	# swallowed into the next fight.
	sword.set("swallowed", 0.0)
	sword.click_flash.visible = false
	_set_scabbard(false)
	if sword.has_method("set_ceremony_mode"):
		sword.call("set_ceremony_mode", false)
	if hud != null:
		hud.set_iaido_presence(1.0)
	player.global_position = start_position
	player.velocity = Vector3.ZERO
	for node in previous_modes:
		if is_instance_valid(node):
			node.process_mode = previous_modes[node]
	previous_modes.clear()
	time_effects.reset()
	audio_state.restore_world_audio()
	audio_state.resume_music()
	pause_manager.release()
	if combat_phase != &"Iaido_End":
		combat_phase = &"Iaido_End"
		phase_changed.emit(combat_phase)
	if _demo_tuning != null:
		tuning = _demo_tuning
		_demo_tuning = null
		audio_timeline.configure(tuning, false)
	combat_cast = false


func _exit_tree() -> void:
	_clear_target_marks()
	_release_executions()
	if active:
		active = false
		_hard_reset()
		audio_state.resume_music()
		# §12 · AND THE CONTROLLER HAS TO BE RELEASED WITH IT.
		#
		# `CombatController.State.IAIDO` is entered when the ceremony starts and
		# is cleared in exactly one place: `finish_iaido()`. A director taken out
		# of the tree while it was running — a scene change, a debug removal, an
		# abort that destroys it — therefore used to leave that state set, and
		# that does not read as "the ceremony is still going". It reads as a
		# player who can never attack again, because `request()` refuses every
		# action while the state is not IDLE.
		#
		# Guarded, because during a full scene teardown the player may already be
		# gone — and this runs inside `free()`, where touching a freed sibling is
		# a crash rather than an error message.
		if is_instance_valid(combat):
			combat.finish_action()


# --- helpers ----------------------------------------------------------------

func _track(t: float, keys: Array[Vector2], ease: StringName = &"in_out") -> float:
	if keys.is_empty():
		return 0.0
	if t <= keys[0].x:
		return keys[0].y
	for i in range(1, keys.size()):
		if t <= keys[i].x:
			var a := keys[i - 1]
			var b := keys[i]
			var u := _eased(clampf((t - a.x) / maxf(b.x - a.x, 0.0001), 0.0, 1.0), ease)
			return lerpf(a.y, b.y, u)
	return keys[keys.size() - 1].y


# --- NOTHING INTERPOLATES ACROSS A TIME STOP --------------------------------
#
# A track whose keys straddle a dead window keeps interpolating on WALL TIME
# unless it is stopped, and three of them did: the FOV push, the desaturation
# and the half-degree camera breath all ran straight through the first stop. A
# render diff of the window then reported a 10% change — the same as a window
# where things are supposed to move. The stop was declared and not implemented.
#
# This inserts a FLAT PLATEAU at the value the track already had when the window
# opened. A plateau is the only shape that is both genuinely frozen inside the
# window AND continuous at both ends: snapping the clock instead would make the
# value jump the instant the stop released, which is a pop, and a pop is worse
# than a drift because the eye catches it immediately.
#
# The cost is that whatever was going to happen during the window happens
# faster afterwards. That is correct: the ceremony does not get extra time back.
func _hold_across_stops(keys: Array[Vector2], ease: StringName = &"in_out") -> Array[Vector2]:
	if keys.is_empty():
		return keys
	var out: Array[Vector2] = []
	for key in keys:
		out.append(key)
	for window in tuning.time_stops():
		var w0 := float(window[0])
		var w1 := float(window[1])
		var v0 := _track_on(out, w0, ease)
		var v1 := _track_on(out, w1, ease)
		# Already flat across the window: nothing to insert, and the key lists
		# stay readable.
		if absf(v0 - v1) < 0.000001:
			continue
		out.append(Vector2(w0, v0))
		out.append(Vector2(w1, v0))
		out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return out


# `_track` without the stop handling, so the plateau is measured on the ORIGINAL
# curve — with the SAME easing the track will be read with, or the plateau value
# would land a hair off what the curve actually had at the window and the stop
# would open with a small step.
func _track_on(keys: Array[Vector2], t: float, ease: StringName = &"in_out") -> float:
	if keys.is_empty():
		return 0.0
	if t <= keys[0].x:
		return keys[0].y
	for i in range(1, keys.size()):
		if t <= keys[i].x:
			var a := keys[i - 1]
			var b := keys[i]
			var u := _eased(clampf((t - a.x) / maxf(b.x - a.x, 0.0001), 0.0, 1.0), ease)
			return lerpf(a.y, b.y, u)
	return keys[keys.size() - 1].y


func _eased(u: float, ease: StringName) -> float:
	match ease:
		&"out":
			return IaidoTuning.ease_out_cubic(u)
		&"in":
			return IaidoTuning.ease_in_cubic(u)
		&"linear":
			return u
		_:
			return IaidoTuning.ease_in_out(u)


# Every continuous quantity in the ceremony goes through this. `_track` alone is
# only safe for tracks whose keys are guaranteed to sit outside the stops.
func _ctrack(t: float, keys: Array[Vector2], ease: StringName = &"in_out") -> float:
	return _track(t, _hold_across_stops(keys, ease), ease)
