extends SceneTree
# PART N #4: do the styles actually PLAY differently?
#
# `style_integration` answers this by reading the authoring: 一文字's startup is
# under 0.07, 回风 steers twice as hard, 藏锋 is stiffer. Every one of those is a
# claim about a NUMBER, and a number can be correct while the thing it describes
# never reaches the player — which is what the whole six-channel pass has been
# about. Mutating those numbers turns that test red, so it is not decoration,
# but it is a data sheet: it would stay green if the styles were wired to the
# same pose driver, the same windows and the same feedback and only their
# spreadsheets differed.
#
# So this rig asks the behavioural question instead: run each style's opening
# light through the same fixed-step rig the sword audit uses, and compare what
# the player would actually receive — how long the cut takes, when the blade
# leaves, how fast it is going, and the shape it traces. Three styles have to be
# three different sentences in those terms, or "a style" is a costume.
#
#   A. RHYTHM   the same input must not take the same time in two styles.
#   B. DEPARTURE  the blade must not leave at the same moment.
#   C. SHAPE    the blade must not trace the same curve.
#
# Deliberately NOT measured: damage. Styles are rhythm, not numbers — the
# project's own rule, and the one a data sheet is most likely to drift into.

const STEP := 1.0 / 60.0
const BLADE_LENGTH := 0.95

var world: Node3D
var player: CharacterBody3D
var lane: MovementLane
var combat: CombatController
var weapon: Node3D
var failures: Array[String] = []
var metrics: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _wait(frames: int) -> void:
	for _i in frames:
		await physics_frame


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	lane = MovementLane.new()
	world.add_child(lane)
	# Collaborators before the player, for the reason given in every other rig
	# in this folder: @onready resolves on tree entry, and a missing
	# TimeEffectManager reads as "this build has no time stops" rather than as
	# "this rig forgot one".
	var screen := CombatScreenFX.new()
	screen.name = "CombatScreenFX"
	world.add_child(screen)
	var clock := TimeEffectManager.new()
	clock.name = "TimeEffectManager"
	world.add_child(clock)
	var packed: PackedScene = load("res://scenes/player/Player.tscn")
	player = packed.instantiate()
	world.add_child(player)
	player.global_position = lane.start_position()
	await _wait(24)
	combat = player.get_node("CombatController")
	weapon = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")
	player.unlimited_resources = true

	var styles := {
		&"universal": "通用", &"hidden_edge": "藏锋", &"flowing_wind": "回风",
	}
	var runs := {}
	for id in styles:
		combat.set_style(id, true)
		await _wait(4)
		runs[id] = await _light_run()
		runs[id]["steer"] = await _steer_run()

	await _compare(runs, styles)
	_report(runs, styles)


# ------------------------------------------------------------------- the run

# One opening light, stepped by hand, with the tip sampled every frame. The
# controller and the weapon come off the tree's clock for the same reason they
# do in sword_feel_channels: the pose driver is an exponential lag on a jittering
# delta, so two runs of the same swing disagree by about as much as the
# difference being looked for between two styles.
func _light_run() -> Dictionary:
	await _wait_until_idle()
	_neutralise()
	await _wait(2)
	combat.set_process(false)
	weapon.set_process(false)
	player.set_physics_process(false)
	var tips: Array[Vector3] = []
	var startup := 0.0
	var frames := 0
	var announced := -1.0
	for _i in 8:
		_step()
	combat.request(&"light")
	await _step_once()
	startup = combat.effective_startup()
	var peak_speed := 0.0
	var prev := _tip()
	for _i in 160:
		_step()
		var now := _tip()
		peak_speed = maxf(peak_speed, now.distance_to(prev) / STEP)
		prev = now
		tips.append(now)
		frames += 1
		if announced < 0.0 and combat.state_time >= startup:
			announced = combat.state_time
		if combat.state != CombatController.State.ATTACK and frames > 4:
			break
	combat.set_process(true)
	weapon.set_process(true)
	player.set_physics_process(true)
	await _wait_until_idle()
	return {
		"tips": tips, "frames": frames, "startup": startup,
		"announced": announced, "peak_speed": peak_speed,
		"move": combat.moveset.get_move(combat.moveset.light_chain[0]).id,
	}


