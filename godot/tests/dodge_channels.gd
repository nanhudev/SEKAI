extends SceneTree
# PART J §27-§32, applied to the dodge.
#
# The sword had to answer swing / contact / enemy / recovery as four things. A
# dodge is the same sentence told about the body instead of the blade: LEAVE /
# TRAVEL / ARRIVE / SETTLE, and it has to be possible to tell them apart. It is
# also the one defensive act in the game that is a RELOCATION, which means it
# carries the player's whole sense of where they are — and a relocation the
# player cannot see happen is a teleport with extra steps.
#
#   A. THE FOUR MOMENTS  §27  the pose must move through the dodge, not sit at
#                             one offset for its whole duration.
#   B. DIRECTION         §32  left and right must be different answers, not the
#                             same shrug mirrored by the body's velocity alone.
#   C. THE EVADE ANSWER  §30  getting out of the way of something must read as
#                             having got out of the way of something.
#   D. THE SETTLE        §31  the dodge has to give the pose back.
#
# Stepped by hand on a fixed delta for the same reason the sword rig is: the
# pose driver is an exponential lag on a delta that jitters, so two identical
# dodges disagree on the fastest part of the move by about as much as the effect
# being looked for. See sword_feel_channels.gd for the full argument.

const STEP := 1.0 / 60.0

var world: Node3D
var player: CharacterBody3D
var lane: MovementLane
var combat: CombatController
var weapon: Node3D
var feedback: CameraFeedbackController
var failures: Array[String] = []
var metrics: Dictionary = {}
var check_log: Array[String] = []

var _pose_prev := Vector3.ZERO
var _evaded := false


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
	# Collaborators BEFORE the player: @onready resolves the instant the player
	# enters the tree, and a rig that forgets one gets a controller whose
	# `time_effects` is null — every request for a time stop then reads exactly
	# like "this build has no time stops".
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
	feedback = player.get_node("CameraFeedbackController")
	player.unlimited_resources = true

	await _measure_four_moments()
	await _measure_direction()
	await _measure_evade_answer()
	await _measure_settle()

	_report()


# ------------------------------------------------------- A. the four moments

# One pose for the whole dodge is a teleport wearing a duration: the player is
# told they moved 2m in 0.36s and shown the same sword the entire way. What has
# to be true is that the hands DO something — they leave, they are dragged along
# by the body, they arrive, and they come back.
func _measure_four_moments() -> void:
	var run := await _dodge_run(Vector2(0.0, 0.0))
	var samples: Array = run["samples"]
	if samples.size() < 8:
		_fail("the dodge lasted %d frames — nothing below can be read from that" % samples.size())
		return
	var rest: Vector3 = run["rest"]
	# Departure measured against the pose it LEFT, not against idle: the rig has
	# to say what "moved" means before it can say how much.
	var travel: Array[float] = []
	for s in samples:
		travel.append((s as Vector3).distance_to(rest))
	var peak := 0.0
	var peak_at := 0
	for i in travel.size():
		if travel[i] > peak:
			peak = travel[i]
			peak_at = i
	var end_gap: float = travel[travel.size() - 1]
	var start_gap: float = travel[0]
	metrics["dodge_peak_departure"] = peak
	metrics["dodge_peak_at_frame"] = peak_at
	metrics["dodge_frames"] = travel.size()
	metrics["dodge_end_gap"] = end_gap
	metrics["dodge_start_gap"] = start_gap
	print("  [dodge samples] " + _spark(travel))

	_check(
		peak >= 0.05,
		"the hands never leave: the biggest departure from rest across the whole dodge is %.4fm — §27: a relocation the player cannot see is a teleport"
			% peak
	)
	# The peak has to be INSIDE the dodge. A pose that jumps out on frame one
	# and stays there is a snap, and a pose that is still leaving when the dodge
	# ends never arrived.
	_check(
		peak_at >= 1 and peak_at <= travel.size() - 3,
		"the peak departure lands on frame %d of %d — a pose that is already fully out on the first frame is a snap, and one still leaving on the last frame never arrived"
			% [peak_at, travel.size()]
	)
	# And the shape has to be a curve, not a step: the first and last frames
	# must both be closer to rest than the peak is, or there is no LEAVE and no
	# ARRIVE, only a moved position held for a while.
	#
	# The end is held to a quarter of the peak, not three quarters. Three
	# quarters was enough to fail the pose this test was written for — one
	# offset held all the way to the last frame — but it also waves through a
	# pose that only *partly* comes home, which is the same defect wearing a
	# smaller number. "Home before the state ends" is the claim, so home is what
	# is asked for.
	_check(
		start_gap < peak * 0.75 and end_gap < peak * 0.25,
		"the pose is %.4fm out on the first frame and %.4fm out on the last, against a %.4fm peak — that is one offset held for the duration, which has no departure and no arrival in it"
			% [start_gap, end_gap, peak]
	)
	# NO TELEPORTING INSIDE THE DODGE. A pose that ramps out and then steps home
	# in a single frame satisfies every claim above — the peak is inside, the
	# ends are close to rest — and is the exact thing these four moments exist to
	# forbid: the player sees one sword, then another. The whole point of
	# measuring the path is that the path is what the player watches.
	var hop := 0.0
	var hop_at := 0
	for i in samples.size() - 1:
		var d: float = (samples[i + 1] as Vector3).distance_to(samples[i] as Vector3)
		if d > hop:
			hop = d
			hop_at = i + 1
	metrics["dodge_biggest_hop"] = hop
	# 45%, and the reason it is not 10% is that the LEAVE is supposed to be fast:
	# a dodge is a burst, so the hands are allowed to snap out of rest. What this
	# forbids is a step — a pose that is fully out and then simply appears
	# somewhere else, which measured as a step is over 100% of the peak (the
	# whole displacement arriving in one frame) and reads as two swords with a
	# gap in between.
	_check(
		hop < peak * 0.45,
		"the biggest single-frame move inside the dodge is %.4fm on frame %d, against a %.4fm peak departure — the hands jump rather than travel, so what the player sees is two poses with a gap in between, not a dodge"
			% [hop, hop_at, peak]
	)


