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
# "review" (outside camera) or "fp" (the player's own eyes); see _run_segment.
var cam_mode := "review"
# The spells this take claims to be showing. The overlay prints what is ACTUALLY
# armed next to it, so a caption that drifts from the code is visible in the very
# frame that makes the claim — which is how the fire takes were caught promising
# a burning field while casting 火矢, a spell that leaves no field at all.
var seg_spells: Array = []
# 势 peaks recorded inside a take, printed with its summary line.
var seg_metrics: Array[String] = []
var flow_peak := 0.0
var run_origin := Vector3.ZERO

const MOVE_ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint"]
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
	DirAccess.make_dir_recursive_absolute(output_dir)
	_clear_existing_frames()

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# Same reason as the Iaido renderer: a covered window stops firing
	# frame_post_draw and the capture loop hangs forever.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

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
	player.unlimited_resources = true
	# The dummy attacking on its own would poison every take that is not about
	# being attacked.
	dummy.set("attack_cooldown", 9999.0)

	_build_overlay()
	if tour == "chain":
		_build_chain_segments()
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
				[SETTLE + 0.10, _chain_req.bind(&"light")],
				[SETTLE + 0.50, _chain_req.bind(&"light")],
				[SETTLE + 0.90, _chain_req.bind(&"light")],
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
				[SETTLE + 0.10, _chain_req.bind(&"light")],
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
				[SETTLE + 0.10, _chain_req.bind(&"heavy")],
				# Released with a margin on purpose. The orbit throws ITSELF at
				# orbit_max_hold (1.30s), and this event used to sit 0.10s inside that
				# cap — which is fine at 20fps and refused at 8fps, because a frame is
				# then 0.12s of game time and the event lands after the window has
				# already closed. A take may not depend on the frame rate.
				[SETTLE + 1.08, _chain_release],
				[SETTLE + 2.60, _chain_req.bind(&"light")],
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
				[SETTLE + 0.10, _chain_req.bind(&"chain_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
				# THE EXIT HAS TO LAND INSIDE THE WINDOW IT EXITS. 缚 opens 1.00s here and
				# the haul it starts runs for ~1.2s, so the tempting move — delay the exit
				# until the haul has finished — pushes it past the window and the request
				# is simply REFUSED (the renderer prints `!! light refused`, which is how
				# this was caught). The haul outliving the bind is the DESIGN (see
				# `_release_hook` in chain_director.gd); the exit is a separate deadline.
				# 0.75s into a 1.00s window, which also survives an 8fps frame.
				[SETTLE + 1.80, _chain_req.bind(&"light")],
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
				[SETTLE + 0.10, _chain_req.bind(&"chain_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
				# 0.25s into a 0.40s window. This is the tightest timing in the whole tour:
				# a heavy is given the SHORTEST bind on purpose (§18's counterplay), so the
				# exit has almost no room — and when it missed, this take did not fail, it
				# silently played 蓄势回旋 → 甩星 instead of 地砸. The caption and the
				# animation disagreed and nothing in the log said so.
				[SETTLE + 1.30, _chain_req.bind(&"heavy")],
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
				[SETTLE + 0.10, _chain_req.bind(&"chain_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"heavy")],
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
				[SETTLE + 0.10, _chain_req.bind(&"chain_hook")],
				[SETTLE + 1.05, _chain_req.bind(&"chain_lock")],
			],
			"duration": SETTLE + 3.8,
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
				[SETTLE + 0.10, _chain_req.bind(&"chain_hook")],
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
				[SETTLE + 0.10, _chain_req.bind(&"heavy")],
				# Cast as early as the orbit allows. 风 is a boost to the SPIN, so it
				# only pays for the seconds it is actually held — cast at 0.55s against
				# a release at 1.05s it bought three points of launch, which is not an
				# argument, it is noise. Take 2 holds for exactly the same 0.95s with no
				# spell, so the only difference between the two takes is the wind.
				[SETTLE + 0.20, _req.bind(&"cast")],
				[SETTLE + 1.05, _chain_release],
			],
			"duration": SETTLE + 3.4,
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
	var setup: Callable = segment["setup"]
	setup.call()
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
	print("--- %s" % seg_name)

	while true:
		var t := float(Time.get_ticks_msec() - begin) / 1000.0
		while next_event < events.size() and t >= float(events[next_event][0]):
			var action: Callable = events[next_event][1]
			action.call()
			next_event += 1
		await _frame()
		_note_parry()
		flow_peak = maxf(flow_peak, combat.flow_ratio())
		_update_camera()
		_update_review_body()
		_update_overlay(t)
		_save()
		if t >= duration and next_event >= events.size():
			break
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
	if not chain.request(action):
		print("    !! %s refused at %.2fs in %s"
			% [String(action), chain.state_time, seg_name])


func _chain_release() -> void:
	if not chain.release_heavy():
		print("    !! 释 refused in %s" % seg_name)


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
	if frame_index % 60 == 0:
		print("    frame %d" % frame_index)


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

	var holder := PanelContainer.new()
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
	column.add_child(title_label)

	note_label = Label.new()
	note_label.add_theme_font_size_override("font_size", 14)
	note_label.modulate = Color(0.62, 0.72, 0.84, 0.95)
	column.add_child(note_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.modulate = Color(0.52, 0.88, 0.70, 0.95)
	column.add_child(status_label)


func _update_overlay(t: float) -> void:
	title_label.text = "%s      t = %.2f s" % [seg_name, t]
	note_label.text = seg_note
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