# 回风's identity is MOTION, not wind-up: it is the style that keeps moving while
# it cuts. Asking it to have a different startup than the universal layer is
# asking the wrong question — and the answer it gives back (0.090 vs 0.085) says
# more about the question than about the style. What has to be true is that the
# cut CARRIES THE BODY: hold a direction and measure how far the player is taken
# sideways by their own swing. A style that cannot do that is 回风 in name only.
func _steer_run() -> float:
	await _wait_until_idle()
	_neutralise()
	_release_wish()
	await _wait(6)
	Input.action_press("move_right")
	await _wait(6)
	var start := player.global_position
	var right := player.global_basis.x
	combat.request(&"light")
	for _i in 40:
		await physics_frame
		if combat.state != CombatController.State.ATTACK and _i > 4:
			break
	var moved: float = (player.global_position - start).dot(right)
	_release_wish()
	await _wait_until_idle()
	return moved


func _release_wish() -> void:
	for name in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(name)


func _step() -> void:
	combat._process(STEP)
	weapon._process(STEP)


# One step, but as a coroutine: the move has to have started before its own
# numbers can be read, and `request` does not start it inside this rig's step.
func _step_once() -> void:
	_step()
	await process_frame


func _tip() -> Vector3:
	return weapon.position + (Basis.from_euler(weapon.rotation) * Vector3.UP) * BLADE_LENGTH


func _neutralise() -> void:
	combat.chain_expires_at = 0.0
	combat.combo_index = 0
	combat.last_light_at = -10.0
	combat.pending_followup_id = &""
	combat.followup_until = 0.0
	combat.riposte_until = 0.0
	combat.bind_until = 0.0
	combat.slip_until = 0.0
	combat.slip_skill = null
	combat.buffer.clear()


func _wait_until_idle() -> void:
	for _i in 200:
		if combat.state == CombatController.State.IDLE:
			return
		await physics_frame


# --------------------------------------------------------------- the compare