# -------------------------------------------------------------- B. direction

# Dodging left and dodging right are two different decisions and the hands have
# to be part of telling them apart. The body's velocity already differs; if the
# sword does not, the only thing that moved is a number.
func _measure_direction() -> void:
	var left := await _dodge_run(Vector2(-1.0, 0.0))
	var right := await _dodge_run(Vector2(1.0, 0.0))
	var l: Array = left["samples"]
	var r: Array = right["samples"]
	var span := mini(l.size(), r.size())
	var worst := 0.0
	for i in span:
		worst = maxf(worst, (l[i] as Vector3).distance_to(r[i] as Vector3))
	metrics["dodge_side_divergence"] = worst
	_check(
		worst >= 0.04,
		"a dodge to the left and a dodge to the right put the hands at most %.4fm apart — §32: direction is its own channel, and right now only the body knows which way it went"
			% worst
	)


# ---------------------------------------------------------- C. the evade answer

# Getting out of the way of something is the one defensive act that is also an
# EVENT, and an event with no answer did not happen. Compare it with the sword:
# a swing that met nothing had to read as a miss, and the same rule applies
# here — a hit that passed through the space the player just left has to say so.
func _measure_evade_answer() -> void:
	var effects = combat.time_effects
	if effects == null:
		_fail("no TimeEffectManager in reach, so nothing about time can be claimed here")
		return
	await _wait_until_idle()
	combat.request(&"dodge")
	await _wait(2)
	effects.reset()
	var trauma_before: float = feedback.trauma
	var landed_before: int = combat.dodges_landed
	var stop := 0.0
	# Recorded on the RIG, not in a local. A GDScript lambda captures its
	# enclosing scope BY VALUE, so `answered = true` inside one is invisible out
	# here and every evade reads as "never said so" — the signal fires and the
	# test swears it did not. The controller's own counter is read as well,
	# because a number on the object cannot be captured wrongly.
	_evaded = false
	if combat.has_signal("dodge_evaded"):
		combat.dodge_evaded.connect(func() -> void: _evaded = true)
	else:
		_fail("the controller has no dodge_evaded signal, so nothing downstream can ever know a hit was avoided")
	if combat.state == CombatController.State.DODGE:
		stop = _hitstop_seconds(func() -> void:
			combat._on_player_hit({"damage": 20.0, "poise_damage": 20.0})
		)
		var trauma_after: float = feedback.trauma
		metrics["evade_hitstop"] = stop
		metrics["evade_trauma"] = trauma_after - trauma_before
		metrics["evade_signalled"] = _evaded
		metrics["evade_counted"] = combat.dodges_landed - landed_before
		_check(
			combat.dodges_landed > landed_before,
			"an evade happened and the controller did not count it (dodges_landed stayed at %d) — a stat that only counts presses is not a stat about dodging" % landed_before
		)
		_check(
			_evaded,
			"a hit passed through the space the player had just left and the controller never said so — §30: the dodge has to answer, or the player cannot tell an evade from a whiff"
		)
		_check(
			stop > 0.0 or trauma_after > trauma_before + 0.001,
			"the evade produced no time and no camera (hitstop %.3f, trauma +%.4f) — it is invisible, and an invisible success is a failure the player will not notice until they stop dodging"
				% [stop, trauma_after - trauma_before]
		)
	else:
		_fail("the dodge never entered DODGE state, so the evade was never offered")
	await _wait(30)


# ----------------------------------------------------------------- D. settle

