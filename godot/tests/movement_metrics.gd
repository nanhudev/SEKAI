extends SceneTree
# Movement FEEL metrics (PART M §36).
#
# WHY THIS FILE EXISTS: feel arguments are not arguable. "The stop is too
# slidey" is either a number or it is an opinion, and only one of those can be
# regression-tested. This file turns §17/§18/§19/§25 and PART I into numbers:
#
#   0 -> max time      §17  "jog enters fast, sprint builds over 0.2-0.45s"
#   max -> stop dist   §18  "must not stop dead, must not slide three metres"
#   180 turn time      §19  "brake / pivot / re-accelerate, input still answers"
#   jump airtime       §24
#   dodge dist + time  PART I "a burst of movement, not teleport 1.8m"
#
# The point of recording them is NOT realism. It is that this codebase has one
# locomotion solver shared by base movement, 风步, the chain's drag, combat
# lunges and styles; when a later change makes running feel worse, these numbers
# are what say which axis drifted. A parameter guessed to fix "floaty" has
# quietly broken "stop" in this engine before.

const TICK := 60.0

var world: Node3D
var player: CharacterBody3D
var lane: MovementLane
var combat: CombatController
var camera: Camera3D
var failures: Array[String] = []
var metrics: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# NOT the combat sandbox. The rig is assembled here from the player and the
	# lane alone, because a measurement taken inside the shared stage is a
	# measurement of everybody's work: several other sessions write to that scene,
	# and one of their scripts failing to parse mid-edit took the tuning resource
	# down with it, producing a well-formatted table of zeros. Movement answers one
	# question — how does the body move — so it needs a stage holding nothing else.
	world = Node3D.new()
	root.add_child(world)
	lane = MovementLane.new()
	world.add_child(lane)
	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	player = scene.instantiate()
	world.add_child(player)
	combat = player.get_node("CombatController")
	camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
	await _wait(6)
	# A measured run must be a PURE locomotion run: no chain in hand, no lingering
	# style buff, no wind multiplier. The chain scales movement by design (§28 —
	# a chain attack does not lock movement the way a sword cut does), so leaving
	# it equipped would be measuring the chain.
	var weapon = player.get_node_or_null("WeaponSlot")
	if weapon != null and not weapon.is_sword():
		weapon.equip(&"sword")
	player.unlimited_resources = true

	await _measure_jog_build()
	await _measure_sprint_build()
	await _measure_stop_from_sprint()
	await _measure_stop_from_jog()
	await _measure_turn_180()
	await _measure_jump()
	await _measure_dodge()

	_report()
	if failures.is_empty():
		print("PASS: the body accelerates, settles, turns and lands inside the PART G envelope")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)


# ---------------------------------------------------------------- measurement

# 0 -> 95% of max. Jog is the default pace and §17 wants it entered FAST; a jog
# that takes three tenths of a second to arrive reads as ice underfoot.
func _measure_jog_build() -> void:
	var samples := await _accelerate(false)
	metrics["jog_time"] = samples.time
	metrics["jog_speed"] = samples.speed
	_check(
		samples.time <= 0.30,
		"jog took %.3fs to reach speed — §17 wants the default pace entered immediately, not floated into"
			% samples.time
	)
	_check(
		samples.speed > 4.0,
		"jog settled at %.2f m/s — the run never actually got going" % samples.speed
	)


# §17: sprint has to BUILD. Not slowly, but visibly; this is also the axis the
# most things can accidentally flatten (a lazily-applied speed multiplier turns
# it into a switch).
func _measure_sprint_build() -> void:
	var samples := await _accelerate(true)
	metrics["sprint_time"] = samples.time
	metrics["sprint_speed"] = samples.speed
	_check(
		samples.time >= 0.18 and samples.time <= 0.45,
		"sprint reached speed in %.3fs — §17 wants 0.2-0.45s of visible build-up, and outside that window it is either a switch or a slog"
			% samples.time
	)


# §18: releasing input must leave a BODY, not a rail. Too short and the player
# is a cursor; too long and every corner overshoots by two metres. This is the
# number most likely to have drifted, because non-sprint tuning gets changed
# while thinking about something else.
func _measure_stop_from_sprint() -> void:
	var samples := await _coast(true)
	metrics["stop_dist"] = samples.distance
	metrics["stop_time"] = samples.time
	_check(
		samples.distance >= 0.35,
		"the body stopped in %.2fm — that is a cursor snapping to zero, not a body settling" % samples.distance
	)
	_check(
		samples.distance <= 1.60,
		"the body slid %.2fm after the key was released — §18 says three metres is a failure and this is most of the way there"
			% samples.distance
	)


