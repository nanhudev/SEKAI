extends SceneTree
##
## Renders a scripted tour of the combat matrix into a PNG sequence, so the
## new systems can actually be WATCHED instead of inferred from green tests.
##
## The Iaido renderer pins its timeline with an explicit debug-hold because that
## ceremony is a fixed script. Combat is not: moves are driven by input, windows
## by wall clock (`CombatController._now()` reads Time.get_ticks_msec()), and a
## pinned clock would desync the two. So this one runs in REAL TIME and measures
## how much game time each captured frame actually covered, then hands the
## resulting frame rate to the encoder. That way the clip plays back at true
## speed no matter how fast this machine happens to render.
##
## Engine.time_scale is deliberately left alone: it scales `delta` (which drives
## animation and move progression) but NOT `_now()` (which drives riposte /
## bind / chain windows). Touching it would make the animation and the windows
## disagree on screen, which is exactly the kind of thing this video exists to
## expose, not to hide.
##
## Usage:
##   godot --path godot --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/combat_movie_renderer.gd -- <output_dir>

const OUT_DEFAULT := "res://../.render/combat"
const PLAYER_Y := 1.15
const DUMMY_DROP := 0.55      # dummy origin is below the player's eye line
const SETTLE := 0.7           # quiet beat at the top of every segment
# How long a refused chain beat keeps asking before the take gives up and says so out
# loud (see _chain_beat). Generous on purpose: at 20fps this is 2s, and a beat that
# takes 2s to be accepted was never going to be accepted — the point of the number is
# to turn a SILENT dropped beat into a printed one, not to time the retry.
const BEAT_PATIENCE_FRAMES := 40

var output_dir := ""
var frame_index := 0
var sandbox: Node3D
var player: CharacterBody3D
var combat: CombatController
var dummy: Node3D
var look_pivot: Node3D
var props: WindProps
var lane: MovementLane
var lab: ChainLab
var chain: ChainDirector
var weapon: WeaponSlot

var layer: CanvasLayer
var title_label: Label
var status_label: Label
var note_label: Label
# A first-person shot of a 1.8m placeholder cone from 2m away is a wall of white,
# which makes every claim about the blade unverifiable. This camera sits at three
# quarters and reads the pair from outside. It is safe to do because the sword is
# parented to the player's own camera rig, so the pose keys — which are written in
# camera space — still describe the player's view, not the review camera's.
var review_camera: Camera3D
# The player's own camera. The chain tour shoots FIRST PERSON by default, because
# that is the only venue this weapon is authored for and the only one its claims
# can be judged in: the handle is parented to camera space, the links are 5cm, and
# §28–§32 (camera language, the head leaving frame but staying findable, no orbit)
# are all statements about what the player sees. From a review camera seven metres
# back the same chain is a dotted line — technically the same geometry, and no
# evidence at all.
var player_camera: Camera3D
# The weapon layer: right in first person, a duplicate floating sword otherwise.
var foreground_layer: CanvasLayer
# A recording-only stand-in for the player's body on the outside shots.
var review_body: Node3D

var segments: Array = []
var seg_name := ""
var seg_note := ""
# Tight by default; the takes that have to show a wall or a thrown crate widen it.
var seg_fov := 38.0
# Per-take camera overrides. A chain reaches 4.6m, so the framing rule that works
# for an 80cm katana leaves the far half of every sweep outside the shot: these
# takes pull the lens back, up and out, and aim further down the chain.
var seg_cam: Dictionary = {}
# Whether this take is shot from the player's own eyes (see player_camera).
var seg_fp := false
# Look pitch in degrees, negative = down. See _stand_in_lab.
var seg_pitch := -2.3
# A chain beat that was refused and is still owed (see _chain_beat).
var _beat_action := &""
var _beat_expect := &""
var _beat_frames := 0
# Seconds elapsed inside the take being shot. Events get the loop's clock directly
# (see `_run_segment`), but a STILL RULE is a predicate evaluated inside `_save()`,
# where there is no `t` in scope — so the clock is parked on a member.
var _seg_t := 0.0
# Pending still captures for the current take: {"tag": String, "when": Callable,
# "done": bool}. Declared per take so a still can never be filed under a picture
# taken in a different take, and CONDITION-driven rather than time-driven because
# "the peak of the arc" is a position, not a timestamp — a frame-clock event on a
# real-time renderer lands wherever the machine happened to be that frame (see
# `_still_when`).
var _stills: Array = []
# "review" (outside camera) or "fp" (the player's own eyes); see _run_segment.
var cam_mode := "review"
# "clean" (default) or "hud": whether the developer status column is drawn. See the
# note in _initialize — the film is meant to be judged without it (§46/§51).
var hud_mode := "clean"
# THE PROBLEMS REEL'S ONE LABEL (§PART H). A take in the fault clip may say ONE
# thing, in the bottom left, and nothing else — no time code, no note, no panel.
# That is a different artefact from `clean` (captions with a clock) and from
# `silent` (nothing at all), so it gets its own mode rather than being assembled
# out of those two.
var problem_label: Label = null
# The spells this take claims to be showing. The overlay prints what is ACTUALLY
# armed next to it, so a caption that drifts from the code is visible in the very
# frame that makes the claim — which is how the fire takes were caught promising
# a burning field while casting 火矢, a spell that leaves no field at all.
var seg_spells: Array = []
# 势 peaks recorded inside a take, printed with its summary line.
var seg_metrics: Array[String] = []
# The chain's own counters at the start of the take, so the segment can report what
# the WEAPON did rather than what the caption claims it did. See the report at the end
# of `_run_segment`.
var seg_hits_before := 0
var seg_walls_before := 0
var flow_peak := 0.0
var run_origin := Vector3.ZERO

# --- §MOTION review numbers --------------------------------------------------
#
# THE MOTION PASS IS JUDGED FROM THE PICTURE, BUT IT IS ARGUED WITH NUMBERS.
#
# Every claim in §2–§14 is a claim about a displacement that is deliberately small
# — a lag of a few centimetres, a turn-back of three to eight degrees, a handle
# hauled two to five. At 480p on a review screen none of those are measurable by
# eye, and the failure mode is not "it looks wrong", it is "it looks like nothing
# is happening". So each take carries the PEAK (or, for the clamp, the minimum)
# of the readings the slice tests already assert on, sampled every frame and
# printed with the take summary — the same discipline as `chain hits +N walls +N`:
# the take is asked what it did rather than trusted to have done it.
var motion_peak_drag := 0.0      # §2/§3 inertia alone, in metres
var motion_peak_turn := 0.0      # §4 angle behind the hand, in degrees
var motion_min_scale := 1.0      # §5 clamp compression, 1.0 = never intervened
var motion_peak_idle := 0.0      # §7 breathing drift alone, in metres
var motion_peak_resist := 0.0    # §14 handle haul, TOTAL (preload + load), in metres
var motion_peak_layers := 0.0    # §6 outermost arc's lean, in metres
var motion_speed_peak := 0.0     # the hand speed that drove the drag
# HOW OFTEN §5's CLAMP ACTUALLY INTERVENED, because a bare minimum cannot be read.
# `clamp 0.0000` printed alone means "on at least one frame the motion was compressed
# to nothing" — which is the same sentence whether that frame was a single settling
# frame or the entire take. The count is what separates "the safe zone held" from
# "the safe zone ate the take", and the latter is a bug in the tuning rather than a
# pass of the rule.
var motion_clamped_frames := 0
var motion_sampled_frames := 0

# §4's fast turn, as a rate held for a number of wall seconds. See `_yaw`.
var turn_rate := 0.0             # degrees per second, applied to the body each frame
var _turn_until := -1.0          # the segment clock at which the rate stops

const MOVE_ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"walk"]
# ArenaDressing's far wall (0.7 thick, centred z = -17, zero collision) and the
# chain lab's near edge. The camera guard below needs both to tell "subject in the
# arena" from "subject behind the wall". WALL_Z is the wall's LAB-SIDE face, not
# its centre: a camera on the arena side of that face is looking through 0.7m of
# placeholder box, however far in front of it the centre is. (The probe that found
# this bug sat at z = -16.6 — half a metre "in front" of the wall, and blind.)
const ARENA_WALL_Z := -17.4
const LAB_ENTRY_Z := -19.0
# Default look-down for a first-person chain take: the eye is at 1.9m, the chain
# swings at about 1.1m, so level looks over the top of every sweep.
const FP_PITCH := -13.0
var start_ms := 0
# Every bind segment reports whether the real hurtbox path actually produced a
# perfect guard. A demo that quietly faked it would be worse than no demo.
var parry_landed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path(OUT_DEFAULT)
	# Rendering the whole tour to check one framing change costs a full minute,
	# so a take count and a start index make the loop short.
	var max_segments := int(args[1]) if args.size() > 1 else 999
	var start_segment := int(args[2]) if args.size() > 2 else 0
	# Two tours, one renderer. The sword tour and the chain tour share every piece
	# of machinery (real-time capture, measured frame rate, the review camera, the
	# overlay), and differ only in which takes are on the list.
	var tour := String(args[3]) if args.size() > 3 else "sword"
	# "fp" shoots every take from the player's eyes unless the take overrides it;
	# "review" (the default) reproduces the sword tour's outside camera.
	cam_mode = String(args[4]) if args.size() > 4 else "review"
	# §46/§51: the acceptance clip is a CLEAN artefact. The status column is the
	# developer readout — radius, momentum, tension, hook target — and a clip that
	# needs those numbers on screen to make its point is a clip that has not made its
	# point: "重 / 拉 / 绷紧 / 不同重量反应" have to be visible in the picture. The
	# captions stay, because they are the film's voice rather than a debug dump, and
	# `hud` puts the numbers back for the times when a take is being diagnosed.
	hud_mode = String(args[5]) if args.size() > 5 else "clean"
	DirAccess.make_dir_recursive_absolute(output_dir)
	_clear_existing_frames()

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# Same reason as the Iaido renderer: a covered window stops firing
	# frame_post_draw and the capture loop hangs forever.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	# A CAPTURE IS NOT A DISPLAY, SO IT MUST NOT BE VSYNC-CAPPED.
	#
	# The capture is real-time: it advances the game clock by the wall delta of each
	# drawn frame and writes the measured rate to `fps.txt` for the encode. That makes
	# the film's own timing a function of how fast the loop runs, so a refresh-rate cap
	# is not a neutral setting — it silently RESAMPLES the whole film. The V4 slice was
	# measured at 16–18 fps with vsync on, i.e. the strip of the weapon that §9 asks for
	# (an 80–160ms wind-up) was being sampled about ten frames wide, and the encode then
	# replayed those samples as if they were real time. Uncapped the same takes measure
	# considerably higher on the same machine.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	sandbox = load("res://scenes/combat/CombatSandbox.tscn").instantiate() as Node3D
	window.add_child(sandbox)

	await process_frame
	await process_frame
	await process_frame

	player = sandbox.get_node("Player") as CharacterBody3D
	combat = player.get_node("CombatController") as CombatController
	dummy = sandbox.get_node("TechnicalDummy") as Node3D
	look_pivot = player.get_node("CameraRig/LookPivot") as Node3D
	player_camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	props = sandbox.get_node("WindProps") as WindProps
	lane = sandbox.get_node_or_null("MovementLane") as MovementLane
	lab = sandbox.get_node_or_null("ChainLab") as ChainLab
	chain = player.get_node("ChainDirector") as ChainDirector
	weapon = player.get_node("WeaponSlot") as WeaponSlot
	# The chain narrates itself. A take that claims a perfect 截链 but never landed
	# one would otherwise be indistinguishable in the log from one that did.
	if chain != null:
		chain.message.connect(func(text: String) -> void: print("      · " + text))

	# The Lab and the HUD belong to the person playing, not to the recording.
	_hide(&"DeveloperPanel")
	_hide(&"ParryDebugOverlay")
	_hide(&"CombatHUD")
	# §17's training-ground legend is a key list for someone who does not know the
	# bindings, which is exactly what a review clip is NOT for: §46/§51 want the
	# artefact clean, and a table of WASD in the corner is a caption about the
	# controls in a clip that is supposed to be about the weapon.
	if lab != null:
		lab.set_legend_visible(false)
	# The foreground weapon layer exists to keep the blade from clipping into the
	# world in first person. From three quarters it draws a second sword floating
	# over the shot.
	#
	# ...BUT IT IS ALSO WHERE THE CHAIN'S HANDLE LIVES. The layer moves every mesh
	# under WeaponRoot onto its own render layer and then clears that layer from the
	# world camera, so hiding the layer does not remove a duplicate — it removes the
	# hand. Handled per take in _run_segment instead of switched off here.
	foreground_layer = sandbox.get_node_or_null("ForegroundWeaponLayer") as CanvasLayer
	if foreground_layer != null:
		foreground_layer.visible = false
	# The dev readout follows the same switch as the overlay that draws it: a clean
	# take has no numbers anywhere, and a hud take has all of them.
	if chain != null:
		chain.debug_readout = hud_mode == "hud"
	player.unlimited_resources = true
	# The dummy attacking on its own would poison every take that is not about
	# being attacked.
	dummy.set("attack_cooldown", 9999.0)

	_build_overlay()
	if tour == "story":
		_build_chain_story_segments()
	elif tour == "chain":
		_build_chain_segments()
	elif tour == "movement":
		_build_movement_segments()
	elif tour == "universal":
		_build_universal_segments()
	elif tour == "styles":
		_build_styles_segments()
	elif tour == "chainfp":
		_build_chain_fp_segments()
	elif tour == "chainidle":
		_build_chain_idle_segments()
	elif tour == "chainv4":
		_build_chain_v4_segments()
	elif tour == "motion":
		_build_chain_motion_segments()
	elif tour == "chainglobal":
		_build_chain_global_segments()
	elif tour == "magic":
		_build_magic_segments()
	elif tour == "play":
		_build_play_segments()
	elif tour == "problems":
		_build_problem_segments()
	else:
		_build_segments()
	_build_review_camera()
	_build_review_body()

	print("window=", root.size, "  tour=", tour, "  segments=", segments.size())
	print("rendering combat tour to: ", output_dir)

	start_ms = Time.get_ticks_msec()
	for i in range(start_segment, mini(segments.size(), start_segment + max_segments)):
		await _run_segment(segments[i])

	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var fps := float(frame_index) / maxf(elapsed, 0.001)
	print("frames=%d  wall=%.2fs  -> ENCODE_FPS=%.3f" % [frame_index, elapsed, fps])
	_write_fps(fps)
	quit()


func _hide(node_name: StringName) -> void:
	var node := sandbox.get_node_or_null(NodePath(String(node_name)))
	if node is CanvasLayer or node is Control:
		(node as Node).set("visible", false)


# --- segments ---------------------------------------------------------------