# The dodge ends. The hands have to come back, and they have to come back
# without a snap — the moment after a dodge is when the player decides what to
# do next, and a sword that teleports home steals the frame they decide on.
func _measure_settle() -> void:
	var run := await _dodge_run(Vector2(0.0, 0.0))
	var tail: Array = run["tail"]
	var rest: Vector3 = run["rest"]
	if tail.size() < 10:
		_fail("no tail was captured after the dodge, so the settle cannot be measured")
		return
	var first: float = (tail[0] as Vector3).distance_to(rest)
	var last: float = (tail[tail.size() - 1] as Vector3).distance_to(rest)
	var biggest_step := 0.0
	for i in tail.size() - 1:
		biggest_step = maxf(biggest_step, (tail[i + 1] as Vector3).distance_to(tail[i] as Vector3))
	metrics["dodge_settle_from"] = first
	metrics["dodge_settle_to"] = last
	metrics["dodge_settle_step"] = biggest_step
	_check(
		last < 0.03,
		"the hands were still %.4fm from rest %d frames after the dodge ended — §31: the recovery is where weight lives, and a pose that never comes home is a pose the player cannot act from"
			% [last, tail.size()]
	)
	_check(
		biggest_step < 0.05,
		"the biggest single-frame hop on the way home was %.4fm — a pose that snaps back is a cut, not a settle"
			% biggest_step
	)


# ------------------------------------------------------------------- the run

# One dodge, stepped by hand, with the pose sampled every frame.
func _dodge_run(wish: Vector2) -> Dictionary:
	await _wait_until_idle()
	_set_wish(wish)
	await _wait(2)
	var rest := weapon.position
	_pose_prev = rest
	combat.set_process(false)
	weapon.set_process(false)
	player.set_physics_process(false)
	feedback.set_process(false)
	var samples: Array[Vector3] = []
	combat.request(&"dodge")
	for _i in 40:
		_step()
		if combat.state != CombatController.State.DODGE and samples.size() > 2:
			break
		samples.append(weapon.position)
	var tail: Array[Vector3] = []
	for _i in 30:
		_step()
		tail.append(weapon.position)
	combat.set_process(true)
	weapon.set_process(true)
	player.set_physics_process(true)
	feedback.set_process(true)
	await _wait_until_idle()
	return {"samples": samples, "tail": tail, "rest": rest}


func _step() -> void:
	_pose_prev = weapon.position
	combat._process(STEP)
	weapon._process(STEP)


# The rig has no keyboard, so the wish vector is written where production reads
# it. Poking the controller's private state would test a rig, not the game.
func _set_wish(wish: Vector2) -> void:
	var actions := {
		"move_left": wish.x < -0.1, "move_right": wish.x > 0.1,
		"move_forward": wish.y < -0.1, "move_back": wish.y > 0.1,
	}
	for name in actions:
		Input.action_press(name) if actions[name] else Input.action_release(name)


func _wait_until_idle() -> void:
	for _i in 200:
		if combat.state == CombatController.State.IDLE:
			return
		await physics_frame


# Read, record, reset — the hitstop is never allowed to run, because waiting
# inside one slows the waiting too.
func _hitstop_seconds(action: Callable) -> float:
	var effects = combat.time_effects
	effects.reset()
	action.call()
	var left: int = effects.effect_end_ms - Time.get_ticks_msec()
	effects.reset()
	return maxi(left, 0) / 1000.0


# A dodge's whole shape in one line, so a regression is visible without reading
# a table. Worth more than the numbers when the numbers are all zero.
func _spark(values: Array) -> String:
	var glyphs := " .:-=+*#%@"
	var peak := 0.0001
	for v in values:
		peak = maxf(peak, float(v))
	var out := ""
	for v in values:
		var i := int(clampf(float(v) / peak, 0.0, 0.999) * (glyphs.length() - 1))
		out += glyphs.substr(i, 1)
	return out


# ------------------------------------------------------------------- reporting

func _check(condition: bool, reason: String) -> void:
	if condition:
		return
	failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)


func _report() -> void:
	print("")
	print("DODGE · FOUR-MOMENT READOUT")
	print("  A moments      peak departure %.4fm at frame %d of %d (start %.4fm, end %.4fm)"
		% [
			metrics.get("dodge_peak_departure", 0.0), int(metrics.get("dodge_peak_at_frame", -1)),
			int(metrics.get("dodge_frames", 0)), metrics.get("dodge_start_gap", 0.0),
			metrics.get("dodge_end_gap", 0.0),
		])
	print("  B direction    left vs right hands apart %.4fm" % metrics.get("dodge_side_divergence", 0.0))
	print("  C evade        hitstop %.3f · trauma +%.4f · signalled %s · counted %d"
		% [
			metrics.get("evade_hitstop", 0.0), metrics.get("evade_trauma", 0.0),
			metrics.get("evade_signalled", false), int(metrics.get("evade_counted", 0)),
		])
	print("  D settle       %.4fm -> %.4fm · biggest hop %.4fm"
		% [
			metrics.get("dodge_settle_from", 0.0), metrics.get("dodge_settle_to", 0.0),
			metrics.get("dodge_settle_step", 0.0),
		])
	print("")
	if failures.is_empty():
		print("PASS: the dodge leaves, travels, arrives and settles, and says so when it works")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