func _measure_stop_from_jog() -> void:
	var samples := await _coast(false)
	metrics["jog_stop_dist"] = samples.distance
	_check(
		samples.distance >= 0.15 and samples.distance <= 0.90,
		"a jog stop slid %.2fm — the two paces are supposed to carry different mass" % samples.distance
	)


# §19: a high-speed reversal must go brake -> pivot -> re-accelerate, but it
# still has to ANSWER. Naive `move_toward` on one shared rate takes v change /
# rate = 16/14 = 1.14s here, which is a boat, not a duellist.
func _measure_turn_180() -> void:
	await _place_at_start()
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait(warm_up_frames(true))
	var top := _hspeed()
	Input.action_release(&"move_forward")
	# SPRINT STAYS DOWN. Releasing it makes the achievable reverse speed the walk
	# ceiling instead, so the "-95% of top" test below could never be met no
	# matter how the body handled it — the harness would report 4 seconds forever
	# and blame the turning.
	Input.action_press(&"move_back")
	var frames := 0
	var arrest := -1
	var target := -top
	while frames < 240:
		await _tick()
		frames += 1
		var along := Vector2(player.velocity.x, player.velocity.z).dot(_forward());
		# Separate metric, and it is the one that matters. Time-to-reversed is
		# dominated by accelerating AWAY afterwards, so it stayed comfortable even
		# with the brake deleted — the body stopped dead in 0.05s and then ran back
		# normally, and nothing in the totals could see that this is precisely the
		# velocity flip §19 exists to forbid. How long the ORIGINAL motion takes to
		# be spent is the pivot, and nothing else measures it.
		if arrest < 0 and along <= top * 0.05:
			arrest = frames
		if along <= target * 0.95:
			break
	Input.action_release(&"move_back")
	Input.action_release(&"sprint")
	metrics["arrest_time"] = float(arrest) / TICK
	var elapsed := float(frames) / TICK
	metrics["turn_time"] = elapsed
	metrics["turn_speed"] = _hspeed()
	_check(
		elapsed <= 0.70,
		"a 180 reversal took %.3fs — §19 wants a brake and a pivot, not a boat turning around" % elapsed
	)
	_check(
		elapsed >= 0.12,
		"a 180 reversal took %.3fs — that is an instant velocity flip, which is what §19 exists to forbid" % elapsed
	)
	# The brake must be an EVENT with a duration, not a rounding step. Too quick
	# and the body has no way to say "I was going that way"; too slow and it is a
	# boat. This gate is blind to everything except how motion is spent.
	var arrest_sec := float(metrics["arrest_time"])
	_check(
		arrest_sec >= 0.10 and arrest_sec <= 0.45,
		"a sprint reversal spent the old motion in %.3fs (%.1f%% of the turn) — §19 wants a brake you can see, not a velocity flip hidden inside a healthy total"
			% [arrest_sec, 100.0 * arrest_sec / maxf(elapsed, 0.001)]
	)


func _measure_jump() -> void:
	await _place_at_start()
	await _wait(30)
	var rest_y := player.global_position.y
	Input.action_press(&"jump")
	var frames := 0
	var airborne := 0
	var peak := rest_y
	while frames < 240:
		await _tick()
		frames += 1
		if frames == 1:
			Input.action_release(&"jump")
		if not player.is_on_floor():
			airborne += 1
			peak = maxf(peak, player.global_position.y)
		elif airborne > 0:
			break
	var airtime := float(airborne) / TICK
	metrics["jump_airtime"] = airtime
	metrics["jump_height"] = peak - rest_y
	_check(
		airtime >= 0.35 and airtime <= 1.30,
		"jump airtime %.3fs — leaves the read either floaty or stunted" % airtime
	)


# PART I: the dodge must be a BURST — fast accelerate, peak, fast settle. The
# failure mode is not distance, it is that the body reaches full speed on frame
# one and therefore has no beginning.
func _measure_dodge() -> void:
	await _place_at_start()
	await _wait(20)
	var origin := player.global_position
	Input.action_press(&"move_forward")
	await _wait(4)
	combat.request(&"dodge")
	var frames := 0
	var peak_speed := 0.0
	var first_frame_speed := 0.0
	while frames < 200:
		await _tick()
		frames += 1
		var s := _hspeed()
		peak_speed = maxf(peak_speed, s)
		if frames == 2:
			first_frame_speed = s
		if combat.state != combat.State.DODGE and frames > 4:
			break
	Input.action_release(&"move_forward")
	var dist := Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(origin.x, origin.z)
	)
	metrics["dodge_dist"] = dist
	metrics["dodge_time"] = float(frames) / TICK
	metrics["dodge_first"] = first_frame_speed
	metrics["dodge_peak"] = peak_speed
	_check(
		dist >= 1.20 and dist <= 3.20,
		"the dodge covered %.2fm — PART I wants a genuine relocation, not a shuffle and not a teleport" % dist
	)
	_check(
		first_frame_speed < peak_speed * 0.55,
		"the dodge was already doing %.2f m/s on frame two against a %.2f m/s peak — that is a teleport, it has no acceleration to read"
			% [first_frame_speed, peak_speed]
	)