func _build_segments() -> void:
	# A take is: name, setup, [time, action] pairs, duration.
	segments = [
		{
			"name": "通用剑 · 四段连击",
			"setup": func() -> void:
				_clean_arena(&"universal")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.1),
			"events": [
				[SETTLE + 0.10, _req.bind(&"light")],
				[SETTLE + 0.55, _req.bind(&"light")],
				[SETTLE + 1.00, _req.bind(&"light")],
				[SETTLE + 1.45, _req.bind(&"light")],
				[SETTLE + 2.60, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 4.4,
		},
		{
			"name": "回风式 · 四段链 + 势(Flow)",
			"setup": func() -> void:
				_clean_arena(&"flowing_wind")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.2),
			"events": [
				[SETTLE + 0.10, _req.bind(&"light")],
				[SETTLE + 0.50, _req.bind(&"light")],
				[SETTLE + 0.90, _req.bind(&"light")],
				[SETTLE + 1.30, _req.bind(&"light")],
				[SETTLE + 2.60, _req.bind(&"light")],
			],
			"duration": SETTLE + 4.4,
		},
		{
			"name": "藏锋流 · 拔刀红利 → 截锋",
			"note": "纳刀状态下出刀更快、更重；完美格挡后归鞘前摇被免除",
			"setup": func() -> void:
				_clean_arena(&"hidden_edge")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 1.9),
			"events": [
				[SETTLE + 0.10, _req.bind(&"light")],
				[SETTLE + 1.60, _req.bind(&"light")],
				[SETTLE + 2.00, _req.bind(&"light")],
				[SETTLE + 3.30, _guard_up],
				[SETTLE + 3.36, _enemy_hit_on],
				[SETTLE + 3.44, _enemy_hit_off],
			],
			"duration": SETTLE + 5.0,
		},
		{
			"name": "白蔷庭 · Measure 近 / 理想 / 远",
			"note": "同一招「穿庭」在三个距离上的削势差异 —— 伤害完全相同",
			"setup": func() -> void:
				_clean_arena(&"white_rose")
				_move_pair(Vector3(0.0, PLAYER_Y, -0.6), 1.1),
			"events": [
				[SETTLE + 0.20, _req.bind(&"heavy")],
				[SETTLE + 1.60, _move_pair.bind(Vector3(0.0, PLAYER_Y, -0.6), 2.3)],
				[SETTLE + 2.30, _req.bind(&"heavy")],
				[SETTLE + 3.70, _move_pair.bind(Vector3(0.0, PLAYER_Y, -0.6), 4.0)],
				[SETTLE + 4.40, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 6.2,
		},
		{
			"name": "白蔷庭 · 缠剑 BIND → 轻 = 合围刺",
			"note": "完美格挡不弹开、不侧移；剑被锁住 0.3s，之后由玩家决定",
			"setup": func() -> void:
				_clean_arena(&"white_rose")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.0),
			"events": [
				[SETTLE + 0.60, _guard_up],
				[SETTLE + 0.66, _enemy_hit_on],
				[SETTLE + 0.74, _enemy_hit_off],
				[SETTLE + 1.05, _req.bind(&"light")],
			],
			"duration": SETTLE + 3.6,
		},
		{
			"name": "白蔷庭 · 缠剑 BIND → 重 = 脱手斩",
			"note": "同一个缠剑，另一个答案：向后脱离，不在原地换血",
			"setup": func() -> void:
				_clean_arena(&"white_rose")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.0),
			"events": [
				[SETTLE + 0.60, _guard_up],
				[SETTLE + 0.66, _enemy_hit_on],
				[SETTLE + 0.74, _enemy_hit_off],
				[SETTLE + 1.05, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 3.6,
		},
		{
			"name": "白蔷庭 · 假章（起手里收回的假动作）",
			"note": "上半段是假章被提前取消，下半段是真招穿庭，两者起手应当难以分辨",
			"setup": func() -> void:
				_clean_arena(&"white_rose")
				_place(Vector3(0.0, PLAYER_Y, -0.6), 2.3),
			"events": [
				[SETTLE + 0.20, _trigger_skill.bind(0)],
				[SETTLE + 0.42, _req.bind(&"light")],
				[SETTLE + 2.30, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 4.0,
		},
		{
			"name": "火 · 焚环：留一片燃烧的地面",
			"note": "火的身份是「选在哪里打」：它留下一片区域，让站在里面的目标持续、不规则地烧，而且剑穿过它会被点燃",
			"spells": [&"flame_ring"],
			"setup": func() -> void:
				_clean_arena(&"universal")
				_spell(&"flame_ring")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.4),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
			],
			"duration": SETTLE + 5.2,
		},
		{
			"name": "冰 · 寒流爬梯：三下才到冻结",
			"note": "普通 / 冰寒 / 霜覆 / 冻结：寒流便宜、要次数；冻结很短，但目标变脆",
			"spells": [&"frost_stream"],
			"setup": func() -> void:
				_clean_arena(&"universal")
				_spell(&"frost_stream")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.2),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
				[SETTLE + 1.60, _req.bind(&"cast")],
				[SETTLE + 3.00, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.6,
		},
		{
			"name": "冰 · 凝霜：一次买一阶（刻意买不到冻结）",
			"note": "同一个学派的两个选择。凝霜一次跨一阶霜覆，所以能立刻接脆化破 —— 但最后一阶仍然得自己挣，冷却 5s",
			"spells": [&"frost_burst"],
			"setup": func() -> void:
				_clean_arena(&"universal")
				_spell(&"frost_burst")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.2),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
			],
			"duration": SETTLE + 3.6,
		},
		{
			"name": "剑 × 魔法 · 冻结 → 重击 → Shatter",
			"note": "参考连击：冻结 + 重击 = 碎裂",
			"setup": func() -> void:
				_clean_arena(&"universal")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 1.8),
			"events": [
				[SETTLE + 0.20, _dummy_state.bind(&"frozen")],
				[SETTLE + 1.10, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 3.6,
		},
		{
			"name": "风 · 风压：轻物被推出去，重物几乎不动",
			"note": "同一个阵风：布箱被扔出去，遗迹哨兵几乎不动 —— 风是力，不是伤害",
			"spells": [&"wind_pressure"],
			"fov": 54.0,
			"setup": func() -> void:
				_clean_arena(&"universal")
				_spell(&"wind_pressure")
				_release_props()
				_move_pair(WindProps.WALL_TEST_PLAYER, 3.3),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.0,
		},
		{
			"name": "风 × 火 · 风把已经在烧的地面推出去",
			"note": "风不点燃任何东西：它把一片正在燃烧的地面扩大、推到别人身上",
			"spells": [&"flame_ring", &"wind_pressure"],
			"fov": 46.0,
			"setup": func() -> void:
				_clean_arena(&"universal")
				_spell(&"flame_ring")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.4),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
				[SETTLE + 2.00, _spell.bind(&"wind_pressure")],
				[SETTLE + 2.30, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.6,
		},
		{
			"name": "风步 · 同一套刀，站着打 vs 动起来打",
			"note": "交互 5 的前半段：同样三刀，移动中命中喂的势更多（sprint 攻击 19 / 站桩 12）。风步换的是动量，不是传送",
			"spells": [&"wind_step"],
			"fov": 50.0,
			"setup": func() -> void:
				_clean_arena(&"flowing_wind")
				_spell(&"wind_step")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 3.1),
			"events": [
				# Phase 1 — standing. This is the baseline the second phase is
				# measured against, in the same take, on the same dummy.
				[SETTLE + 0.05, _metric_reset],
				[SETTLE + 0.10, _req.bind(&"light")],
				[SETTLE + 0.55, _req.bind(&"light")],
				[SETTLE + 1.00, _req.bind(&"light")],
				[SETTLE + 1.50, _metric.bind("站着三刀")],
				# Phase 2 — moving. 势 is zeroed so the peak measures only these
				# three cuts. The direction is HELD ACROSS each light request,
				# because that is the instant the controller samples movement
				# intent; releasing first would reproduce the standing case.
				[SETTLE + 1.60, combat.reset_flow],
				[SETTLE + 1.65, _spell.bind(&"wind_step")],
				[SETTLE + 1.70, _req.bind(&"cast")],
				[SETTLE + 2.15, _hold.bind(&"move_forward", true)],
				[SETTLE + 2.50, _req.bind(&"light")],
				[SETTLE + 2.62, _hold.bind(&"move_forward", false)],
				[SETTLE + 2.95, _hold.bind(&"move_forward", true)],
				[SETTLE + 3.30, _req.bind(&"light")],
				[SETTLE + 3.42, _hold.bind(&"move_forward", false)],
				[SETTLE + 3.75, _hold.bind(&"move_forward", true)],
				[SETTLE + 4.10, _req.bind(&"light")],
				[SETTLE + 4.22, _hold.bind(&"move_forward", false)],
				[SETTLE + 4.60, _metric.bind("移动三刀")],
			],
			"duration": SETTLE + 5.4,
		},
		{
			"name": "风步 · 同一段时间的位移：无风步 vs 有风步",
			"note": "在专用移动平台上跑直线（假人已挪开）：同样 1.6 秒，有风步多跑一截。风步改的是动量，不是传送",
			"spells": [&"wind_step"],
			"fov": 52.0,
			"setup": func() -> void:
				_clean_arena(&"flowing_wind")
				_enter_lane()
				_spell(&"wind_step"),
			"events": [
				# Baseline first, then the same run with the buff. Both legs are
				# measured from the same start line on the same platform, so the
				# difference is the buff and nothing else.
				[SETTLE + 0.60, _note_run_origin],
				[SETTLE + 0.65, _hold.bind(&"move_forward", true)],
				[SETTLE + 2.25, _hold.bind(&"move_forward", false)],
				[SETTLE + 2.35, _metric_distance.bind("无风步 1.6s")],
				[SETTLE + 2.55, _enter_lane],
				[SETTLE + 2.70, _req.bind(&"cast")],
				[SETTLE + 3.20, _note_run_origin],
				[SETTLE + 3.25, _hold.bind(&"move_forward", true)],
				[SETTLE + 4.85, _hold.bind(&"move_forward", false)],
				[SETTLE + 4.95, _metric_distance.bind("有风步 1.6s")],
			],
			"duration": SETTLE + 5.8,
		},
		{
			"name": "风推 · 撞墙",
			"note": "被推的对象撞上实体才会产生冲击 —— 没有环境，风只是一个击退数字",
			"spells": [&"wind_pressure"],
			"fov": 58.0,
			"setup": func() -> void:
				_clean_arena(&"universal")
				_spell(&"wind_pressure")
				_release_props()
				_move_pair(WindProps.WALL_TEST_PLAYER, 1.5),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.0,
		},
	]


# 缚星链 · PHASE 0–1 (§55). Eight takes, and between them they are the whole
# argument: a wide sweep, momentum that arrives sooner instead of hitting harder,
# a throw that goes taut and changes what the buttons do, and a hook whose outcome
# is decided by the weight of what it caught.
func _build_chain_segments() -> void:
	# The chain takes see a 4.6m weapon from 5m behind, so they run a wider lens and
	# a camera that is further out and aims further down the chain. Everything else
	# about the framing rule is unchanged.
	var wide := {"side": 3.8, "back": 5.4, "up": 4.6, "aim": 2.6}
	var wider := {"side": 4.4, "back": 6.0, "up": 5.0, "aim": 3.0}
	# The hook family has to be shot from outside, and every one of them is here for
	# the same reason: 缚 and 曳 END with the target and the player at contact range,
	# so first person ends every one of those takes as a screen full of the target's
	# body. That is honest — a real enemy pulled onto you does fill your view — but it
	# is the placeholder cone that makes it unreadable, and an acceptance clip that
	# shows four seconds of white cone proves nothing about the hook. Close and low,
	# so the chain is still a chain at four metres.
	var tight := {"side": 3.2, "back": 4.2, "up": 2.2, "aim": 1.8}
	# WHY THE STAGE IS THIS DEEP. The camera sits `back` metres BEHIND the player,
	# and ArenaDressing stands a 34m wide, 5.6m tall wall across z = -17 — the
	# boundary between the arena and this room. A take staged at the lab's near edge
	# (z = -22) therefore parked the review camera at z = -16.6, i.e. behind that
	# wall, and rendered the back of a placeholder box for four seconds. Standing
	# deeper puts the camera on the lab side of it without changing a single framing
	# number: the presets above stay exactly as tuned.
	var stand_z := -25.5
	segments = [
		{
			"name": "缚星链 · 横缚 → 返扫 → 下砸",
			"note": "三连。横/横/纵 —— 第三击换的是轴，不是更大的数字。链头不回收，第二击带着第一击还没停下的惯性。",
			"fov": 48.0,
			"cam": wide,
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_LIGHT])
				_stand_in_lab(0.0, stand_z)
				_chain_target(ElementLibrary.WEIGHT_LIGHT, 3.2),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"light", &"ch_sweep")],
				[SETTLE + 0.50, _chain_req_expect.bind(&"light", &"ch_return")],
				[SETTLE + 0.90, _chain_req_expect.bind(&"light", &"ch_slam")],
			],
			"duration": SETTLE + 2.6,
		},
		{
			"name": "缚星链 · 一个横缚，两个目标",
			"note": "145° 的横扫。一次攻击打中两个敌人是这把武器存在的理由 —— 它问的是空间，不是精準。",
			"fov": 48.0,
			"cam": wide,
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_LIGHT, ElementLibrary.WEIGHT_MEDIUM])
				_stand_in_lab(0.0, stand_z)
				_chain_target(ElementLibrary.WEIGHT_LIGHT, 3.0, -1.5)
				_chain_target(ElementLibrary.WEIGHT_MEDIUM, 3.0, 1.5),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"light", &"ch_sweep")],
			],
			"duration": SETTLE + 2.0,
		},
		{
			"name": "缚星链 · 蓄势回旋 → 甩星 → 绷切",
			"note": "按住重击即回旋，转得越久链头越快；松手甩出去 —— 扔出去的链一定会到最大半径，绷紧时轻击变成绷切。",
			"fov": 54.0,
			"cam": wider,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, stand_z),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"heavy", &"ch_orbit")],
				# Released with a margin on purpose. The orbit throws ITSELF at
				# orbit_max_hold (1.30s), and this event used to sit 0.10s inside that
				# cap — which is fine at 20fps and refused at 8fps, because a frame is
				# then 0.12s of game time and the event lands after the window has
				# already closed. A take may not depend on the frame rate.
				[SETTLE + 1.08, _chain_release_expect.bind(&"ch_launch")],
				[SETTLE + 2.60, _chain_req_expect.bind(&"light", &"ch_snap")],
			],
			"duration": SETTLE + 4.0,
		},
		{
			"name": "缚星链 · 缠锁 · 轻 → 缚 → 拉近斩",
			"note": "钩住轻型目标：是它被拉过来。缚 不是一次吸附 —— 2.3m 分成五记递减的拉扯，每一记之间身体会停一下再被拽走，总距离不变，变的是节奏。缚 打开 1.00s 窗口，轻击在窗口里变成拉近斩。",
			"fov": 56.0,
			"fp": false,
			"cam": tight,
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_LIGHT])
				_stand_in_lab(0.0, stand_z)
				_chain_target(ElementLibrary.WEIGHT_LIGHT, 3.6),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
				# THE EXIT HAS TO LAND INSIDE THE WINDOW IT EXITS. 缚 opens 1.00s here and
				# the haul it starts runs for ~1.2s, so the tempting move — delay the exit
				# until the haul has finished — pushes it past the window and the request
				# is simply REFUSED (the renderer prints `!! light refused`, which is how
				# this was caught). The haul outliving the bind is the DESIGN (see
				# `_release_hook` in chain_director.gd); the exit is a separate deadline.
				# 0.75s into a 1.00s window, which also survives an 8fps frame.
				[SETTLE + 1.80, _chain_req_expect.bind(&"light", &"ch_pull_cut")],
			],
			# Longer than the events need, on purpose: the SECOND haul (拉近斩 is 拉且松,
			# so it re-arms the sequence) is where the 顿挫 rhythm is actually watched.
			"duration": SETTLE + 4.2,
		},
		{
			"name": "缚星链 · 缠锁 · 重 → 缚 → 地砸",
			"note": "同一个输入，重型敌人不动，被拉过去的是你 —— 重型敌人不是受害者，是锚。而且这一记拉扯是五下顿挫，不是一次吸附：每一记你都看得见自己被拽近了。缚 只开 0.40s，重击在窗口里变成地砸。",
			"fov": 56.0,
			"fp": false,
			"cam": tight,
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_HEAVY])
				_stand_in_lab(0.0, stand_z)
				_chain_target(ElementLibrary.WEIGHT_HEAVY, 3.6),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
				# 0.25s into a 0.40s window. This is the tightest timing in the whole tour:
				# a heavy is given the SHORTEST bind on purpose (§18's counterplay), so the
				# exit has almost no room — and when it missed, this take did not fail, it
				# silently played 蓄势回旋 → 甩星 instead of 地砸. The caption and the
				# animation disagreed and nothing in the log said so.
				[SETTLE + 1.30, _chain_req_expect.bind(&"heavy", &"ch_ground_slam")],
			],
			"duration": SETTLE + 4.2,
		},
		{
			"name": "缚星链 · 曳 (不缚，直接拉)",
			"note": "曳 是同一个拉扯，提前用、打折用 —— 但它同样是五记顿挫，不是一次吸附。这次双方都动了，谁动多少由重量表决定。",
			"fov": 56.0,
			"fp": false,
			"cam": tight,
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_MEDIUM])
				_stand_in_lab(0.0, stand_z)
				_chain_target(ElementLibrary.WEIGHT_MEDIUM, 3.8),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req_expect.bind(&"heavy", &"ch_yank")],
			],
			"duration": SETTLE + 3.8,
		},
		{
			"name": "缚星链 · 钩住固定物 (锚)",
			"note": "钩住石柱就是钩住一个重型敌人：柱子不动，动的是你 —— 一记一记被拽过去。没有一行专门为锚写的代码。",
			"fov": 56.0,
			"fp": false,
			"cam": tight,
			"setup": func() -> void:
				_enter_lab([])
				# The anchor is scenery at a fixed spot, so this take cannot simply
				# walk deeper — it has to change which way it faces. Standing beyond
				# the pillar and looking BACK down the lab (yaw 180) puts the camera
				# deeper instead of into the arena wall, and turns the pull into a
				# move toward the lens, which is the whole claim of the shot.
				_stand_in_lab(ChainLab.ANCHOR_POSITION.x, -30.0, 180.0),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
			],
			"duration": SETTLE + 3.8,
		},
		{
			"name": "缚星链 · 钩住头顶横杆 (瞄哪打哪)",
			"note": "抛出方向跟着准心走 —— 抬头 28°，链头就从自己头顶上方飞出去，钩住横杆。没有这一条，世界里所有高的东西（横杆、废墟环、树杈）都钩不到，游链以后也就没有锚点。横杆是重的，所以被拉过去的还是你。",
			# §13: the throw is released TOWARD THE AIM, and this is the take that says
			# so — the one claim that cannot be filmed from the outside camera, because
			# it is about where the player was looking.
			"fov": 62.0,
			"pitch": 28.6,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(
					ChainLab.HIGH_ANCHOR_POSITION.x, ChainLab.HIGH_ANCHOR_POSITION.z + 3.4
				),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
			],
			"duration": SETTLE + 2.8,
		},
		{
			"name": "缚星链 · 撞墙",
			"note": "链头不会穿过石面 —— 扔空的一击撞在墙上，丢掉大部分势。空间有代价，链才是链。",
			"fov": 56.0,
			"cam": wider,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, -38.0),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
			],
			"duration": SETTLE + 2.6,
		},
		{
			"name": "缚星链 · 风 × 链",
			"note": "风不给链加伤害，它加转速 —— 而转速是这把武器自己的货币。回旋中吃到风，甩出去就更重。",
			"fov": 54.0,
			"cam": wider,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, stand_z)
				_spell(&"wind_step"),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"heavy", &"ch_orbit")],
				# Cast as early as the orbit allows. 风 is a boost to the SPIN, so it
				# only pays for the seconds it is actually held — cast at 0.55s against
				# a release at 1.05s it bought three points of launch, which is not an
				# argument, it is noise. Take 2 holds for exactly the same 0.95s with no
				# spell, so the only difference between the two takes is the wind.
				[SETTLE + 0.20, _req.bind(&"cast")],
				[SETTLE + 1.05, _chain_release_expect.bind(&"ch_launch")],
			],
		"duration": SETTLE + 3.4,
	},
	]