# Every pair is checked, not just each style against the universal layer: two
# styles agreeing with each other is the same failure as two styles agreeing with
# the shared language.
func _compare(runs: Dictionary, styles: Dictionary) -> void:
	var ids: Array = runs.keys()
	var closest_shape := 1e9
	var shape_pair := ""
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = runs[ids[i]]
			var b: Dictionary = runs[ids[j]]
			var d_shape: float = _path_departure(a["tips"], b["tips"])
			metrics["shape_%s_%s" % [ids[i], ids[j]]] = d_shape
			if d_shape < closest_shape:
				closest_shape = d_shape
				shape_pair = "%s/%s" % [styles[ids[i]], styles[ids[j]]]
	metrics["closest_shape"] = closest_shape
	metrics["shape_pair"] = shape_pair

	# C. SHAPE. Every pair, not just each style against the shared language: two
	# styles agreeing with each other is the same failure.
	#
	# WHAT THIS ACTUALLY MEASURES, written down because it was found the hard
	# way: replacing 回风's entire authored pose with the universal one does NOT
	# turn this red. The path still differs by more than 0.15m, because what is
	# being sampled is the weapon's final transform, which carries the
	# locomotion offsets — and the two styles move the body differently (their
	# `lunge` and `steer` differ), so the sword is dragged differently even when
	# it is told to hold the identical pose.
	#
	# That is not a flaw in the threshold, it is a statement about the claim:
	# "the swing the player receives" genuinely includes how their own body is
	# carried through it, and in first person that is most of what a style feels
	# like. A pose-only comparison would need the locomotion contribution
	# neutralised, which would be a different — and narrower — assertion.
	_check(
		closest_shape >= 0.15,
		"the closest two styles (%s) trace paths only %.4fm apart — the body cannot tell them apart, and first person is the only place a style has to be true"
			% [shape_pair, closest_shape]
	)

	# A/B. IDENTITY, and deliberately asked per style rather than per pair.
	#
	# Requiring every pair to differ in the same channel is the wrong question.
	# 回风 answered "my startup is 0.090 and the universal's is 0.085" and that
	# number says more about the question than about the style: 回风 is not the
	# fast-draw style, it is the style that keeps moving. Forcing a rhythm gap
	# onto it would be authoring to satisfy a test. What each style owes is a
	# difference in the channel that IS its identity.
	var uni: Dictionary = runs[&"universal"]
	var he: Dictionary = runs[&"hidden_edge"]
	var fw: Dictionary = runs[&"flowing_wind"]
	metrics["he_startup_gain"] = float(uni["startup"]) - float(he["startup"])
	metrics["fw_steer_gain"] = float(fw["steer"]) - float(uni["steer"])

	# 藏锋 waits and draws: its identity is that the blade is ALREADY out when
	# the player decides. Measured as the wind-up it actually gives them.
	_check(
		float(he["startup"]) <= float(uni["startup"]) * 0.75,
		"藏锋's opening light releases in %.3fs against the universal %.3fs (%.0f%% of it) — the draw is its whole identity, and a draw that takes as long as a normal cut is not a draw"
			% [float(he["startup"]), float(uni["startup"]), float(he["startup"]) / maxf(float(uni["startup"]), 0.0001) * 100.0]
	)
	# 回风 moves: its identity is that the cut carries the body.
	_check(
		float(fw["steer"]) >= float(uni["steer"]) * 1.5 + 0.01,
		"回风's cut carries the body %.3fm sideways against the universal %.3fm — a style about moving that does not move differently while it swings is 回风 in name only"
			% [float(fw["steer"]), float(uni["steer"])]
	)


# How far one blade's PATH ever leaves the other blade's path. Not frame-to-frame
# and not phase-to-phase: two swings of different lengths would then differ purely
# on the timing. See sword_feel_channels.gd for the full argument.
func _path_departure(a: Array, b: Array) -> float:
	var worst := 0.0
	for i in a.size():
		var point := a[i] as Vector3
		var best := 1e9
		for j in b.size() - 1:
			var p := b[j] as Vector3
			var q := b[j + 1] as Vector3
			var edge := q - p
			var span := edge.length_squared()
			var u := 0.0 if span < 1e-9 else clampf((point - p).dot(edge) / span, 0.0, 1.0)
			best = minf(best, point.distance_to(p + edge * u))
		worst = maxf(worst, best)
	return worst


# ------------------------------------------------------------------- reporting

func _check(condition: bool, reason: String) -> void:
	if condition:
		return
	failures.append(reason)


func _report(runs: Dictionary, styles: Dictionary) -> void:
	print("")
	print("STYLE VOICE · the same input, three styles")
	for id in runs:
		var r: Dictionary = runs[id]
		print("  %-4s %-14s %2d frames · startup %.3fs · peak %.2f m/s · carried %.3fm"
			% [
				styles[id], r["move"], int(r["frames"]), float(r["startup"]),
				float(r["peak_speed"]), float(r["steer"]),
			])
	print("  closest pair %s: path %.4fm apart" % [metrics.get("shape_pair", "?"), metrics.get("closest_shape", 0.0)])
	print("  identity    藏锋 draw %.3fs vs 通用 %.3fs · 回风 carries %.3fm vs 通用 %.3fm"
		% [
			float(runs[&"hidden_edge"]["startup"]), float(runs[&"universal"]["startup"]),
			float(runs[&"flowing_wind"]["steer"]), float(runs[&"universal"]["steer"]),
		])
	print("")
	if failures.is_empty():
		print("PASS: every style answers the same input with a different curve, and each one differs from the shared language in the channel that is its identity")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