# ---------------------------------------------------------------- primitives

func _accelerate(sprint: bool) -> Dictionary:
	await _place_at_start()
	Input.action_press(&"move_forward")
	if sprint:
		Input.action_press(&"sprint")
	# Deliberately DYNAMIC: naming `CombatTuning` as a static type anywhere in a
	# test script that also instantiates the player makes Godot resolve the global
	# class while the player's own scripts are still being compiled, and the
	# preloaded tuning .tres then comes back with its script DETACHED — a plain
	# Resource, so every tuning field reads as 0 and the report is a table of
	# lies. Read through `get()` instead and the binding is never in question.
	var tune: Resource = player.tuning
	var target_speed := float(tune.get("sprint_speed" if sprint else "walk_speed"))
	var ceiling := target_speed
	var frames := 0
	while frames < 200:
		await _tick()
		frames += 1
		if _hspeed() >= ceiling * 0.95:
			break
	Input.action_release(&"move_forward")
	if sprint:
		Input.action_release(&"sprint")
	return {"time": float(frames) / TICK, "speed": _hspeed()}


func _coast(sprint: bool) -> Dictionary:
	await _place_at_start()
	Input.action_press(&"move_forward")
	if sprint:
		Input.action_press(&"sprint")
	# JUST long enough to be AT top speed and no longer. The deck is 18m and the
	# far kerb is a wall: a longer warm-up parks the body against it, and the
	# "stop" then measures the kerb rather than the legs — that failure printed a
	# perfectly confident 0.00m.
	await _wait(warm_up_frames(sprint))
	var top := _hspeed()
	Input.action_release(&"move_forward")
	if sprint:
		Input.action_release(&"sprint")
	var origin := player.global_position
	var frames := 0
	while frames < 300:
		await _tick()
		frames += 1
		if _hspeed() <= 0.12:
			break
	var dist := Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(origin.x, origin.z)
	)
	return {"distance": dist, "time": float(frames) / TICK, "top": top}


# Enough frames to be AT the ceiling, not more: past the ceiling the only thing
# accumulating is runway consumed.
func warm_up_frames(sprint: bool) -> int:
	return 50 if sprint else 40


func _place_at_start() -> void:
	var start := lane.start_position()
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.look_at_from_position(start, start + MovementLane.RUN_DIRECTION * 4.0, Vector3.UP)
	await _wait(6)


func _hspeed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _forward() -> Vector2:
	var b := player.global_basis.z
	return Vector2(-b.x, -b.z).normalized()


# Both frames: the camera runs in `_process` and the body in `_physics_process`,
# so skipping either one would let the two halves of the feel disagree.
func _tick() -> void:
	await physics_frame
	await process_frame


func _wait(frames: int) -> void:
	for i in frames:
		await _tick()


func _report() -> void:
	print("")
	print("  ── MOVEMENT METRICS ─────────────────────────────────────────")
	print("    jog      到速 %.3fs   峰值 %.2f m/s   松键滑行 %.2fm" % [
		metrics.get("jog_time", 0.0), metrics.get("jog_speed", 0.0), metrics.get("jog_stop_dist", 0.0)
	])
	print("    sprint   到速 %.3fs   峰值 %.2f m/s   松键滑行 %.2fm / %.3fs" % [
		metrics.get("sprint_time", 0.0), metrics.get("sprint_speed", 0.0),
		metrics.get("stop_dist", 0.0), metrics.get("stop_time", 0.0)
	])
	print("    turn 180 反向 %.3fs   原运动耗尽(brake) %.3fs   占转向 %.0f%%" % [
		metrics.get("turn_time", 0.0), metrics.get("arrest_time", 0.0),
		100.0 * metrics.get("arrest_time", 0.0) / maxf(metrics.get("turn_time", 0.001), 0.001)
	])
	print("    jump     滞空 %.3fs   高度 %.2fm" % [
		metrics.get("jump_airtime", 0.0), metrics.get("jump_height", 0.0)
	])
	print("    dodge    距离 %.2fm   时长 %.3fs   第2帧 %.2f → 峰值 %.2f m/s" % [
		metrics.get("dodge_dist", 0.0), metrics.get("dodge_time", 0.0),
		metrics.get("dodge_first", 0.0), metrics.get("dodge_peak", 0.0)
	])
	print("  ──────────────────────────────────────────────────────────-")
	print("")


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)