# ============================================================================
#  §32 · THE CLEAN TOUR — the chain as a PHYSICAL STORY, not a feature list.
# ============================================================================
#
# WHY THIS IS A SECOND TOUR AND NOT A REORDER OF THE FIRST ONE. The tour above was
# built to answer "does this feature exist", so its takes are named after features
# and ordered the way the weapon was implemented. That is the right film for a
# reviewer who has the design document open and the wrong one for the question this
# pass actually asks, which is:
#
# THE V3 UPDATE. The weapon changed shape underneath this film — a 4.6m chain held
# in a fist became a 10m chain coiled in a fist — and that changes what the first
# two beats are even ABOUT. So beat 1 is no longer "watch the rope hang" (a 10m rope
# would be a line running off the bottom of the frame); it is "look at how much
# chain is still in the hand", which is §26's claim and only exists in first person.
# Beat 3 is no longer 横 → 返 → 砸: A3 changes the weapon's whole subject, so the
# take now plays the actual light chain — 左甩 / 快右左 / 直抛 — which is the exact
# sentence PART O asks a stranger to read off clean video.
#
#   can a player who cannot see a HUD, a skill name, an effect or a final sound
#   read 松 / 甩 / 左甩 / 快右左 / 直抛 out of the motion alone?
#
# So this tour is ordered as a story told in ten beats, each one about a DIFFERENT
# physical problem, and every take is filmed so the thing that changed is the thing
# the frame is about. It is shot with `chain <fp|review> clean` (no debug numbers)
# and there is a `silent` HUD mode that drops the captions too, for the screening
# where the viewer has been told nothing at all.
#
# V3 films the loop TWICE, from the eyes and from the side, because those two views
# can see different beats (see the note on `loop`): a sentence verified from only one
# of them is a sentence verified in one of its two required senses — PART O asks what
# a PLAYER reads, and PART A asks whether the three beats are really three.
func _build_chain_story_segments() -> void:
	var wider := {"side": 4.4, "back": 6.0, "up": 5.0, "aim": 3.0}
	var tight := {"side": 3.2, "back": 4.2, "up": 2.2, "aim": 1.8}
	# 3b's framing — the loop shot from OUTSIDE, and the reason it exists is a
	# measurement: 直抛 is INVISIBLE in first person. It is the one beat of the three
	# whose motion is along the view axis, so from the hand that threw it the chain
	# foreshortens to nothing — the frame at t=2.49s of the first-person take shows
	# the head 9.6m away as a pale dot beside the fist, because 9.6m straight ahead of
	# a 1.91m eye is 4.5° below the crosshair. Nine metres of reach, and the shot says
	# the chain never left. No retiming fixes a view that is edge-on to the motion, so
	# the sentence is filmed twice: once from the eyes (can the player read it) and
	# once from the side (are there really three beats).
	var loop := {"side": 5.0, "back": 5.6, "up": 3.4, "aim": 2.8}
	# V3 · 松 is no longer a shot of a hanging rope, it is a shot of the BUNDLE — and
	# the bundle is welded to the player's own hand (ChainHandAnchor), so this is the
	# one take that has to be shot FIRST PERSON: from the review rig the same bundle
	# is a fist-sized column two metres from the lens, which is not where §26's claim
	# lives. Nothing in this dictionary applies to it.
	#
	# V3 · the loop take is shot FIRST PERSON, and that is a correction rather than a
	# preference.
	#
	# §PART G is explicit that the chain may leave the screen and that only the hand,
	# the rope's direction and the tension line have to stay findable — and PART O's
	# gate is what a PLAYER reads, and the player is inside this camera. Shooting the
	# loop from the review rig answered a question nobody asked: the first V3 loop take
	# held the whole 4.3m arc in frame and the verdict on it was still unreadable,
	# because at 5–6m a 7cm chain is a 6px filament against a light deck. The same
	# sweep seen from the hand is a bar of chain crossing the lens.
	#
	# The far end of the three-beat sentence is the exception, and the 甩 take is the
	# take that owns it: 直抛 leaving frame IS the read for "this went a long way",
	# which is exactly what PART G permits.
	var stand_z := -25.5
	segments = [
		# ---------------------------------------------------------------- 1 · 松
		{
			"name": "缚星链 · 松 —— 十米收在手里",
			"note": "没有输入，而且是全部十拍里两拍第一人称的第一拍 —— 因为这一拍说的正是「玩家第一眼看见什么」。手里是一整把没放出去的链：八圈叠在拳头下面，只有末梢垂出一点点，链头把那一小段坠住。要读出来的是「这条链很长，只是现在收在手里」，而不是「这条武器只有两米」。它也不能看起来像一条从手到某处的线 —— 线读不出重量，一圈圈叠起来的金属读得出。",
			"fov": 75.0,
			"fp": true,
			# This take is shot by the PLAYER'S OWN CAMERA (fov 75, Player.tscn), not by
			# the review rig, and that is the point: the hand rides LookPivot through
			# ChainHandAnchor at camera-space (0.30, −0.34, −0.62), so the bundle's
			# on-screen place is fixed by the rig rather than by a framing choice — it
			# hangs ~26–28° below centre, well inside the 37.5° half-FOV, and no
			# `cam`/`pitch` here can move it. The only thing this take controls is
			# TIME: stand still for three seconds and let the eye count the loops.
			"pitch": -13.0,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, stand_z),
			"events": [],
			"duration": SETTLE + 3.4,
		},
		# ---------------------------------------------------------------- 2 · 甩
		{
			"name": "缚星链 · 甩 —— 绷是一个事件",
			"note": "朝空地扔出去，什么都不钩，所以这一下把整个武器都放了出去：链头一路飞到九米多，手里那八圈在飞行里被抽干。看的是绳：刚出头的十几帧它是弯的、松的，链头在飞而绳还在后面；快到长度尽头时它才在 0.05 秒里从松变直 —— 绷是一次事件，不是一条本来就直的线。",
			"fov": 54.0,
			# The taut beat now happens at 9.6m of reach instead of 4.6m, so the framing
			# has to hold the far end of the rope: a 2.6m focus would put the snap —
			# the whole point of the take — off the top of the shot.
			"cam": wider,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, stand_z),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
			],
			"duration": SETTLE + 3.2,
		},
		# ---------------------------------- 3 · 亮链三拍 · 第一人称（A1 · A2 · A3）
		{
			"name": "缚星链 · 亮链三拍 · 第一人称 —— 左甩 / 快右左 / 直抛",
			"note": "一套完整套路的第一句，也是 PART O 要看的那一句。左甩：一条又宽又重的横弧，链头从右手侧绕过身前扫到左边，大部分链还盘在手里 —— 它比剑慢，因为重的东西要花时间。第二拍不回收链头：它带着第一拍没停下来的惯性先往右再往左，两次转向都发生在链头还在飞的时候，所以这两下比第一下更快、更连。第三拍忽然换轴 —— 不再是横的弧，而是沿准星的一条前向长线，链头一路走到九米多，绳在最后 0.05 秒里从松变直。三拍之间链头一次都没有停下，这就是它和一串各自独立的动画的区别。这一拍故意打空：它要说的是动作本身，不是命中的那一下。",
			"fov": 75.0,
			# First person, so `fov`/`cam` are the player's own rig (see take 1) and all
			# this take controls is where the eye is pointed while the loop runs. −10°
			# and not the rig default of −13°: the sweep's head sits ~20° under the
			# horizon at its 4.3m reach and the throw's sits ~9° under at 9.6m, so a
			# flatter eye puts both inside the 37.5° half-FOV and keeps the deck out of
			# the top two thirds of the shot.
			"fp": true,
			"pitch": -10.0,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, stand_z),
			# The first press carries an extra 0.35s of settle on top of SETTLE, and
			# that is a measured fix, not padding. At `SETTLE + 0.10` the take dropped
			# its opening beat whenever the chain was still finishing the PREVIOUS
			# take's reel-in: the renderer logged
			#     !! light refused at 0.00s
			# and rendered a three-beat take whose first beat had never happened. It
			# survived the full nine-take tour by luck of the frame rate and died on a
			# three-take re-render, which is exactly the kind of flake a take may not
			# have — the whole loop is the claim.
			#
			# The 0.52s CADENCE is the part that is the data: 左甩 runs 0.64s and
			# 快右左 0.56s, so a press this far in lands inside the previous beat's
			# RECOVERY — the chain is cut over, never dropped — while still letting
			# nearly the whole arc of each beat reach the screen. A press past 0.64s
			# would find the chain back in HELD and the third press would open the
			# loop at 左甩 again instead of playing 直抛.
			#
			# Fired through `_chain_beat` rather than at the exact frame, because
			# that recovery window is 0.20–0.22s wide and the event clock is wall
			# time: see the note on the helper. The cadence is unchanged; only the
			# coin-flip on which frame the scheduler wakes up on is gone.
			"events": [
				[SETTLE + 0.45, _chain_beat.bind(&"light", &"ch_sweep")],
				[SETTLE + 0.97, _chain_beat.bind(&"light", &"ch_return")],
				[SETTLE + 1.49, _chain_beat.bind(&"light", &"ch_throw")],
			],
			"duration": SETTLE + 3.6,
		},
		# -------------------------- 3b · 亮链三拍 · 全局（三拍是不是三拍）
		{
			"name": "缚星链 · 亮链三拍 · 全局",
			"note": "同一句话，从外面看一遍。第一人称那一拍回答的是「玩家看不看得懂」，这一拍回答的是「是不是真的三拍」。左甩：一条又宽又重的横弧，链头从右手侧绕过身前扫到左边。快右左：不回收链头，带着上一拍没停下来的惯性先往右再往左，两次转向都发生在链头还在飞的时候，所以比第一下更快更连。直抛：忽然换轴 —— 不再是横的弧，而是沿准星的一条前向长线，一路走到九米多，绳在最后 0.05 秒里从松变直。三拍之间链头一次都没有停下来；也不该有任何一拍回到待机。",
			"fov": 62.0,
			"cam": loop,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, stand_z),
			"events": [
				[SETTLE + 0.45, _chain_beat.bind(&"light", &"ch_sweep")],
				[SETTLE + 0.97, _chain_beat.bind(&"light", &"ch_return")],
				[SETTLE + 1.49, _chain_beat.bind(&"light", &"ch_throw")],
			],
			"duration": SETTLE + 3.6,
		},
		# ---------------------------------------------------------------- 4 · 蓄
		{
			"name": "缚星链 · 蓄",
			"note": "按住重击，链头开始绕圈。转速、半径、链条被拉直的程度、手柄的阻力 —— 一起涨。蓄得越久甩出去越重，所以「不想乱甩」这句话在这一拍里第一次成立。",
			"fov": 54.0,
			"cam": wider,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, stand_z),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"heavy", &"ch_orbit")],
				# Released with a margin: the orbit throws ITSELF at orbit_max_hold
				# (1.30s) and a take may not depend on the render frame rate.
				[SETTLE + 1.08, _chain_release_expect.bind(&"ch_launch")],
			],
			"duration": SETTLE + 3.6,
		},
		# ---------------------------------------------------------------- 5 · 拉·轻
		{
			"name": "缚星链 · 拉 · 轻",
			"note": "钩住轻的东西，是它被甩过来。同一个输入、同一根链，换的只是链头上挂了什么 —— 重量表是一条物理，不是一行 if。",
			"fov": 56.0,
			"fp": false,
			"cam": tight,
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_LIGHT])
				_stand_in_lab(0.0, stand_z)
				_chain_target(ElementLibrary.WEIGHT_LIGHT, 3.6),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
			],
			"duration": SETTLE + 3.6,
		},
		# ---------------------------------------------------------------- 6 · 拉·中
		{
			"name": "缚星链 · 拉 · 中",
			"note": "中等重量：两边都被拽。这一拍存在的理由是它必须和另外两拍看起来都不一样 —— 轻的是对方飞过来，重的是你被拖过去，中等的是两个身体一起让一步。",
			"fov": 56.0,
			"fp": false,
			"cam": tight,
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_MEDIUM])
				_stand_in_lab(0.0, stand_z)
				_chain_target(ElementLibrary.WEIGHT_MEDIUM, 3.6),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
			],
			"duration": SETTLE + 3.6,
		},
		# ---------------------------------------------------------------- 7 · 拉·重
		{
			"name": "缚星链 · 拉 · 重",
			"note": "钩住比自己重的东西，被拉过去的是你 —— 一次一下、看得见地把你拽近，不是一次吸附。重型敌人不是受害者，是锚。",
			"fov": 56.0,
			"fp": false,
			"cam": tight,
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_HEAVY])
				_stand_in_lab(0.0, stand_z)
				_chain_target(ElementLibrary.WEIGHT_HEAVY, 3.6),
			# NO THIRD PRESS, AND IT IS NOT AN OMISSION.
			#
			# This take used to end with `heavy → 地砸` at +2.30s, and the renderer
			# logged the mismatch itself:
			#     !! heavy played ch_orbit, but this take claims ch_ground_slam
			# The first guess was a mistimed press. It is not. Replayed on the
			# deterministic clock, 缚's bind lasts its own bound_time (0.40s on a
			# heavy body), and when it lapses the chain emits 缚 · 松脱 and REELS
			# IN — so by +2.30s the director is back in HELD with `is_hooked()`
			# false and `heavy` means "start a spin", which is what it did.
			#
			# The deeper reading is the one that matters: 缚 IS the pull. The
			# caption on this take is a sentence about the WEIGHT TABLE, and the
			# weight table is applied by 缚, not by 地砸 — 地砸 is §23's exit from
			# a bind you are still holding, which is a different beat and belongs
			# to the tour take that is about exits. What the camera has to see
			# here is: 咬 → 绷 → 拉 (five diminishing yanks, player hauled 0.66m,
			# target moved 0.00m) → 松脱 → 回抽. All five of those beats are in
			# these two presses. A third one would only have added a claim the
			# take does not make.
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
			],
			"duration": SETTLE + 3.4,
		},
		# ---------------------------------------------------------------- 8 · 锚
		{
			"name": "缚星链 · 锚",
			"note": "钩住石柱，和钩住一个重型敌人是同一件事：柱子不动，动的是你。没有一行专门为锚写的代码 —— 这就是重量表是物理而不是特例的意思。",
			"fov": 56.0,
			"fp": false,
			"cam": tight,
			"setup": func() -> void:
				_enter_lab([])
				# The pillar is scenery at a fixed spot, so this take cannot walk
				# deeper — it faces back down the lab instead, which also turns the
				# haul into a move toward the lens.
				_stand_in_lab(ChainLab.ANCHOR_POSITION.x, -30.0, 180.0),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
			],
			"duration": SETTLE + 3.8,
		},
		# ---------------------------------------------------------------- 9 · 撞
		{
			"name": "缚星链 · 撞",
			"note": "对着墙扔出去，什么都没钩到。链头不会穿过石面，撞上就丢掉大部分势 —— 空间对这条链是有代价的，这就是它为什么是链而不是一根很长的剑。",
			"fov": 56.0,
			"cam": wider,
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, -38.0),
			"events": [
				[SETTLE + 0.10, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
			],
			"duration": SETTLE + 2.6,
		},
	]


# A STAND-IN BODY FOR THE OUTSIDE SHOTS, built from the player's own hurtbox.
#
# The player has no mesh: in first person the hand and the weapon are the only
# things drawn, which is correct for playing and useless for filming. An outside
# take of a hook then shows a lone enemy and no actor — and four of this weapon's
# claims are ABOUT the player moving. 曳 moves both bodies by the weight table, the
# anchor hauls the player to the pillar, a wall stops the head and costs the spin,
# and a heavy target is not a victim but an anchor. None of those can be seen if the
# thing being moved is invisible.
#
# Size and placement come from the hurtbox rather than from a guess, so this cannot
# drift away from the body it stands for. Recording-only: the renderer adds it, the
# game never does.
func _build_review_body() -> void:
	review_body = Node3D.new()
	review_body.name = "ReviewBody"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.38, 0.49)
	material.roughness = 0.68
	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = _hurtbox_radius()
	capsule.height = _hurtbox_height()
	torso.mesh = capsule
	torso.material_override = material
	review_body.add_child(torso)
	# A wedge at the chest so the FACING reads. Every one of these takes is about
	# which way something got pulled, and a bare capsule has no front.
	var nose := MeshInstance3D.new()
	var wedge := BoxMesh.new()
	wedge.size = Vector3(0.16, 0.16, 0.34)
	nose.mesh = wedge
	nose.material_override = material
	nose.position = Vector3(0.0, 0.35, -(capsule.radius + 0.15))
	review_body.add_child(nose)
	review_body.visible = false
	sandbox.add_child(review_body)


func _hurtbox_shape() -> CapsuleShape3D:
	var node := player.get_node_or_null("Hurtbox/CollisionShape3D") as CollisionShape3D
	return node.shape as CapsuleShape3D if node != null else null


func _hurtbox_radius() -> float:
	var shape := _hurtbox_shape()
	return shape.radius if shape != null else 0.34


func _hurtbox_height() -> float:
	var shape := _hurtbox_shape()
	return shape.height if shape != null else 1.7


func _update_review_body() -> void:
	if review_body == null:
		return
	review_body.visible = not seg_fp
	if seg_fp:
		return
	var node := player.get_node_or_null("Hurtbox/CollisionShape3D") as CollisionShape3D
	if node == null:
		return
	review_body.global_position = node.global_position
	review_body.global_rotation = Vector3(0.0, player.global_rotation.y, 0.0)


func _build_review_camera() -> void:
	review_camera = Camera3D.new()
	review_camera.name = "ReviewCamera"
	review_camera.fov = seg_fov
	review_camera.near = 0.05
	review_camera.far = 120.0
	sandbox.add_child(review_camera)
	_update_camera()
	review_camera.make_current()


# Everything in every take happens in front of the player, so one framing rule
# covers the whole tour: sit behind and to the side, and keep the player's own
# position inside the shot. The blade is parented to the player's camera rig, so
# a camera that looks past the player is a camera with no sword in it.
#
# The lens is tight on purpose. At a wide angle a 1.8m placeholder cone 5m away
# is a thumbnail, and the blade — the thing every claim is about — disappears.
func _update_camera() -> void:
	if review_camera == null:
		return
	if seg_fp:
		# Nothing to place and nothing to aim. The player's rig IS the camera, and
		# the chain's handle is parented into it — a review camera cannot show a
		# weapon that lives in camera space, only a smaller version of it.
		if player_camera != null and not player_camera.is_current():
			player_camera.make_current()
		return
	review_camera.fov = seg_fov
	var basis := player.global_transform.basis
	var forward := -basis.z
	# Per-take override, because one framing rule cannot cover both an 80cm katana
	# and a 4.6m chain. Defaults reproduce the sword tour exactly.
	var side := float(seg_cam.get("side", 2.2))
	var back := float(seg_cam.get("back", 3.0))
	var up := float(seg_cam.get("up", 3.8))
	var aim := float(seg_cam.get("aim", 1.0))
	# Aim between the player and the enemy, not at the enemy: the blade is drawn at
	# the player's own eye, so a camera that centres the enemy puts the sword at the
	# bottom edge. The chain takes aim further out so the head stays in frame.
	var focus := player.global_position + forward * aim + Vector3(0.0, 0.15, 0.0)
	# Steep three-quarter, high and off the shoulder. Sitting level behind the
	# player looks *along* the blade, and a blade pointing away from the camera is
	# a blade pointing away from the camera — an 80cm sword renders as a sliver.
	# From above and to the side the swing has to cross the frame to happen.
	#
	# It also has to stay near the centre line: ArenaDressing flanks the arena with
	# pillars from |x| 2.7 outward and keeps the middle deliberately clear, so a
	# camera parked at x=3 films the inside of a pillar. That was the first take.
	var eye := (
		player.global_position
		+ basis.x * side
		- forward * back
		+ Vector3(0.0, up, 0.0)
	)
	review_camera.global_position = eye
	review_camera.look_at(focus, Vector3.UP)
	# The sandbox re-asserts the player's camera once during startup, so claim
	# the viewport back only if it was taken.
	if not review_camera.is_current():
		review_camera.make_current()


# ------------------------------------------------------------ movement tour
# PART M. Every chapter is shot FIRST PERSON, because the claims are about what
# travelling FEELS like -- the gait in the camera, the blade being carried, the
# pitch of a turn -- and none of those exist on the outside of the body. What an
# outside view would add, "the player moved", is already proven by the numbers in
# tests/movement_metrics.gd.
#
# Chapters 1-3 exist because Walk did not. Keyboard input is all-or-nothing, so
# the game had one pace that it called walking; the third pace is a held modifier,
# which means a gamepad stick still gets the whole continuum for free.
func _build_movement_segments() -> void:
	segments = [
		{
			"name": "移动 · 走 WALK",
			"note": "按住 Ctrl。这是本轮才真正存在的第三档速度。看：步频最慢，相机起伏最轻，剑几乎不动 —— 不是把小跑调慢，是另一种走法。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(0.0),
			"events": [
				[SETTLE, _lane_hold.bind([&"walk", &"move_forward"])],
				[SETTLE + 2.4, _lane_release.bind([&"walk", &"move_forward"])],
			],
			"duration": SETTLE + 3.2,
		},
		{
			"name": "移动 · 小跑 JOG",
			"note": "默认速度。§17 要它「立刻进入」—— 实测 0.250s 到速，不是漂上去的。和上一章对比：步频变快，相机起伏变明显，剑开始跟不住身体。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(0.0),
			"events": [
				[SETTLE, _lane_hold.bind([&"move_forward"])],
				[SETTLE + 2.4, _lane_release.bind([&"move_forward"])],
			],
			"duration": SETTLE + 3.2,
		},
		{
			"name": "移动 · 冲刺 SPRINT",
			"note": "§22 FOV 推开、步频更高、剑换成另一种持握姿态；§17 要 0.2–0.45s 的建立感（实测 0.367s），所以起步那一瞬不是满速。松手时（§23）剑回位的耗时是进入的 3.05 倍，不是瞬间弹回。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(0.0),
			"events": [
				[SETTLE, _lane_hold.bind([&"sprint", &"move_forward"])],
				[SETTLE + 2.6, _lane_release.bind([&"sprint", &"move_forward"])],
			],
			"duration": SETTLE + 3.6,
		},
		{
			"name": "移动 · 松键与停 SETTLE",
			"note": "§18 不能瞬停，也不能滑三米。实测冲刺松键滑行 1.16m / 0.317s（改之前 2.22m）。看身体收住那一下 —— 是「先卸掉再收住」，不是断电。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(0.0),
			"events": [
				[SETTLE, _lane_hold.bind([&"sprint", &"move_forward"])],
				[SETTLE + 1.3, _lane_release.bind([&"sprint", &"move_forward"])],
			],
			"duration": SETTLE + 2.6,
		},
		{
			"name": "移动 · 180° 回头 TURN",
			"note": "§19 不能瞬间反向，也不能像船掉头。实测整段 0.533s，其中「原有动量耗尽」占 0.183s（34%）—— 要看的就是这 34%：先把向前的速度花掉，再朝反方向加速。删掉制动的话总时长依旧好看，但这段会变成瞬时翻转。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(0.0),
			"events": [
				[SETTLE, _lane_hold.bind([&"sprint", &"move_forward"])],
				[SETTLE + 1.2, _lane_release.bind([&"move_forward"])],
				[SETTLE + 1.22, _lane_hold.bind([&"move_back"])],
				[SETTLE + 2.2, _lane_release.bind([&"move_back", &"sprint"])],
			],
			"duration": SETTLE + 3.0,
		},
		{
			"name": "移动 · 跳 JUMP & LAND",
			"note": "§24 起跳压缩 / 滞空 / 落地压缩。§25 落地按落下速度分三档并传导到相机与剑；但小跳不该震屏 —— 低于 3.0 m/s 的下落完全不发声，这两跳都是轻档。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(0.0),
			"events": [
				[SETTLE, _jump_press],
				[SETTLE + 0.06, _jump_release],
				[SETTLE + 1.3, _jump_press],
				[SETTLE + 1.36, _jump_release],
			],
			"duration": SETTLE + 2.6,
		},
		{
			"name": "移动 · 重落地 HEAVY LAND",
			"note": "从高处落下。三档实测 light 5.1 / medium 8.4 / heavy 12.4 m/s：相机与剑都按档位反应，而剑是弹簧（先沉过头再回来），不是一次性位移。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(-2.0, 5.2),
			"events": [],
			"duration": SETTLE + 2.6,
		},
		{
			"name": "移动 · 前闪避 DODGE FWD",
			"note": "PART I 要的是「一阵爆发」，不是瞬移 1.8m。实测 2.00m / 0.367s，第 2 帧速度远低于峰值 —— 有加速段、峰值段、收尾段，不是一帧到位。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(0.0),
			"events": [
				[SETTLE, _dodge],
				[SETTLE + 1.4, _dodge],
			],
			"duration": SETTLE + 2.6,
		},
		{
			"name": "移动 · 侧闪避 DODGE SIDE",
			"note": "同一次侧移，看剑的横向拖尾：身体先走，剑被留在后面再追上来。§21 的 weapon lag 按身体本地速度算，所以侧移与前后的拖曳方向不同。",
			"fp": true, "fov": 68.0, "pitch": -1.0,
			"setup": func() -> void: _lane_start(0.0),
			"events": [
				[SETTLE, _lane_hold.bind([&"move_right"])],
				[SETTLE + 0.2, _dodge],
				[SETTLE + 1.6, _lane_release.bind([&"move_right"])],
				[SETTLE + 1.62, _lane_hold.bind([&"move_left"])],
				[SETTLE + 1.8, _dodge],
				[SETTLE + 2.4, _lane_release.bind([&"move_left"])],
			],
			"duration": SETTLE + 3.2,
		},
		{
			"name": "移动 · 上坡 SLOPE UP",
			"note": "§26 上坡要付出代价。同一段坡、同样按住冲刺：上坡 5.51 m/s 对平地 6.90 m/s（−20%）。读数取自脚下实际表面法线而非高度图，关卡把坡放在哪都成立。",
			"fp": true, "fov": 68.0, "pitch": 6.0,
			"setup": func() -> void: _enter_ramp(0.2, true),
			"events": [
				[SETTLE + 0.2, _lane_hold.bind([&"sprint", &"move_forward"])],
				[SETTLE + 1.3, _lane_release.bind([&"sprint", &"move_forward"])],
			],
			"duration": SETTLE + 2.2,
		},
		{
			"name": "移动 · 下坡 SLOPE DOWN",
			"note": "§26 下坡稍微保留动量（+7%，7.39 m/s）。注意这不是重力推着走 —— 刻意没做沿坡重力求解器，否则它会立刻开始和流派突进、链拽拉互相打架。",
			"fp": true, "fov": 68.0, "pitch": -6.0,
			"setup": func() -> void: _enter_ramp(0.2, false),
			"events": [
				[SETTLE + 0.2, _lane_hold.bind([&"sprint", &"move_forward"])],
				[SETTLE + 1.3, _lane_release.bind([&"sprint", &"move_forward"])],
			],
			"duration": SETTLE + 2.2,
		},
	]


# Every take starts from NOTHING HELD. A key left down by the previous chapter
# silently changes this one, and it is worst in the pace chapters: a surviving
# `sprint` turns the walk chapter into a sprint, and the only symptom is a caption
# that no longer matches what is on screen.
func _lane_start(offset_x: float, drop_height := 0.0) -> void:
	_release_movement()
	Input.action_release(&"walk")
	Input.action_release(&"jump")
	var start := lane.start_position()
	player.global_position = Vector3(start.x + offset_x, MovementLane.DECK_Y + 1.4 + drop_height, start.z)
	player.velocity = Vector3.ZERO
	player.look_at_from_position(
		player.global_position,
		player.global_position + MovementLane.RUN_DIRECTION * 4.0,
		Vector3.UP
	)
	look_pivot.rotation.x = deg_to_rad(seg_pitch)


# The lane's own ramp: the one slope in the level, and the SAME slope for both
# takes, so the only difference between the two chapters is which way it is faced.
func _enter_ramp(along: float, uphill: bool) -> void:
	_lane_start(0.0)
	var bottom := MovementLane.CENTER.x - MovementLane.LENGTH * 0.5 - MovementLane.RAMP_RUN
	var rise := MovementLane.DECK_Y / MovementLane.RAMP_RUN
	var run := MovementLane.RAMP_RUN * (along if uphill else 1.0 - along)
	player.global_position = Vector3(bottom + run, run * rise + 1.2, MovementLane.CENTER.z)
	player.velocity = Vector3.ZERO
	# The ramp only rises toward +x, so facing +x is the climb and facing -x is the
	# descent. Same surface, opposite normal.
	player.rotation = Vector3(0.0, 0.0 if uphill else PI, 0.0)
	look_pivot.rotation.x = deg_to_rad(seg_pitch)


func _lane_hold(actions: Array) -> void:
	for a in actions:
		_hold(a, true)


func _lane_release(actions: Array) -> void:
	for a in actions:
		_hold(a, false)


# Jump is EDGE-TRIGGERED, so it is pressed on one event and lifted on the next.
# Pressing and releasing inside a single event is a coin flip on whether a physics
# tick ever observes `is_action_just_pressed`, which reads as a broken take.
func _jump_press() -> void:
	Input.action_press(&"jump")


func _jump_release() -> void:
	Input.action_release(&"jump")


func _dodge() -> void:
	combat.request(&"dodge")


func _run_segment(segment: Dictionary) -> void:
	seg_name = String(segment.get("name", ""))
	seg_note = String(segment.get("note", ""))
	seg_fov = float(segment.get("fov", 38.0))
	seg_cam = segment.get("cam", {})
	# First person unless the take asks for the outside view. The outside view is
	# right for the claims that are about SHAPE (one sweep through two targets, the
	# pillar hauling the player in); first person is right for everything about
	# WEIGHT and about the camera itself.
	seg_fp = bool(segment.get("fp", cam_mode == "fp"))
	seg_pitch = float(segment.get("pitch", FP_PITCH if seg_fp else -2.3))
	if foreground_layer != null:
		foreground_layer.visible = seg_fp
	seg_spells = segment.get("spells", [])
	seg_metrics.clear()
	flow_peak = 0.0
	parry_landed = false
	_reset_motion_metrics()
	var setup: Callable = segment["setup"]
	setup.call()
	_seg_t = 0.0
	# Taken AFTER the take's own setup, so a `chain.reset()` inside it cannot shift the
	# baseline and turn one real hit into two reported ones.
	if chain != null:
		seg_hits_before = chain.hits_landed
		seg_walls_before = chain.wall_hits
	_stills = []
	for rule in segment.get("stills", []):
		_stills.append({"tag": String(rule[0]), "when": rule[1], "done": false})
	await _frame()
	await _frame()
	_update_camera()
	# A framing guard, not a debug print. ArenaDressing stands a 34m wide wall at
	# z = -17 (no collision) between the arena and the chain lab, so a take whose
	# subject is in the lab but whose camera has drifted back past it films the
	# inside of a placeholder box for four seconds and reports a clean summary.
	# The symptom is an empty take, so it is worth one line to catch it here.
	if not seg_fp and player.global_position.z < LAB_ENTRY_Z and review_camera.global_position.z > ARENA_WALL_Z:
		print("    !! %s: subject is in the lab (z=%.1f) but the review camera is at z=%.1f, \
behind the arena far wall — this take will render the wall, not the chain"
			% [seg_name, player.global_position.z, review_camera.global_position.z])
	combat.perfect_guard_count = 0
	if not seg_spells.is_empty() and not seg_spells.has(combat.spell_id):
		print("    !! %s declared %s but %s is armed" % [seg_name, seg_spells, combat.spell_id])

	var events: Array = segment.get("events", [])
	var duration := float(segment.get("duration", 4.0))
	var begin := Time.get_ticks_msec()
	var next_event := 0
	var prev_t := 0.0
	_beat_action = &""
	print("--- %s" % seg_name)

	while true:
		var t := float(Time.get_ticks_msec() - begin) / 1000.0
		_seg_t = t
		while next_event < events.size() and t >= float(events[next_event][0]):
			var action: Callable = events[next_event][1]
			action.call()
			next_event += 1
		_pump_beat()
		await _frame()
		_note_parry()
		flow_peak = maxf(flow_peak, combat.flow_ratio())
		_sample_motion()
		_update_turn(t, prev_t)
		prev_t = t
		_update_camera()
		_update_review_body()
		_update_overlay(t)
		_save()
		if t >= duration and next_event >= events.size() and _beat_action.is_empty():
			break
	_report_missing_stills()
	# §SELF-REPORT — WHAT THE WEAPON ACTUALLY DID IN THIS TAKE.
	#
	# The chain takes are captioned "A1 命中敌人" and "A1 撞墙", and a caption is a
	# CLAIM. `capture_chain_audio.gd` learned this the hard way for sound: a take that
	# stages a beat and gets refused still renders a beautiful and entirely fictional
	# clip. The chain counts its own hits and wall bites, so the take can be ASKED
	# rather than trusted — the same discipline as `perfect_guards` on the sword takes,
	# and the reason this is printed whether or not the number is flattering.
	if chain != null:
		seg_metrics.append("chain hits +%d  walls +%d"
			% [chain.hits_landed - seg_hits_before, chain.wall_hits - seg_walls_before])
		# Opt-in, so the sword and movement tours keep exactly the summary line they
		# had. A take that printed seven zeroes would be noise; a MOTION take that
		# printed none would be an unbacked claim.
		if bool(segment.get("motion", false)):
			seg_metrics.append(_motion_metric_line())
	print("    %s  frames=%d  perfect_guards=%d%s"
		% [
			seg_name,
			frame_index,
			combat.perfect_guard_count,
			("  |  " + "  ".join(seg_metrics)) if not seg_metrics.is_empty() else "",
		])
	_release_movement()


# --- driving the systems ----------------------------------------------------

func _req(action: StringName) -> void:
	combat.request(action)


# Arm a spell through the SAME call the player's wheel uses. The renderer used to
# call select_school() and hope, which is how two takes ended up captioned as
# showing a burning field while actually casting the primary.
func _spell(spell_id: StringName) -> void:
	if not combat.select_spell(spell_id):
		print("    !! could not arm %s" % spell_id)


# Movement for the takes that are about moving. The player reads input actions,
# so pressing one here is the same path a key would take.
func _hold(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_movement() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


# Movement takes happen on their own stage. The arena cannot host a straight run:
# the dummy stands on the line the player walks, so the run turns into a shove
# about two metres in and the take measures the enemy's pushbox instead of the
# player's speed.
func _enter_lane() -> void:
	if lane == null:
		return
	var start := lane.start_position()
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.look_at_from_position(start, start + MovementLane.RUN_DIRECTION * 4.0, Vector3.UP)
	look_pivot.rotation.x = -0.05
	# The enemy is parked off the lane rather than left standing in the shot.
	dummy.global_position = Vector3(0.0, 0.6, -9.0)


func _note_run_origin() -> void:
	run_origin = player.global_position


func _metric_distance(label: String) -> void:
	seg_metrics.append("%s 位移=%.2fm" % [label, player.global_position.distance_to(run_origin)])


# 势 peaks are the honest way to compare a standing exchange with a moving one:
# a snapshot has to be timed to the landing frame, a peak does not.
func _metric_reset() -> void:
	flow_peak = 0.0


func _metric(label: String) -> void:
	seg_metrics.append("%s peak 势=%.0f%%" % [label, flow_peak * 100.0])
	flow_peak = 0.0


func _trigger_skill(index: int) -> void:
	combat.trigger_skill(index)


func _dummy_state(label: StringName) -> void:
	dummy.call("apply_debug_state", label)


func _guard_up() -> void:
	combat.finish_action()
	combat.set_state(CombatController.State.BLOCK)


func _enemy_hit_on() -> void:
	var hb: CombatHitbox = dummy.get_node("AttackHitbox")
	hb.set_active(true)


func _enemy_hit_off() -> void:
	var hb: CombatHitbox = dummy.get_node("AttackHitbox")
	hb.set_active(false)


func _note_parry() -> void:
	if not parry_landed and combat.perfect_guard_count > 0:
		parry_landed = true


func _clean_arena(style_id: StringName) -> void:
	combat.finish_action()
	combat.set_state(CombatController.State.IDLE)
	combat.set_style(style_id, true)
	combat.reset_skill_cooldowns()
	combat.reset_flow()
	combat.iaido_ready_at = 0.0
	combat.ultimate_ready_at = 0.0
	combat.perfect_guard_count = 0
	# Back to the controller's own default school, so a take that arms nothing
	# starts from a known spell rather than from whatever the last take left.
	combat.select_school(&"frost")
	# Movement held by the previous take would keep walking through this one.
	_release_movement()
	player.set("stamina", 100.0)
	player.set("health", 100.0)
	dummy.call("reset_dummy")
	dummy.set("attack_cooldown", 9999.0)
	_clear_fields()
	# The two movable crates start 3m in front of the player, which is exactly
	# where the review camera looks. They are parked out of the arena for every
	# take that is not about wind; the wind takes put them back on purpose.
	_park_props()


func _park_props() -> void:
	if props == null:
		return
	# Two distinct spots AND frozen. Stacked at one position the two rigid bodies
	# resolve their overlap by launching each other back across the arena, which
	# is how a "parked" crate ends up filling half the shot.
	var spots := [Vector3(12.0, 0.45, 12.0), Vector3(13.4, 0.45, 12.6)]
	for i in props.light_objects.size():
		var body := props.light_objects[i]
		if not is_instance_valid(body):
			continue
		body.freeze = true
		body.global_position = spots[i % spots.size()]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


# The wind takes need the crates back where the player can actually throw them.
func _release_props() -> void:
	if props == null:
		return
	for body in props.light_objects:
		if is_instance_valid(body):
			body.freeze = false
	props.reset()


func _clear_fields() -> void:
	for node in player.get_parent().get_children():
		if node is ElementField:
			node.queue_free()


# --- the chain ---------------------------------------------------------------

# 缚星链 takes happen in the CHAIN LAB, not the arena. A chain needs a 4.6m throw,
# a wall for the throw to end on, and three weights standing one throw apart —
# none of which the arena has, and all of which are the weapon's actual argument.
# The arena's own dummy is on the walking line, so it is parked out of the shot.
func _enter_lab(weights: Array) -> void:
	weapon.equip(WeaponSlot.CHAIN)
	chain.reset()
	_park_props()
	dummy.global_position = Vector3(60.0, 0.0, 0.0)
	if lab == null:
		return
	lab.reset()
	for target in lab.targets:
		if not is_instance_valid(target):
			continue
		# No enemy AI in a chain take: a target that walks toward the player
		# changes the distance the take is about.
		target.set_process(false)
		target.set("attack_cooldown", 9999.0)
		if not weights.has(target.call("weight_class")):
			target.global_position = Vector3(60.0, 0.0, 0.0)


# The lab deck's surface is y = 0 and the player's body centre settles 0.9 above it,
# which is not the arena's number. Reusing the arena's height here would bury the
# player up to the knee in the deck.
func _stand_in_lab(x: float, z: float, turn_degrees := 0.0) -> void:
	player.global_position = Vector3(x, 0.9, z)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0.0, deg_to_rad(turn_degrees), 0.0)
	# In first person this is the whole aim of the take. The eye sits at 1.9m and the
	# chain swings at about 1.1m, so a level look puts every sweep in the bottom
	# fifth of the frame; the takes tilt down to where the weapon actually is.
	look_pivot.rotation.x = deg_to_rad(seg_pitch)


# Put one weight where the take needs it, measured from the player's own facing, so
# a take can pick its distance without teleporting the player again.
func _chain_target(weight: StringName, distance: float, lateral := 0.0) -> Node3D:
	if lab == null:
		return null
	var target := lab.target_for(weight)
	if target == null:
		print("    !! the lab has no %s target" % String(weight))
		return null
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	target.global_position = (
		player.global_position + forward * distance + right * lateral + Vector3(0.0, -0.9, 0.0)
	)
	target.global_position.y = 0.0
	target.rotation = Vector3.ZERO
	target.call("reset_dummy")
	target.set("attack_cooldown", 9999.0)
	return target


# The chain is driven through the same call the player's own input makes. Asking the
# weapon directly is what the developer panel does, so a take cannot show a
# technique the player has no button for — and a refusal is printed rather than
# silently producing a caption about something that never happened.
func _chain_req(action: StringName) -> void:
	_request_chain(action, &"")


# THE CAPTION AND THE ANIMATION HAVE TO BE THE SAME CLAIM.
#
# `request()` returning true only means "SOMETHING happened", which is not the same as
# "the thing this take is about happened". The heavy bind take fired its exit 0.15s
# outside 缚's 0.40s window; the request was ACCEPTED and the take rendered happily —
# it just played 蓄势回旋 → 甩星 instead of 地砸, while the caption on screen said 地砸.
# Nothing in the log disagreed, because nothing was asked.
#
# So any input whose meaning depends on a WINDOW (taut, bound, hooked) has to declare
# which technique it meant, and the renderer checks it against what actually started.
func _chain_req_expect(action: StringName, expect: StringName) -> void:
	_request_chain(action, expect)


func _request_chain(action: StringName, expect: StringName) -> void:
	if not chain.request(action):
		print("    !! %s refused at %.2fs in %s"
			% [String(action), chain.state_time, seg_name])
		return
	var played := _played_move()
	if expect != &"" and played != expect:
		print("    !! %s played %s, but this take claims %s  (%s)"
			% [String(action), String(played), String(expect), seg_name])


# §PART O — a beat that was REFUSED is retried, because a take may not silently drop
# part of its own claim.
#
# The loop's three presses are authored 0.52s apart and that cadence is the data:
# 左甩 runs 0.64s and 快右左 0.56s, so each press is meant to land inside the previous
# beat's RECOVERY rather than after the beat has ended. But the renderer's event clock
# is WALL time (Time.get_ticks_msec) while the chain's is GAME time, and a recovery
# window is only ~0.2s wide — one slow frame and the press arrives a frame or two after
# the move has ended in RETRACTING, where `_can_act()` is false and the request is
# refused. The observed failure was exactly this:
#
#     !! light refused at 0.00s in 缚星链 · 亮链三拍 —— 左甩 / 快右左 / 直抛
#
# and the take then rendered 左甩 / 快右左 and NO 直抛 — a three-beat sentence with two
# beats in it, which is precisely the thing the take exists to disprove. It happened in
# one of two renders of the same build, so it is a frame-rate coin-flip and not a
# property of the moveset.
#
# So a beat scheduled this way is offered on its scheduled frame and then offered again
# every frame until the chain takes it. When the timing works — the normal case — the
# first offer lands exactly as before and nothing about the cadence changes; this only
# removes the dependence on which frame the scheduler happened to wake up on.
func _chain_beat(action: StringName, expect: StringName) -> void:
	if not _beat_action.is_empty():
		print("    !! %s was still owed %s when %s was scheduled in %s"
			% [String(_beat_action), String(_beat_expect), String(action), seg_name])
	_beat_action = action
	_beat_expect = expect
	_beat_frames = 0


func _pump_beat() -> void:
	if _beat_action.is_empty():
		return
	_beat_frames += 1
	if chain.request(_beat_action):
		var played := _played_move()
		if _beat_expect != &"" and played != _beat_expect:
			print("    !! %s played %s, but this take claims %s  (%s)"
				% [String(_beat_action), String(played), String(_beat_expect), seg_name])
			print("       why: state=%s index=%d idle=%.2f radius=%.2f taut=%s"
				% [str(chain.state), int(chain.get("_chain_index")),
					float(chain.get("_idle_time")), float(chain.radius),
					str(chain.is_taut())])
		_beat_action = &""
		return
	if _beat_frames > BEAT_PATIENCE_FRAMES:
		print("    !! %s was never accepted after %d frames in %s"
			% [String(_beat_action), _beat_frames, seg_name])
		_beat_action = &""


func _played_move() -> StringName:
	return chain.active_move.id if chain.active_move != null else &""


func _chain_release() -> void:
	if not chain.release_heavy():
		print("    !! 释 refused in %s" % seg_name)
		return


# 释 is only reachable from a spin, and a spin only ever releases into the throw — so
# this one expect is not a window check, it is the take's whole claim ("松手甩出去").
func _chain_release_expect(expect: StringName) -> void:
	if not chain.release_heavy():
		print("    !! 释 refused in %s" % seg_name)
		return
	var played := _played_move()
	if played != expect:
		print("    !! 释 played %s, but this take claims %s  (%s)"
			% [String(played), String(expect), seg_name])


func _place(player_pos: Vector3, distance: float) -> void:
	_move_pair(player_pos, distance)


# Aim at the target's y raised to the player's own, for the same reason the Lab
# does: looking down at a body below eye level tilts the whole rig and the shot
# reads as a stumble.
func _move_pair(player_pos: Vector3, distance: float) -> void:
	player.global_position = player_pos
	var dummy_pos := player_pos + Vector3(0.0, -DUMMY_DROP, -distance)
	dummy.global_position = dummy_pos
	player.look_at_from_position(
		player_pos, Vector3(dummy_pos.x, player_pos.y, dummy_pos.z), Vector3.UP
	)
	look_pivot.rotation.x = -0.06
	# The dummy's AttackHitbox sits at local +Z 1.3, so this thing attacks along
	# its own +Z. look_at would point -Z at the player and swing its hitbox away
	# from them, which is why every parry take silently produced no perfect guard.
	# Aim it at the mirror point instead.
	dummy.look_at_from_position(
		dummy_pos,
		Vector3(
			dummy_pos.x * 2.0 - player_pos.x,
			dummy_pos.y,
			dummy_pos.z * 2.0 - player_pos.z
		),
		Vector3.UP
	)
	combat.measure_range = combat.measure_distance_now()
	combat.measure_state = combat.measure_label()


# --- capture ----------------------------------------------------------------

# Two frames: one to let physics land, one to land the drawn pose.
func _frame() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save() -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport returned no image at frame %d" % frame_index)
		return
	var err := image.save_png("%s/frame_%04d.png" % [output_dir, frame_index])
	if err != OK:
		push_error("save_png failed (%d) at frame %d" % [err, frame_index])
	frame_index += 1
	_pump_stills()
	if frame_index % 60 == 0:
		print("    frame %d" % frame_index)


# ONE FRAME, FILED UNDER A NAME — for the stills the brief asks to be handed over
# next to the clip (chain_v4_idle / _sweep_peak / _wall_bite / _tension).
#
# The rule is a PREDICATE over the weapon's own state, not a timestamp, and that is
# the whole design of it. This renderer runs in real time (see the file header), so
# an event at "t = 1.09s" lands on whichever frame the machine happened to produce
# nearest that instant — and 左甩 crosses its own front in 0.26s, which at 20fps is
# five frames for the entire second half of the arc. A still picked by clock would
# be a photograph of the machine's frame rate, not of the technique. Asking
# `chain.radius >= 3.30` instead photographs the moment the head is actually out
# there.
func _pump_stills() -> void:
	for rule in _stills:
		if rule["done"]:
			continue
		var when: Callable = rule["when"]
		if not when.call():
			continue
		rule["done"] = true
		var tag: String = rule["tag"]
		var from := "%s/frame_%04d.png" % [output_dir, frame_index - 1]
		var to := "%s/still_%s.png" % [output_dir, tag]
		var err := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)
		)
		if err == OK:
			# WHERE THE WEAPON ACTUALLY WAS, alongside the frame number. A still's tag
			# names a beat and the frame number says when it happened, but neither says
			# WHERE — and "the trident bit the wall" is a claim about a position that
			# `chain_v4_slice` already proves as a zero-drift number and the trained eye
			# then has to find in the picture. Printing the head's own height on the
			# still's line is what turns "the marking band looks slightly low" from an
			# impression into a comparison.
			var head_at := (
				chain.chain_visual.drawn_head()
				if chain.chain_visual != null else Vector3.ZERO
			)
			# ...and HOW MUCH FISTFUL IS STILL IN THE HAND, which is §11's claim and
			# the one thing about this still that cannot be read off the picture: the
			# bundle and the thrown chain are the same material at the same distance,
			# so "the hand is emptier here than in take A" needs the number.
			var bundle_shown := (
				chain.chain_visual.drawn_bundle()
				if chain.chain_visual != null else 0
			)
			print(
				"    still · %s  (frame %d  t=%.2fs  head y=%.2f  z=%.2f  bundle %d/%d)"
				% [
					tag, frame_index - 1, _seg_t, head_at.y, head_at.z,
					bundle_shown, chain.chain_visual.coils()
					if chain.chain_visual != null else 0
				]
			)
		else:
			print("    !! still %s failed (%d)" % [tag, err])


# A still rule that never fired is a picture the delivery would be missing. Reported
# rather than left for whoever unzips the folder to notice, for the same reason a
# refused chain beat is printed instead of silently dropped.
func _report_missing_stills() -> void:
	for rule in _stills:
		if not rule["done"]:
			print("    !! still %s never fired in %s" % [String(rule["tag"]), seg_name])


# --- §MOTION sampling --------------------------------------------------------

func _reset_motion_metrics() -> void:
	motion_peak_drag = 0.0
	motion_peak_turn = 0.0
	motion_min_scale = 1.0
	motion_peak_idle = 0.0
	motion_peak_resist = 0.0
	motion_peak_layers = 0.0
	motion_speed_peak = 0.0
	motion_clamped_frames = 0
	motion_sampled_frames = 0
	# A rate left running across a take boundary would spin the next take's player.
	turn_rate = 0.0
	_turn_until = -1.0


# Applied AFTER the frame, so `dt` is the wall time the frame actually took. The
# stow root follows the body, so this is the same path a mouse swing takes.
func _update_turn(t: float, prev_t: float) -> void:
	if turn_rate == 0.0 or player == null:
		return
	player.rotation.y += deg_to_rad(turn_rate) * maxf(0.0, t - prev_t)
	if t >= _turn_until:
		turn_rate = 0.0


# Read once per frame. Peaks rather than means on purpose: the claims are about
# TRANSIENTS — a dodge kick lasts a tenth of a second and a mean over four seconds
# would round it to nothing, which is the same failure as asserting on a total that
# cannot fall below its own noise floor.
#
# ⚠️ AND IT MUST NOT START UNTIL THE TAKE HAS. Every take begins with `_stand_in_lab`,
# which TELEPORTS the player, and the chain's hand speed is a smoothed difference of
# the hand's own world position — so the frame after a teleport reports whatever
# distance was jumped divided by one frame. The first version sampled from frame 0 and
# printed `hand 183.40 m/s` for a take in which the player was standing still, and
# `drag 0.0524 m` for the IDLE take, whose whole claim is that the surplus does NOT
# move. The number was measuring the harness, not the weapon. The drag reading was the
# worse of the two: the visual clamps its own offset (`_clamp_len(..., MOTION_LAG_MAX)`),
# so the teleport spike arrived pre-limited to exactly 0.055 and read as a plausible
# saturated reading rather than as obviously broken.
#
# 0.60 s, and the number is set by the SPRING rather than by the event table. The
# teleport does not merely spike the speed reading for a frame — it injects a large
# displacement into `_motion_off`, and with `MOTION_LAG_ZETA` 0.58 at `MOTION_LAG_TAU`
# 0.062 that ring decays as `e^(-ζt/τ)` = `e^(-9.4t)`. At 0.20 s it is still 15% of the
# spike, which measured as `drag 0.0268 m` on a take where the player never moves —
# five times §7's whole idle drift, printed as the inertia of a standing man. At 0.60 s
# it is 0.4%, i.e. below the idle figure it would be confused with. The earliest event
# in this tour is 0.40 s and the drag it produces takes ~0.2 s to build, so nothing is
# lost: 02's sprint still reads a saturated 0.055.
const MOTION_SETTLE := 0.60


func _sample_motion() -> void:
	var vis := chain.chain_visual if chain != null else null
	if vis == null:
		return
	if _seg_t < MOTION_SETTLE:
		return
	motion_peak_drag = maxf(motion_peak_drag, vis.motion_drag().length())
	motion_peak_turn = maxf(motion_peak_turn, rad_to_deg(vis.motion_turn_lag()))
	var scale := vis.motion_lag_scale()
	motion_min_scale = minf(motion_min_scale, scale)
	motion_sampled_frames += 1
	if scale < 0.9999:
		motion_clamped_frames += 1
	motion_peak_idle = maxf(motion_peak_idle, vis.motion_idle().length())
	motion_peak_resist = maxf(motion_peak_resist, vis.handle_resist().length())
	motion_speed_peak = maxf(motion_speed_peak, vis.motion_hand_speed())
	for offset in vis.motion_layer_offsets():
		motion_peak_layers = maxf(motion_peak_layers, offset)


# Appended only for the motion tour, so the other tours' summary lines are exactly
# as they were. A take that printed seven zeroes would be noise; a MOTION take that
# printed none would be an unbacked claim.
func _motion_metric_line() -> String:
	# `handle` is the TOTAL haul, and it is labelled that way because it is not the
	# same quantity §14 is about. `handle_resist()` returns the whole offset the handle
	# was given, which is the WIND-UP term (`_preload * PRELOAD_REACH`, the handle
	# moving the wrong way before the strike) PLUS the load term (`_load * HANDLE_RESIST`,
	# §14's 2–5 cm). A take that reads 0.0750 m during a wind-up is not failing §14 — the
	# slice measures the load term on its own and gets 0.0450. Printing one number and
	# letting it stand for both would be the same class of mistake as reading the
	# director's `tension` as the picture's `load`.
	return "motion drag %.4f m  turn %.2f°  clamp %.4f (%d/%d frames)  idle %.4f m  handle(total) %.4f m  layers %.4f m  hand %.2f m/s" % [
		motion_peak_drag, motion_peak_turn, motion_min_scale,
		motion_clamped_frames, motion_sampled_frames,
		motion_peak_idle, motion_peak_resist, motion_peak_layers, motion_speed_peak,
	]


func _write_fps(fps: float) -> void:
	var file := FileAccess.open("%s/fps.txt" % output_dir, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("%.4f\n" % fps)
	file.close()


func _clear_existing_frames() -> void:
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return
	var removed := 0
	for file in dir.get_files():
		# Leftover frames from a longer previous take end up in the encode.
		if file.get_extension().to_lower() == "png" or file == "fps.txt":
			dir.remove(file)
			removed += 1
	if removed > 0:
		print("cleared %d stale files" % removed)


# --- overlay ----------------------------------------------------------------

func _build_overlay() -> void:
	layer = CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)

	# Built only in `label` mode, and it is deliberately a bare Label rather than a
	# panel: a box drawn around the fault would frame it, and framing a fault is
	# half of explaining it.
	if hud_mode == "label":
		problem_label = Label.new()
		problem_label.add_theme_font_size_override("font_size", 26)
		layer.add_child(problem_label)
		problem_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
		problem_label.offset_left = 34.0
		problem_label.offset_bottom = -28.0
		problem_label.offset_top = -70.0
		problem_label.offset_right = 560.0
		problem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		problem_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		# Outlined, because the clip is judged over a bright ground plane and an
		# unreadable label is not a label.
		problem_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		problem_label.add_theme_constant_override("outline_size", 8)
		problem_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.82))

	var holder := PanelContainer.new()
	# §32: A TAKE WITH NO TITLE AT ALL. `silent` is for the clip that is shown to
	# someone who has not been told anything — the argument of the chain pass is that
	# 松 / 甩 / 咬 / 绷 / 拉 / 砸 can be read out of the motion ALONE, and a caption
	# that names the beat is the answer key printed on the exam paper. The captions
	# stay for `clean` (the film's voice) and the numbers for `hud` (diagnosis).
	holder.visible = hud_mode != "silent" and hud_mode != "label"
	# Top, not bottom: the blade and the player's own position sit low in this
	# shot, so a bottom strip would cover the one thing the video is about.
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE, true)
	holder.offset_top = 14.0
	# The tallest take decides the box: the chain takes print a two-line weapon
	# readout on top of the four sword lines, and a clipped line is a claim the
	# viewer cannot check.
	holder.offset_bottom = 224.0
	holder.offset_left = 100.0
	holder.offset_right = -100.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.70)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	holder.add_theme_stylebox_override("panel", style)
	layer.add_child(holder)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	holder.add_child(column)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 21)
	title_label.modulate = Color(0.94, 0.95, 0.98, 1.0)
	# WRAPPING, not clipping. The captions are the film's voice — they are the only
	# thing explaining what a take is claiming — and a note that runs off the right
	# edge is a claim half the viewer cannot read. `WORD_SMART` because these are
	# Chinese notes with latin terms in them: a word-only wrap would push a whole
	# sentence to the next line and a character-only wrap would break "CHAIN LAB".
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title_label)

	note_label = Label.new()
	note_label.add_theme_font_size_override("font_size", 14)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.modulate = Color(0.62, 0.72, 0.84, 0.95)
	column.add_child(note_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.modulate = Color(0.52, 0.88, 0.70, 0.95)
	column.add_child(status_label)


func _update_overlay(t: float) -> void:
	if hud_mode == "label":
		# The fault clip's contract: the picture shows the problem, the label names
		# it, and nothing explains it. A reviewer who is told which frame is bad
		# before they have decided cannot be used as evidence that it is bad.
		if problem_label != null:
			problem_label.text = seg_name
		return
	title_label.text = "%s      t = %.2f s" % [seg_name, t]
	note_label.text = seg_note
	status_label.visible = hud_mode == "hud"
	if status_label.visible:
		status_label.text = "%s\n%s\n%s\n%s\n%s" % [
			_spell_line(), _move_line(), combat.debug_state_line(), _enemy_line(), _chain_line()
		]


# §38. State / Radius / Momentum / Tension / Hook target / Weight class, on screen.
# Without it a viewer cannot tell a 0.40s heavy bind from a 1.00s light one except
# by counting frames, and the weight table — which IS the hook — is invisible.
func _chain_line() -> String:
	if chain == null or not chain.is_equipped():
		return "缚星链: 未持有 (剑)"
	return "%s   %s" % [chain.debug_state_line().replace("\n", "   "), chain.debug_flags_line()]


# Movement, because interactions #2 and #5 are claims about movement, and the
# video has to be able to show whether it happened. `攻击类型` is the controller's
# own label for the attack: sprint/retreat are the labels it uses for a hit
# delivered on the move, which is the one that feeds 势 more.
func _move_line() -> String:
	var kind := String(combat.attack_kind)
	if kind == "":
		kind = "-"
	return "运动: 速度 x%.2f   当前流速 %.1f m/s   出刀瞬间移动=%s   攻击类型=%s" % [
		combat.speed_multiplier(),
		player.velocity.length(),
		"是" if combat.commit_moving else "否",
		kind,
	]


func _spell_line() -> String:
	# What is armed, printed every frame next to what the take claimed it would
	# arm. If those two ever disagree the frame says so out loud, instead of a
	# caption quietly describing a spell that was never cast.
	var spell := combat.current_spell()
	if spell == null:
		return "魔法: -"
	var mismatch := ""
	if not seg_spells.is_empty() and not seg_spells.has(spell.id):
		mismatch = "   <<< 这不是本段声明的法术"
	return "魔法: %s · %s%s" % [
		String(combat.selected_school).to_upper(), spell.display_name, mismatch
	]


func _enemy_line() -> String:
	if not dummy.has_method("element_stage"):
		return ""
	var parts: Array[String] = []
	for id in [ElementLibrary.FIRE, ElementLibrary.FROST, ElementLibrary.WIND]:
		var stage: StringName = dummy.call("element_stage", id)
		if stage != &"":
			parts.append("%s=%s" % [id, stage])
	var line := "敌人: %s" % str(dummy.get("state"))
	if not parts.is_empty():
		line += "  " + " ".join(parts)
	if bool(dummy.call("is_brittle")):
		line += "  [BRITTLE]"
	var bind_line := ""
	if combat.bind_until > Time.get_ticks_msec() / 1000.0:
		bind_line = "  >>> BIND 窗口开着 <<<"
	return line + bind_line


# ===========================================================================
# PART C / PART D / PART E / PART F / PART G / PART H — THE PACKAGE'S OWN TAKES
#
# WHY THESE ARE NOT THE EXISTING SWORD TOUR.
#
# The sword tour is a CLAIMS tour: every take sets up the one situation its
# caption is about, so 白蔷庭 measures at 1.1 / 2.3 / 4.0m and 藏锋 fights at 1.9m.
# That is correct for proving a style exists, and wrong for the question a
# reviewer actually asks — "不看 UI，这是不是四套剑?" — because a comparison has to
# hold everything except the one variable constant. So `styles` pins the pair at
# ONE distance with ONE camera and changes only `set_style`.
#
# `play` is a single continuous take rather than a list of demonstrations,
# because gluing demonstrations together is exactly what a "is the combat flow
# coherent" clip must NOT be.
#
# Every take here is FIRST PERSON unless it says otherwise. §11 is explicit that
# the training ground is played in first person and that a third-person camera
# proves the weapon exists without proving anything about feel, so the outside
# camera survives only in `chainglobal`, where the subject is a 10 m chain's
# SHAPE and no first-person frame can contain it.
#
# The setups are BOUND FUNCTION CALLABLES rather than inline lambdas. A lambda
# that has to run four statements has to survive GDScript's capture-by-value rule
# and the parser's suite/comma interaction; a `func` with `.bind()` has neither
# problem and reads the same at every call site.
# ===========================================================================

# One distance for every style take. Long enough that a sword lunge reads; short
# enough that the dummy is a present body rather than a dot. The existing tour's
# 2.1/2.2/1.9/1.1 are deliberately NOT reused.
const REVIEW_DISTANCE := 2.2

# A3 直抛 is a 10 m weapon's longest sentence (§10: "A3 straight throw needs a
# clearly long-range target"). Shot at 2.2 m the throw has nowhere to go, which is
# the easiest way to make the chain look short in a clip that is supposed to show
# how long it is.
const CHAIN_MID := 5.4
const CHAIN_FAR := 9.2


## Swap the held weapon the way the player does, so a review take goes through the
## same unequip cleanup (hitbox, buffer, chain release, rig visibility) that the
## 1 / 2 keys do. Falling back to the raw slot keeps this working on a stage that
## has no WeaponManager mounted.
func _switch(wanted: StringName) -> void:
	var mgr := player.get_node_or_null("WeaponManager")
	if mgr != null and mgr.has_method("equip_weapon"):
		mgr.call("equip_weapon", wanted)
		return
	weapon.equip(wanted)
	combat.finish_action()


## Pitch the head. The idle coils sit at chest height in front of the player and a
## level first-person frame looks straight over them, so the coil beat has to look
## down at its own subject. Negative is down (forward = -basis.z).
func _look(pitch_deg: float) -> void:
	if look_pivot != null:
		look_pivot.rotation.x = deg_to_rad(pitch_deg)


## Turn the body away from the target, so the next beats MISS on purpose. A clip
## that only ever shows the chain connecting cannot show whether a whiff reads as
## a whiff, and §PART D asks for exactly that beat.
func _turn(degrees: float) -> void:
	player.rotation.y += deg_to_rad(degrees)


## §4's one demand is a FAST TURN, and a fast turn is a RATE — not an angle.
##
## `_turn(90.0)` teleports the body a quarter turn inside one frame, and the motion
## system integrates its turn demand per frame, so a teleport produces a single
## enormous spike that the limit then clips to 8° and calls it a lag. That is a
## number produced entirely by the harness: the thing §4 is about is what happens
## when a player SWINGS the view round at 150°/s and the chain arrives late. So the
## turn is applied as a per-frame rate and stopped after `seconds` of wall time.
##
## It is applied to the BODY rather than the look pivot because the stow root is
## welded to the body's own yaw, so a pivot-only turn would move the camera and
## leave the chain exactly where it was — which is precisely the bug §4 names
## ("镜头一抬：整束链：翻过去").
func _yaw(deg_per_second: float, seconds: float) -> void:
	turn_rate = deg_per_second
	_turn_until = _seg_t + seconds


## Style takes: ONE distance, ONE style change, and the sword in hand.
func _setup_pair(style_id: StringName, distance: float, look_deg: float, player_z := 0.0) -> void:
	_clean_arena(style_id)
	_place(Vector3(0.0, PLAYER_Y, player_z), distance)
	_switch(&"sword")
	_look(look_deg)


## Chain takes: the same, with the chain in hand.
func _setup_chain(distance: float, look_deg: float) -> void:
	_clean_arena(&"universal")
	_place(Vector3(0.0, PLAYER_Y, 0.0), distance)
	_switch(&"chain")
	_look(look_deg)


## The SAME five light beats and two heavies for all four styles, returned fresh
## per take so no take can mutate another's schedule.
func _style_beats() -> Array:
	return [
		[0.60, _req.bind(&"light")],
		[1.05, _req.bind(&"light")],
		[1.50, _req.bind(&"light")],
		[1.95, _req.bind(&"light")],
		[3.10, _req.bind(&"heavy")],
		[4.90, _req.bind(&"light")],
		[5.35, _req.bind(&"light")],
		[5.80, _req.bind(&"light")],
		[7.00, _req.bind(&"heavy")],
	]


## The chain's three light beats, in the order the library defines them
## (chain_library: light_chain = [ch_sweep, ch_return, ch_throw]). Named here so a
## take that claims to show A1/A2/A3 and a library that reorders them cannot drift
## apart silently.
func _a1() -> void:
	_chain_beat(&"light", &"ch_sweep")


func _a2() -> void:
	_chain_beat(&"light", &"ch_return")


func _a3() -> void:
	_chain_beat(&"light", &"ch_throw")


# ------------------------------------------------------------- VIDEO 1 (§PART C)
# sword_universal_clean.mp4 — idle / movement / light combo / heavy / guard /
# perfect guard, first person, no debug HUD. ONE take, because the point is what
# the universal sword feels like IN SEQUENCE, and a sequence that cuts between
# setups is a slideshow.
func _build_universal_segments() -> void:
	segments = [
		{
			"name": "剑 · 通用全套 UNIVERSAL",
			"note": "待机 → 移动 → 四段轻击 → 重击 → 格挡 → 完美格挡 → 闪避。",
			"setup": _setup_pair.bind(&"universal", REVIEW_DISTANCE, -3.0, 0.4),
			"fp": true,
			"events": [
				# --- approach on foot, stop. The first 2.6s are deliberately
				# --- empty: the blade has to be given time to sit and settle.
				[2.60, _lane_hold.bind([&"move_forward"])],
				[4.40, _lane_release.bind([&"move_forward"])],
				# --- the four-hit light combo, tapped at player spacing --------
				[5.40, _req.bind(&"light")],
				[5.92, _req.bind(&"light")],
				[6.44, _req.bind(&"light")],
				[6.96, _req.bind(&"light")],
				# --- the heavy, held so the charge is on screen ---------------
				[8.20, _req.bind(&"heavy")],
				# --- block a real enemy swing ---------------------------------
				[11.00, _guard_up],
				[12.40, _enemy_hit_on],
				[12.62, _enemy_hit_off],
				# --- then the PERFECT guard: guard up inside the 0.12s window --
				[14.60, _req.bind(&"light")],
				[16.40, _guard_up],
				[16.62, _enemy_hit_on],
				[16.84, _enemy_hit_off],
				[18.00, _lane_hold.bind([&"move_right"])],
				[18.70, _lane_release.bind([&"move_right"])],
				# --- dodge, then one more exchange ----------------------------
				[19.60, _dodge],
				[21.40, _req.bind(&"light")],
				[21.92, _req.bind(&"light")],
				[22.44, _req.bind(&"light")],
				[23.40, _req.bind(&"heavy")],
			],
			"duration": 26.5,
		},
	]


# ------------------------------------------------------------- VIDEO 2 (§PART C)
# sword_styles_clean.mp4 — four styles, SAME dummy, SAME camera, SAME distance,
# SAME inputs. Only `set_style` moves. This is the only arrangement in which a
# reviewer can answer "are these four different swords" rather than "are these
# four captures".
func _build_styles_segments() -> void:
	segments = [
		{
			"name": "剑 · 通用 UNIVERSAL",
			"note": "基线：所有流派共用的这一套刀。距离 2.2 m 固定。",
			"setup": _setup_pair.bind(&"universal", REVIEW_DISTANCE, -3.0),
			"fp": true,
			"events": _style_beats(),
			"duration": 9.6,
		},
		{
			"name": "剑 · 藏锋 HIDDEN EDGE",
			"note": "纳刀开局；出刀更重、更慢、更短。距离 2.2 m 固定。",
			"setup": _setup_pair.bind(&"hidden_edge", REVIEW_DISTANCE, -3.0),
			"fp": true,
			"events": _style_beats(),
			"duration": 9.6,
		},
		{
			"name": "剑 · 回风 FLOWING WIND",
			"note": "命中才起势；落空后摇完整。距离 2.2 m 固定。",
			"setup": _setup_pair.bind(&"flowing_wind", REVIEW_DISTANCE, -3.0),
			"fp": true,
			"events": _style_beats(),
			"duration": 9.6,
		},
		{
			"name": "剑 · 白蔷庭 WHITE ROSE",
			"note": "Measure：距离决定削势，不决定伤害。距离 2.2 m 固定 —— 这一条对它不利，Measure 要换距离才读得出来，这里刻意不换。",
			"setup": _setup_pair.bind(&"white_rose", REVIEW_DISTANCE, -3.0),
			"fp": true,
			"events": _style_beats(),
			"duration": 9.6,
		},
	]


# ------------------------------------------------------------- VIDEO D (§PART D)
# chain_v3_first_person_clean.mp4 — the chain as the player actually sees it.
# Idle coils, A1 left sweep, A2 fast right-left, A3 straight throw, a whiff that
# retracts, movement and a dodge with the chain out.
#
# NOTHING here pretends A4/A5 exist. They are not implemented, so the combo is
# three beats and a retract, exactly as the build behaves.
func _build_chain_idle_segments() -> void:
	segments = [
		{
			"name": "缚星链 · 待机盘链 IDLE BUNDLE",
			"note": "只看一件事：手里那团是「一把长链」还是「一个盘子」。",
			"setup": _setup_chain.bind(CHAIN_MID, -22.0),
			"fp": true,
			"events": [
				[0.10, _look.bind(-3.0)],
			],
			"duration": 3.0,
		},
	]


# ============================================================================
#  §V4 — THE A1 VERTICAL SLICE (chain_v4_A1_vertical_slice.mp4)
# ============================================================================
#
# WHY THIS TOUR EXISTS, AND WHAT IT REFUSES TO SHOW.
#
# Chain V3 was not judged short of polish — it was judged WRONG AT THE LEVEL OF
# ABSTRACTION: the picture read as "a spline hung in front of the camera with
# something sliding along its end". V4 replaces the presentation with three
# authored rigs (HELD / SWING / TENSION) and rebuilds the three meshes that carry
# the read (handle, trident, link). This tour is the ONLY evidence for that claim,
# so it is one uninterrupted sentence about ONE technique:
#
#   待机盘链 → A1 空挥 → A1 命中敌人 → A1 撞墙 → 咬住 → 绷紧 → 回收 → 待机
#
# PART B freezes A2/A3/A4/A5, E, Q, F and the ultimate until A1 is accepted, so
# there is exactly one technique in the whole clip. A take that also showed A2
# would be smuggling an unapproved beat through an approval gate.
#
# ALL FOUR TAKES ARE FIRST PERSON. Every claim here is about a weapon IN A HAND —
# how much chain is still in the fist, whether the handle moves before the head,
# whether a wall bite holds its place. None of those are visible from outside, and
# the handle is parented to CAMERA space, so an outside camera is not a second
# angle on the same object: it is a different object. (That is also why the look
# pitch does nothing for framing here — see `_stand_in_lab`.)
#
# TARGET A (open ground) / TARGET B (one dummy) / TARGET C (the lab wall at
# WALL_Z = -42.6) are the entire test scene (PART G).
func _build_chain_v4_segments() -> void:
	# ---------------------------------------------------------------------------
	# WHERE THE PLAYER STANDS FOR THE WALL TAKE, AND WHY IT IS A DERIVED NUMBER.
	#
	# 左甩 is an ARC of radius 2.60 → 4.30 m spanning 150°, so its FORWARD REACH IS
	# NOT 4.30 m. The head crosses the player's own centre line (azimuth 180°) at
	# radius ≈ 3.48 m, and that — not the arc's end radius — is the furthest the
	# sweep ever gets in front of the player.
	#
	# The wall's lab-side face is `WALL_Z + 0.35` = -42.25 (the body is 0.7 thick and
	# centred on WALL_Z). Standing 3.35 m off that face puts the crossing at azimuth
	# ≈171°, i.e. just past half way round a 150° arc: the whole right half of the
	# sweep is on screen before the bite, and the bite itself lands a little left of
	# centre where the trident's silhouette is not buried in the player's own body.
	# FURTHER BACK and the sweep simply never touches the wall; CLOSER and it bites
	# on the right, behind the shoulder. This is the one number in the take that a
	# change to 左甩 invalidates, and it is written as a derivation so it moves with
	# the wall.
	# ---------------------------------------------------------------------------
	var wall_face_z := ChainLab.WALL_Z + 0.35
	var wall_stand_z := wall_face_z + 3.35
	# The dummy for TARGET B. It stands ON the arc, not inside it: the head passes
	# the centre line at radius 3.48, so 3.5 m directly ahead is a body the sweep
	# runs through rather than one it orbits. A dummy at 2.0 m would be INSIDE the
	# arc and 左甩 would miss it every single time — which is exactly the kind of
	# silent geometry error this number exists to prevent.
	var enemy_distance := 3.5
	var deck_z := -33.0  # 9.25 m of clear deck: 左甩's 3.48 m reach cannot find the wall
	segments = [
		# ---------------------------------------------------------------- A · IDLE
		{
			"name": "缚星链 V4 · A 待机盘链 IDLE BUNDLE",
			"note": "只看一件事：手里那一团是「一把长链」，还是一个几何圆盘。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, deck_z),
			"fp": true,
			"pitch": -13.0,
			"stills": [
				["chain_v4_idle", func() -> bool:
					return chain.state == ChainDirector.State.HELD and _seg_t > 1.60],
			],
			"events": [],
			"duration": 3.0,
		},
		# ------------------------------------------------------- B · A1 MISS
		{
			"name": "缚星链 V4 · B A1 左甩 空挥 MISS",
			"note": "开阔地，没有目标。看弧、看链的松紧变化、看收势有没有走完。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, deck_z),
			"fp": true,
			"pitch": -13.0,
			"stills": [
				["chain_v4_sweep_peak", func() -> bool:
					return (
						chain.state == ChainDirector.State.SWINGING
						and chain.radius >= 3.30
					)],
			],
			# ONE A1, NOT TWO, and this was MEASURED rather than simplified. The take
			# used to press 左甩 again at t=2.60 to fill its five seconds, and the
			# renderer's own caption check caught what that actually was:
			# `!! light played ch_snap, but this take claims ch_sweep`. The first A1
			# had put the weapon into a hooked state against the deck, so the second
			# press routed to a different technique entirely — and the take's report
			# line showed `walls +1` in a stretch captioned 开阔地，没有目标.
			#
			# A caption is a CLAIM. The fix is not a better caption for the second
			# action: it is that this take is about ONE whiff, and §16 wants the
			# follow-through and the retract seen out, which is what the rest of the
			# five seconds now shows.
			"events": [
				[0.80, _a1],
			],
			"duration": 5.0,
		},
		# ----------------------------------------------------- C · A1 ENEMY HIT
		{
			"name": "缚星链 V4 · C A1 左甩 命中敌人 ENEMY HIT",
			"note": "同一个弧，这一次头部真的落在身体上。看命中那一下有没有「咬」进去。",
			"setup": func() -> void:
				_enter_lab([ElementLibrary.WEIGHT_LIGHT])
				_stand_in_lab(0.0, deck_z)
				_chain_target(ElementLibrary.WEIGHT_LIGHT, enemy_distance),
			"fp": true,
			"pitch": -13.0,
			"events": [
				[0.80, _a1],
				[2.80, _a1],
			],
			"duration": 5.2,
		},
		# ------------------------------------------- D · A1 WALL → BITE → TENSION
		{
			"name": "缚星链 V4 · D A1 撞墙 → 咬住 → 绷紧 → 回收",
			"note": "链头钉在接触点不动，链条从松到紧。撞墙和「被叫回来」必须看得出区别。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, wall_stand_z),
			"fp": true,
			"pitch": -13.0,
			"stills": [
				["chain_v4_wall_bite", func() -> bool:
					return chain.is_anchored() and chain_visual_bite() >= 0.80],
				# §19 — the load still waits for the BITE TO BE OVER, so the two
				# named beats cannot be filed from one frame. They were: both rules
				# went true on frame 265 before `TENSION_BUILD_TIME` separated the
				# bite's clock from the load's, which produced two stills of a single
				# instant and hid the fact that there was only ever one beat.
				["chain_v4_tension", func() -> bool:
					return (
						chain.is_anchored()
						and chain_visual_bite() >= 1.0
						and chain_visual_load() >= 0.95
					)],
			],
			"events": [
				[0.80, _a1],
			],
			"duration": 4.6,
		},
	]


# The two rig readings the wall stills are picked on, wrapped so a still rule stays
# a one-line predicate instead of a null dance inside a dictionary literal.
func chain_visual_bite() -> float:
	return chain.chain_visual.bite_phase() if chain.chain_visual != null else 0.0


func chain_visual_load() -> float:
	return chain.chain_visual.load() if chain.chain_visual != null else 0.0


# The three §MOTION readings a still predicate needs, wrapped for the same reason
# the two above are: a still rule stays a one-line predicate instead of a null dance
# inside a dictionary literal.
func motion_drag_len() -> float:
	return chain.chain_visual.motion_drag().length() if chain.chain_visual != null else 0.0


func motion_release_step() -> int:
	return chain.chain_visual.release_step() if chain.chain_visual != null else 0


func motion_bundle() -> int:
	# `drawn_bundle()`, NOT `coils()`. The two are different numbers on purpose: `coils()`
	# is the ROPE's own count and can be `-1` as a sentinel meaning "the stow is not being
	# drawn this frame", while `drawn_bundle()` is the DRAWING's and is always normalised
	# to `coil_max` or below. §20's last still is a claim about what the hand LOOKS like
	# after the repack, so it is the drawing's number that has to come back up.
	return chain.chain_visual.drawn_bundle() if chain.chain_visual != null else 0


# ============================================================================
#  §V4·B — THE FLOATING MOTION PASS (chain_v4_floating_motion_pass.mp4)
# ============================================================================
#
# WHAT THIS TOUR IS FOR, AND WHY IT IS NOT THE SLICE TOUR.
#
# The `chainv4` tour above answers "is A1 the right technique": one uninterrupted
# sentence, 待机 → 空挥 → 命中 → 撞墙, filmed so a stranger can read the beats off
# the motion. This tour answers a different question — §2 to §14 of the V4·B brief,
# which are all about the FOUR FLOATING ARCS that are NOT the thrown chain:
#
#   does the bundle sitting on the hip behave like it has WEIGHT — does it lag a
#   run, lean into a strafe, get left behind by a fast turn, stop dead when the
#   head bites, and come back to nothing when the fight ends?
#
# Those are different claims and they need different staging, which is why this is
# a second tour rather than more takes on the first. §5 in particular is a claim
# about where the arcs sit IN THE FRAME, so every take is first person — an outside
# camera is not a second angle on the same object, it is a different object.
#
# THE SEVEN TAKES ARE THE SIX KEY FRAMES PLUS ONE. §20 names six stills, and §4's
# fast turn is not one of them — but §4 is a demand ("快速转头 → 3–8°，回正") and a
# demand with no take is a demand with no evidence, so the turn gets its own take
# and its own place in the clip. Order is the order of the brief: idle, turn,
# sprint, dodge, release, bite, repack.
#
# Every take carries `"motion": true`, which appends the peak drag / peak turn /
# clamp floor / idle drift / handle haul to its summary line. THE NUMBERS ARE NOT
# DECORATION: at review resolution a 4 cm lag and a 3° turn-back are invisible, and
# the failure mode of a broken motion system is not "it looks wrong", it is "it
# looks like nothing is happening" — which reads as a PASS. The numbers are what
# make that failure visible, and they are printed for every take whether or not
# they are flattering.
func _build_chain_motion_segments() -> void:
	# The wall take's stance, derived exactly as the slice's is (see the long note
	# in `_build_chain_v4_segments`): 左甩 crosses the player's own centre line at
	# radius ≈3.48 m, and the wall's lab-side face is WALL_Z + 0.35. Standing 3.35 m
	# off that face puts the crossing just past half way round the arc.
	var wall_face_z := ChainLab.WALL_Z + 0.35
	var wall_stand_z := wall_face_z + 3.35
	# 9.25 m of clear deck in front: 左甩's 3.48 m reach cannot find the wall, so the
	# release and the repack are the only two things in frame.
	var deck_z := -33.0
	# THE SPRINT NEEDS A RUNWAY, AND THE LENGTH OF IT IS ARITHMETIC RATHER THAN TASTE.
	#
	# The deck is 24 m long (z = -19 to -43) and the wall stands at -42.6, so the run
	# distance is fixed by where the take starts. The first draft started at -22 and held
	# for 2.40 s — 19.2 m at `combat_tuning`'s 8.0 m/s sprint speed, i.e. the player
	# arrives at the wall face (-42.25) at almost exactly the moment of release, and the
	# take would have been measuring a collision rather than a lag. Started at -24 and
	# held for 1.40 s instead: ~9.5 m of run (the ramp costs something) plus a few metres
	# of deceleration, ending around z = -36 with six metres of deck still in hand.
	var sprint_z := -24.0
	segments = [
		# ------------------------------------------------------------ 01 · IDLE
		{
			"name": "缚星链 V4·B · 01 待机 · 浮链几乎不动",
			"note": "站着不动。四层浮链有没有「呼吸」——目标是活着，不是被动画。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, deck_z),
			"fp": true,
			"pitch": -13.0,
			"motion": true,
			"stills": [
				["01_idle", func() -> bool:
					return chain.state == ChainDirector.State.HELD and _seg_t > 1.80],
			],
			"events": [],
			"duration": 4.0,
		},
		# ------------------------------------------------ 01b · THE FAST TURN §4
		{
			"name": "缚星链 V4·B · 01b 快速转头 · 链被落下 3–8° 再回正",
			"note": "150°/s 甩头。整束链先落在身后，再回到手上；抬镜头不会把整束链翻过去。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, deck_z),
			"fp": true,
			"pitch": -13.0,
			"motion": true,
			"events": [
				[0.90, _yaw.bind(150.0, 0.55)],
			],
			"duration": 3.6,
		},
		# ------------------------------------------------------ 02 · SPRINT LAG
		{
			"name": "缚星链 V4·B · 02 冲刺 · 链被留在身后",
			"note": "向前猛跑。链往后拖；松手后还会往前追几厘米才停 —— 范围是克制的。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, sprint_z),
			"fp": true,
			"pitch": -13.0,
			"motion": true,
			"stills": [
				# 0.050 rather than "some drag": at 8.0 m/s the demand is 0.0818, so the
				# spring SATURATES against `MOTION_LAG_MAX` 0.055 — this threshold only goes
				# true at essentially full sprint, which is the frame the take is about. A
				# lower number would file the picture from the acceleration ramp instead,
				# and the caption would then be promising a sprint while showing a walk.
				["02_sprint_lag", func() -> bool:
					return (
						chain.state == ChainDirector.State.HELD
						and motion_drag_len() >= 0.050
					)],
			],
			"events": [
				[0.40, _lane_hold.bind([&"move_forward", &"sprint"])],
				[1.80, _lane_release.bind([&"move_forward", &"sprint"])],
			],
			"duration": 4.4,
		},
		# ------------------------------------------------------- 03 · DODGE LAG
		{
			"name": "缚星链 V4·B · 03 闪避 · 一次短促的惯性踢",
			"note": "向左闪。整束链被甩向外侧，然后在两百毫秒内收住 —— 不是持续摇晃。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, deck_z),
			"fp": true,
			"pitch": -13.0,
			"motion": true,
			"stills": [
				["03_dodge_lag", func() -> bool:
					return _seg_t > 0.86 and motion_drag_len() >= 0.012],
			],
			"events": [
				[0.55, _lane_hold.bind([&"move_left"])],
				[0.90, _dodge],
				[1.35, _lane_release.bind([&"move_left"])],
			],
			"duration": 3.8,
		},
		# ----------------------------------------------------- 04 · A1 RELEASE
		{
			"name": "缚星链 V4·B · 04 A1 释放 · 四层收成两层",
			"note": "空挥。起手收一层、挥出去再收一层 —— 是阶梯，不是突然生成一条攻击曲线。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, deck_z),
			"fp": true,
			"pitch": -13.0,
			"motion": true,
			"stills": [
				["04_a1_release", func() -> bool:
					return (
						chain.state == ChainDirector.State.SWINGING
						and motion_release_step() >= 1
						and chain.radius >= 1.60
					)],
			],
			"events": [
				[0.80, _a1],
			],
			"duration": 4.6,
		},
		# -------------------------------------------------------- 05 · WALL BITE
		{
			"name": "缚星链 V4·B · 05 撞墙 · 浮链立刻停止漂移",
			"note": "链头咬住墙。命中之后不再有待机漂移 —— 换到张力架，链绷紧、手被拉住。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, wall_stand_z),
			"fp": true,
			"pitch": -13.0,
			"motion": true,
			"stills": [
				["05_wall_bite", func() -> bool:
					return chain.is_anchored() and chain_visual_bite() >= 0.80],
			],
			"events": [
				[0.80, _a1],
			],
			"duration": 4.6,
		},
		# --------------------------------------------------- 06 · REPACKED IDLE
		{
			"name": "缚星链 V4·B · 06 空挥回收 · 回到满盘待机",
			"note": "空挥收势：一层一层把余链收回手里，回到和新的一样。",
			"setup": func() -> void:
				_enter_lab([])
				_stand_in_lab(0.0, deck_z),
			"fp": true,
			"pitch": -13.0,
			"motion": true,
			"stills": [
				["06_repacked_idle", func() -> bool:
					return (
						chain.state == ChainDirector.State.HELD
						and motion_release_step() == 0
						and motion_bundle() >= 4
						and _seg_t > 2.60
					)],
			],
			"events": [
				[0.60, _a1],
			],
			"duration": 4.6,
		},
	]


func _build_chain_fp_segments() -> void:
	segments = [
		{
			"name": "缚星链 · 第一人称 FIRST PERSON",
			"note": "待机盘链 → A1 左甩 → A2 快右左 → A3 直抛 → 落空回收 → 移动/闪避。目标 5.4 m。",
			"setup": _setup_chain.bind(CHAIN_MID, -22.0),
			"fp": true,
			"events": [
				# --- back to eye level before the first beat -------------------
				[2.40, _look.bind(-3.0)],
				# --- A1 / A2 / A3 at mid range --------------------------------
				[3.40, _a1],
				[4.10, _a2],
				[4.80, _a3],
				# --- the same three again, so one of them can be watched twice -
				[6.80, _a1],
				[7.50, _a2],
				[8.20, _a3],
				# --- turn away and whiff: the retract has to read as a retract -
				[9.60, _turn.bind(55.0)],
				[10.60, _a3],
				[12.40, _turn.bind(-55.0)],
				# --- walk while the chain is out ------------------------------
				[14.00, _lane_hold.bind([&"move_forward"])],
				[15.10, _lane_release.bind([&"move_forward"])],
				[15.50, _lane_hold.bind([&"move_right"])],
				[16.30, _lane_release.bind([&"move_right"])],
				# --- dodge with the chain out (does the head follow?) ---------
				[16.90, _dodge],
				# --- A1/A2/A3 one last time -----------------------------------
				[18.90, _a1],
				[19.60, _a2],
				[20.30, _a3],
				# --- settle, so the retract and the re-coil are both on screen -
				[22.30, _look.bind(-20.0)],
			],
			"duration": 32.0,
		},
	]


# ---------------------------------------------- VIDEO D, DEBUG (§PART D)
# chain_v3_global_debug.mp4 — the SHAPE of the weapon, which no first-person frame
# can contain: 10 m of chain, the coils releasing, the head's trajectory, and the
# A3 distance measured against a target that is genuinely 9.2 m away.
#
# Outside camera and `--hud hud` on purpose. This clip is not feel evidence and is
# labelled as such in the README; it exists so a reviewer can see the geometry the
# first-person clip cannot show.
func _build_chain_global_segments() -> void:
	segments = [
		{
			"name": "缚星链 · 全链身 10 m",
			"note": "待机 → 展开。整条链的长度与盘绕量。",
			"setup": _setup_chain.bind(CHAIN_MID, -3.0),
			"fp": false,
			"cam": {"side": 4.6, "back": 6.4, "up": 5.4, "aim": 3.2},
			"events": [
				[2.60, _a1],
				[4.00, _lane_hold.bind([&"move_back"])],
				[5.00, _lane_release.bind([&"move_back"])],
			],
			"duration": 6.4,
		},
		{
			"name": "缚星链 · A1 左甩 · 头部轨迹",
			"note": "左甩是分段方位角，不是一条 300° 弧。",
			"setup": _setup_chain.bind(CHAIN_MID, -3.0),
			"fp": false,
			"cam": {"side": 4.6, "back": 6.4, "up": 5.4, "aim": 3.2},
			"events": [
				[0.90, _a1],
				[3.20, _a1],
				[5.00, _a1],
			],
			"duration": 6.6,
		},
		{
			"name": "缚星链 · A2 快右左 · 两段方位角",
			"note": "右→左两段。速度是这一拍的卖点。",
			"setup": _setup_chain.bind(CHAIN_MID, -3.0),
			"fp": false,
			"cam": {"side": 4.6, "back": 6.4, "up": 5.4, "aim": 3.2},
			"events": [
				[0.90, _a2],
				[3.00, _a2],
				[4.80, _a2],
			],
			"duration": 6.4,
		},
		{
			"name": "缚星链 · A3 直抛 · 9 m 落点",
			"note": "目标 9.2 m。这一拍的距离就是这把武器存在的理由。",
			"setup": _setup_chain.bind(CHAIN_FAR, -3.0),
			"fp": false,
			"cam": {"side": 6.0, "back": 8.0, "up": 6.2, "aim": 4.8},
			"events": [
				[0.90, _a3],
				[3.20, _a3],
				[5.20, _a3],
			],
			"duration": 6.8,
		},
	]


# ------------------------------------------------------------- VIDEO F (§PART F)
# magic_current_clean.mp4 — fire / frost / wind as they are TODAY. Flat casts,
# no weapon interaction (imbuement is designed but not built), so the clip makes
# no claim beyond "these three exist and are distinguishable on screen".
func _build_magic_segments() -> void:
	segments = [
		{
			"name": "魔法 · 火 FIRE / 冰 FROST / 风 WIND",
			"note": "三系当前真实状态。不是 Placeholder，但也没有武器 × 元素的交互。",
			"setup": _setup_pair.bind(&"universal", 3.6, -3.0),
			"fp": true,
			"events": [
				[0.80, _spell.bind(&"fire_bolt")],
				[1.40, _req.bind(&"cast")],
				[3.40, _spell.bind(&"frost_stream")],
				[4.00, _req.bind(&"cast")],
				[6.00, _spell.bind(&"wind_pressure")],
				[6.60, _req.bind(&"cast")],
				[8.20, _spell.bind(&"frost_stream")],
				[8.80, _req.bind(&"cast")],
			],
			"duration": 11.4,
		},
	]


# ------------------------------------------------------------- VIDEO G (§PART G)
# combat_real_play_clean.mp4 — ONE continuous 74 second take, no captions, no
# cuts, no reset. §PART G is explicit that this matters more than every individual
# demo combined: it is the only clip in the package that can answer "is the combat
# flow coherent".
func _build_play_segments() -> void:
	segments = [
		{
			"name": "实战 · REAL PLAY",
			"setup": _setup_pair.bind(&"universal", 4.2, -3.0, 0.6),
			"fp": true,
			"events": [
				# --- approach, moving like a player and not like a demo --------
				[1.00, _lane_hold.bind([&"move_forward"])],
				[1.90, _lane_release.bind([&"move_forward"])],
				[2.30, _req.bind(&"light")],
				[2.85, _req.bind(&"light")],
				[3.60, _lane_hold.bind([&"move_right"])],
				[4.20, _lane_release.bind([&"move_right"])],
				[4.50, _req.bind(&"heavy")],
				# --- read the enemy, block it ----------------------------------
				[6.40, _guard_up],
				[6.80, _enemy_hit_on],
				[7.05, _enemy_hit_off],
				# --- break off, dodge, come back -------------------------------
				[8.00, _dodge],
				[9.30, _lane_hold.bind([&"move_left"])],
				[10.10, _lane_release.bind([&"move_left"])],
				[10.40, _req.bind(&"light")],
				[11.00, _req.bind(&"light")],
				# --- SWITCH TO THE CHAIN ---------------------------------------
				[12.60, _switch.bind(&"chain")],
				[13.60, _a1],
				[14.30, _a2],
				[15.00, _a3],
				[16.60, _lane_hold.bind([&"move_back"])],
				[17.40, _lane_release.bind([&"move_back"])],
				[17.80, _a1],
				[18.50, _a2],
				[19.20, _a3],
				# --- the chain's own heavy: spin, then release ------------------
				[21.40, _hold.bind(&"heavy_attack", true)],
				[22.90, _hold.bind(&"heavy_attack", false)],
				# --- hook something and pull ----------------------------------
				[24.60, _chain_req_expect.bind(&"chain_hook", &"ch_hook")],
				[27.40, _chain_beat.bind(&"light", &"ch_pull_cut")],
				# --- SWITCH BACK TO THE SWORD ----------------------------------
				[29.60, _switch.bind(&"sword")],
				[30.80, _req.bind(&"light")],
				[31.35, _req.bind(&"light")],
				[32.40, _req.bind(&"heavy")],
				# --- magic, then fight on ---------------------------------------
				[34.60, _spell.bind(&"frost_stream")],
				[35.40, _req.bind(&"cast")],
				[37.40, _lane_hold.bind([&"move_forward"])],
				[38.30, _lane_release.bind([&"move_forward"])],
				[38.60, _req.bind(&"light")],
				[39.15, _req.bind(&"light")],
				[39.70, _req.bind(&"light")],
				# --- chain again, this time with wind feeding it ---------------
				[41.80, _switch.bind(&"chain")],
				[43.00, _spell.bind(&"wind_pressure")],
				[43.70, _req.bind(&"cast")],
				[45.40, _a1],
				[46.10, _a2],
				[46.80, _a3],
				[48.60, _dodge],
				[50.00, _a1],
				[50.70, _a2],
				[51.40, _a3],
				# --- finish on the sword ---------------------------------------
				[53.60, _switch.bind(&"sword")],
				[54.80, _req.bind(&"heavy")],
				[56.60, _lane_hold.bind([&"move_right"])],
				[57.40, _lane_release.bind([&"move_right"])],
				[57.80, _req.bind(&"light")],
				[58.35, _req.bind(&"light")],
				[59.40, _guard_up],
				[60.20, _enemy_hit_on],
				[60.45, _enemy_hit_off],
				[62.00, _spell.bind(&"fire_bolt")],
				[62.70, _req.bind(&"cast")],
				[65.00, _req.bind(&"light")],
				[65.55, _req.bind(&"light")],
				[67.20, _dodge],
				[69.00, _switch.bind(&"chain")],
				[70.20, _a1],
				[70.90, _a2],
				[71.60, _a3],
			],
			"duration": 74.0,
		},
	]


# ------------------------------------------------------------- VIDEO H (§PART H)
# combat_problems.mp4 — the faults, labelled and unexplained. Shown with
# `--hud label`, which draws ONE short string in the bottom left and nothing else.
# The task's name IS the label; a take that needed two lines to explain itself
# would be a take that is arguing rather than showing.
#
# Nothing here is staged to look worse than it is. The point of the reel is that a
# reviewer trusts the good clips because the bad ones were put on the table.
func _build_problem_segments() -> void:
	segments = [
		{
			"name": "A3 直抛 · 第一人称看不清",
			"setup": _setup_chain.bind(CHAIN_MID, -3.0),
			"fp": true,
			"events": [
				[0.90, _a1],
				[1.60, _a2],
				[2.30, _a3],
				[3.40, _a1],
				[4.10, _a2],
				[4.80, _a3],
			],
			"duration": 7.0,
		},
		{
			"name": "收招 · 像机器",
			"setup": _setup_pair.bind(&"universal", REVIEW_DISTANCE, -3.0),
			"fp": true,
			"events": [
				[0.60, _req.bind(&"light")],
				[1.40, _req.bind(&"light")],
				[2.20, _req.bind(&"light")],
				[3.00, _req.bind(&"heavy")],
				[4.40, _req.bind(&"light")],
			],
			"duration": 6.0,
		},
		{
			"name": "敌人 · 挨打没反应",
			"setup": _setup_pair.bind(&"universal", REVIEW_DISTANCE, -3.0),
			"fp": true,
			"events": [
				[0.70, _req.bind(&"heavy")],
				[2.40, _req.bind(&"light")],
				[3.10, _req.bind(&"light")],
				[3.80, _req.bind(&"light")],
			],
			"duration": 5.4,
		},
		{
			"name": "换手 · 中间那一顿",
			"setup": _setup_pair.bind(&"universal", REVIEW_DISTANCE, -3.0),
			"fp": true,
			"events": [
				[0.60, _req.bind(&"light")],
				[1.20, _switch.bind(&"chain")],
				[2.60, _switch.bind(&"sword")],
				[3.20, _req.bind(&"light")],
				[3.90, _switch.bind(&"chain")],
			],
			"duration": 5.6,
		},
		{
			"name": "起跳 · 最高点发飘",
			"setup": _setup_pair.bind(&"universal", REVIEW_DISTANCE, -3.0),
			"fp": true,
			"events": [
				[0.50, _lane_hold.bind([&"move_forward"])],
				[0.80, _jump_press],
				[0.95, _jump_release],
				[2.40, _lane_release.bind([&"move_forward"])],
			],
			"duration": 4.6,
		},
		{
			"name": "魔法 · 看不出区别",
			"setup": _setup_pair.bind(&"universal", 3.2, -3.0),
			"fp": true,
			"events": [
				[0.60, _spell.bind(&"fire_bolt")],
				[1.20, _req.bind(&"cast")],
				[2.80, _spell.bind(&"frost_stream")],
				[3.40, _req.bind(&"cast")],
				[5.00, _spell.bind(&"wind_pressure")],
				[5.60, _req.bind(&"cast")],
			],
			"duration": 7.4,
		},
	]
