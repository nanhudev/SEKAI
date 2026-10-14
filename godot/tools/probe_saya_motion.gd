extends SceneTree
## PROBE · DOES THE SAYA STAND STILL?
##
## ===========================================================================
## THE QUESTION
## ===========================================================================
## "刀鞘不要乱动" is a complaint no still frame can adjudicate. A scabbard that
## wanders looks correct in every one of them; what is wrong is the TRAJECTORY,
## and the trajectory is the one thing a screenshot cannot show.
##
## So this measures the three ways a held object can be wrong:
##
##   1  A JUMP. The distance the mouth travels in ONE update. A scabbard in a
##      hand has no mechanism to teleport, so a large value is a state change
##      being smuggled through the transform — the classic form being "the
##      choreographed pose stops being asked for this frame and the derived pose
##      starts being asked for". A jump is frame-rate independent: it survives
##      any dt, which is why it is the headline number.
##
##   2  WANDERING. Path walked over net displacement while the saya is supposed
##      to be HELD. A held object scores 1.0; one that visits and returns scores
##      high while never moving far, and that is exactly the picture that reads
##      as "乱动".
##
##   3  SPEED. Metres per second, so the number means the same thing whether the
##      run was 60 fps or 5000.
##
## It drives the REAL sentence through the REAL entrances — the weapon switch,
## the light chain A1→A4, and the switch-out — because the failure being hunted
## lives at the SEAM between two systems, and a hand-built pose list would have
## no seam to find.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_saya_motion.gd

const WEAPON_ROOT := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"

## For `angle_between` -- the only well-conditioned way to ask how far apart two
## rotations are. `Quaternion.angle_to` answers 0.056 degrees for a rotation
## against itself. See `SwordPoseSampler.angle_between`.
const SwordPoseSampler := preload("res://scripts/combat/sword_pose_sampler.gd")

## What counts as a teleport: the speed ceiling, expressed as the displacement one
## rendered frame at 60 Hz would show. The saya is 0.80 m long and 36 mm across,
## so 20 mm in a frame is already half its own width — visible by construction.
const JUMP_LIMIT := 0.020
const SPEED_LIMIT := JUMP_LIMIT * 60.0

## ===========================================================================
## §5'S CONTROLLED BREATHING, AS A BAND WITH TWO ENDS
## ===========================================================================
## This was `IDLE_DRIFT_LIMIT := 0.012` and a single `<` test, i.e. "while the
## blade is out the mouth must travel less than twelve millimetres". It passed,
## and then it failed at 13.2 mm -- and the failure was the GATE's, not the
## rig's. The Controlled Stillness brief does not ask for a still saya: §1 asks
## for FOLLOW THE LEFT HAND WITH CONTROLLED STABILISATION, §3 makes the left hand
## the saya's driver, and §5 gives the breathing a size -- 0.5 to 1.5 cm, 1 to 2
## degrees. §P0-1 then names "the saya is too absolutely still, it reads as a
## world-space prop" as the FIRST problem of the pass.
##
## So a one-sided ceiling was measuring the wrong thing twice over: it could not
## fail for TOO LITTLE movement, which is the defect the pass exists to fix, and
## it went red exactly when the rig started doing what it was asked.
##
## The band below is §5 quoted, and both ends are load-bearing:
##
##   below the floor   the breathing is not happening, and P0-1 is back
##   above the ceiling the hand is drifting rather than breathing
##
## Measured as the DIAMETER of the mouth's own track over the leg -- the widest
## distance between any two samples -- rather than as its path length, because a
## path length grows with how long you watch and says nothing about amplitude. A
## diameter is the excursion, and §5 is an excursion.
const BREATH_FLOOR := 0.005
const BREATH_CEIL := 0.015

## The window every speed is measured over.
##
## NOT ONE FRAME, AND THIS IS THE WHOLE INSTRUMENT. A headless renderer runs at
## whatever rate it manages and its frame times are not uniform: this run
## alternates ~15 ms and ~1 ms, and dividing one frame's displacement by that
## frame's own dt turns a perfectly smooth 0.74 m/s traverse into three
## consecutive "3-4 m/s" readings and a 21 mm "jump". Measured over the trace,
## step and dt are INVERSELY correlated, which is the signature of a jittery
## instrument rather than a jumping object.
##
## A window wider than the worst hitch averages that out, and the threshold goes
## back to meaning the thing it was chosen for. Same discipline as the loudness
## work: the short-term measurement is a fixed window, not a sample.
const SPEED_WINDOW := 0.030

## ===========================================================================
## THE CLOCK, AND WHY IT IS NOT `Time.get_ticks_usec()`
## ===========================================================================
## The first version of this probe timed each sample with the wall clock across
## an `await process_frame`, and produced three consecutive 3-4 m/s readings on a
## traverse that the authored curve caps at 0.74 m/s. Dumping the trace showed
## why: a step of 0.006 m appeared under a dt of 0.0005 s AND under a dt of
## 0.016 s, so the clock was noise and the object was smooth.
##
## This node accumulates the same `delta` the game's own `_process` receives, and
## it is added to the tree LAST so its delta is counted after the pose it belongs
## to has been written. The displacement between two samples then spans exactly
## the engine time the pose advanced over — which is the quantity the question
## is about, and the only one that is not a measurement of this script's
## scheduling.
class FrameClock extends Node:
	var total := 0.0
	func _process(delta: float) -> void:
		total += delta


var _clock: FrameClock
var _samples: Array[Dictionary] = []
var _marks: Array[Dictionary] = []
var _t := 0.0
var _last_total := 0.0
var _fails: Array[String] = []

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var manager: Node
var slot: WeaponSlot


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_geometry()

	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	_clock = FrameClock.new()
	root.add_child(_clock)
	await _frames(14)
	player = world.get_node("Player")
	combat = player.get_node("CombatController")
	slot = player.get_node("WeaponSlot")
	manager = player.get_node_or_null("WeaponManager")
	if combat.saya_rig == null or manager == null:
		print("FAIL: no saya rig or no manager")
		quit(1)
		return

	print("")
	print("── the walk · mouth in WeaponRoot space, every update")
	_last_total = _clock.total
	# THE SWORD HAS TO BE PUT AWAY FIRST or the "switch-in" leg measures nothing:
	# the sandbox starts holding the sword, so `equip_weapon(SWORD)` is a no-op
	# and the draw — the one act this probe most needs to see — never runs.
	# Timed in SECONDS, not frames: headless process frames are uncapped, so 240
	# of them is a fiftieth of a second and the sheathe takes 1.6.
	manager.call("equip_weapon", WeaponSlot.CHAIN)
	await _leg("put-away", Callable(), 2.6)
	await _leg("switch-in", func(): manager.call("equip_weapon", WeaponSlot.SWORD), 4.2)
	await _leg("idle", Callable(), 1.0)
	await _leg("a1", func(): combat.request(&"light"), 0.0)
	await _leg("idle-1", Callable(), 1.1)
	await _leg("a1-again", func(): combat.request(&"light"), 0.0)
	await _leg("idle-2", Callable(), 1.1)
	await _leg("a2", func(): combat.request(&"light"), 0.0)
	await _leg("idle-3", Callable(), 1.1)
	await _leg("a3", func(): combat.request(&"light"), 0.0)
	await _leg("idle-4", Callable(), 1.1)
	await _leg("a4", func(): combat.request(&"light"), 0.0)
	await _leg("settle", Callable(), 1.4)
	await _leg("switch-out",
		func(): manager.call("equip_weapon", WeaponSlot.CHAIN), 3.4)

	_report()
	# The clock is a node this script added, so it is a node this script has to
	# take away: the SceneTree holds the only reference to it, and quitting with
	# it still installed reports both an instance leak and a script still in use,
	# which is a probe printing errors on a clean run.
	root.remove_child(_clock)
	_clock.free()
	_clock = null
	quit(1 if not _fails.is_empty() else 0)


# ===========================================================================
# THE OFFLINE HALF · the sentence's own sheath track, read as a path
# ===========================================================================
#
# Printed before the live run, and for the same reason the live probes exist:
# a beat list is four numbers that have to be right TOGETHER, and each one looks
# reasonable on its own. What makes a track read as "乱动" is not any single
# beat — it is the SPEED between them, which nothing in the source states.
func _geometry() -> void:
	var move := SwordBasic.equip()
	if not move.has_saya_beats():
		return
	print("── the draw's two tracks, segment by segment")
	_track("BLADE ", move)
	_track("SAYA  ", move)
	var home := SwordBasic.saya_home()
	var last: Vector3 = move.saya_positions[move.saya_positions.size() - 1]
	print("   the sheath's last beat is %.4f m from the seating home (%s)"
		% [last.distance_to(home), "OK" if last.distance_to(home) < 0.002 else "IT TELEPORTS"])


## One track's segment table. The sheath's own beats and the blade's are on the
## same clock and the same walk, so they get the same instrument: what makes a
## beat list read as "乱动" is never one beat — it is the SPEED between them,
## which nothing in the source states.
func _track(label: String, move: SwordMove) -> void:
	var times := move.beat_times
	var positions := move.saya_positions if label == "SAYA  " else move.beat_positions
	var rotations := move.saya_rotations if label == "SAYA  " else move.beat_rotations
	var count := times.size()
	print("   %s %-9s %8s %7s %8s %8s" % [
		label, "window", "travel", "m/s", "aim °", "spin °"])
	var path := 0.0
	var fastest := 0.0
	var fastest_at := ""
	for i in count - 1:
		var span: float = times[i + 1] - times[i]
		var travel: float = positions[i].distance_to(positions[i + 1])
		var basis_a := Basis.from_euler(rotations[i])
		var basis_b := Basis.from_euler(rotations[i + 1])
		# TWO DIFFERENT ANGLES, and they answer two different questions.
		#
		# `aim` is the angle between where the blade/saya POINTS — the +Y the
		# Registry measures along. It is the one that decides whether a blade is
		# still travelling down its own bore, because a blade rotated out of its
		# scabbard's axis is a blade through the scabbard's wall.
		#
		# `spin` is the whole rotation, roll included. It is what the eye reads as
		# a flick, and it is much larger than `aim` whenever a pose turns the
		# EDGE without turning the blade.
		var aim := rad_to_deg((basis_a * Vector3.UP).angle_to(basis_b * Vector3.UP))
		var spin := SwordPoseSampler.angle_between(
			basis_a.get_rotation_quaternion(), basis_b.get_rotation_quaternion())
		var speed := travel / maxf(span, 0.0001)
		path += travel
		if speed > fastest:
			fastest = speed
			fastest_at = "%.2f-%.2f" % [times[i], times[i + 1]]
		print("   %s %-9s %8.3f %7.2f %8.1f %8.1f" % [
			"      ", "%.2f-%.2f" % [times[i], times[i + 1]], travel, speed, aim, spin])
	print("   %s total %.3f m · fastest segment %s at %.2f m/s" % [
		label, path, fastest_at, fastest])


# ===========================================================================
# Driving
# ===========================================================================

## Runs one leg: marks it, fires the trigger, then walks until the rig is quiet
## again (or until `seconds` is spent, for the legs that have no trigger).
func _leg(tag: String, trigger: Callable, seconds: float) -> void:
	_mark(tag)
	if trigger.is_valid():
		trigger.call()
	var deadline := _t + seconds
	while true:
		await process_frame
		_sample()
		if seconds > 0.0:
			if _t >= deadline:
				break
		elif combat.state == CombatController.State.IDLE and _t >= deadline + 0.25:
			break


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _mark(tag: String) -> void:
	_marks.append({"tag": tag, "index": _samples.size(), "t": _t,
		"pos": _mouth(), "blend": float(combat.equip_blend)})


func _sample() -> void:
	var delta := _clock.total - _last_total
	_last_total = _clock.total
	_t = _clock.total
	_samples.append({"pos": _mouth(), "dt": delta, "t": _t, "state": combat.state,
		"blend": float(combat.equip_blend)})


func _mouth() -> Vector3:
	if combat.saya_rig == null or not is_instance_valid(combat.saya_rig):
		return Vector3.ZERO
	return combat.saya_rig.mouth_point()


## The widest distance between any two positions the mouth visited over the leg —
## the EXCURSION, which is what §5 sizes, as opposed to the path length, which
## grows with how long the leg lasts.
##
## Quadratic and deliberately so: a leg is about 66 samples, so this is four
## thousand comparisons, and an approximate answer here would be an approximate
## gate.
func _diameter(from: int, to: int) -> float:
	var widest := 0.0
	for a in range(from, to):
		for b in range(a + 1, to):
			widest = maxf(widest, _samples[a]["pos"].distance_to(_samples[b]["pos"]))
	return widest


# ===========================================================================
# Verdict
# ===========================================================================

func _report() -> void:
	print("")
	print("   %-10s %8s %9s %9s %9s %9s" % ["leg", "path", "leap@60", "m/s", "hover", "span"])
	var global_at := ""
	var global_speed := 0.0
	var idle_worst := 0.0
	var idle_span := 0.0
	var idle_span_at := ""
	for i in _marks.size():
		var from: int = _marks[i]["index"]
		var to: int = _marks[i + 1]["index"] if i + 1 < _marks.size() else _samples.size()
		if to <= from:
			continue
		var tag: String = _marks[i]["tag"]
		var hover := 0.0
		var path := 0.0
		for k in range(from, to):
			hover = maxf(hover, _samples[k]["pos"].distance_to(_marks[i]["pos"]))
			if k > from:
				path += _samples[k - 1]["pos"].distance_to(_samples[k]["pos"])
		var speed := _peak_speed(from, to)
		var span := _diameter(from, to)
		print("   %-10s %8.3f %9.1f %9.2f %9.4f %9.4f" % [
			tag, path, speed / 60.0 * 1000.0, speed, hover, span])
		if speed > global_speed:
			global_speed = speed
			global_at = tag
		if tag.begins_with("idle"):
			idle_worst = maxf(idle_worst, path)
			if span > idle_span:
				idle_span = span
				idle_span_at = tag

	print("")
	_judge(global_speed < SPEED_LIMIT,
		"no rendered frame shows more than %.0f mm of travel (worst %.2f m/s = %.1f mm "
			% [JUMP_LIMIT * 1000.0, global_speed, global_speed / 60.0 * 1000.0]
		+ "at 60 Hz, during `%s`)" % global_at)
	# §5's band. The two ends are separate gates because they fail for opposite
	# reasons and the fix is opposite in each case.
	_judge(idle_span >= BREATH_FLOOR,
		"the saya is being HELD, not parked: it breathes at least %.0f mm with the "
			% (BREATH_FLOOR * 1000.0) + "blade out (`%s` spans %.1f mm)" % [
				idle_span_at, idle_span * 1000.0])
	_judge(idle_span <= BREATH_CEIL,
		"and it is breathing rather than drifting (widest span %.1f mm, limit %.0f)"
			% [idle_span * 1000.0, BREATH_CEIL * 1000.0])
	print("   (idle path length %.4f m — grows with how long you watch, so it is not"
		% idle_worst)
	print("    what §5's band is measured against; the span above is.)")

	# WHERE, exactly. A per-leg maximum says which act is wrong; only the instant
	# says WHY — an authority handover and an over-fast beat are told apart by
	# what the rig was being asked for at that moment.
	var fastest := _fastest_window()
	print("   fastest %.2f m/s at t=%.3fs · %s · blend %.3f · %s" % [
		fastest["speed"], fastest["t"], fastest["leg"], fastest["blend"],
		_state_name(fastest["state"])])
	if OS.get_environment("SAYA_TRACE") != "":
		_trace()
	else:
		print("")
		print("   set SAYA_TRACE=<leg> to dump one leg, update by update")


## The fastest the mouth travels over any `SPEED_WINDOW` of the stretch
## `[from, to)`. See `SPEED_WINDOW` for why this is a window and not a frame.
func _peak_speed(from: int, to: int) -> float:
	var peak := 0.0
	for i in range(from, to):
		var j := i + 1
		while j < to and _samples[j]["t"] - _samples[i]["t"] < SPEED_WINDOW:
			j += 1
		if j >= to:
			break
		var span: float = _samples[j]["t"] - _samples[i]["t"]
		if span <= 0.0:
			continue
		peak = maxf(peak, _samples[i]["pos"].distance_to(_samples[j]["pos"]) / span)
	return peak


## Where the fastest window is, as an instant and the pose inputs at it. A number
## without an instant is not actionable.
func _fastest_window() -> Dictionary:
	var best := {"speed": 0.0, "t": 0.0, "leg": "", "blend": 0.0, "state": 0}
	for k in _marks.size():
		var from: int = _marks[k]["index"]
		var to: int = _marks[k + 1]["index"] if k + 1 < _marks.size() else _samples.size()
		for i in range(from, to):
			var j := i + 1
			while j < to and _samples[j]["t"] - _samples[i]["t"] < SPEED_WINDOW:
				j += 1
			if j >= to:
				break
			var span: float = _samples[j]["t"] - _samples[i]["t"]
			if span <= 0.0:
				continue
			var speed: float = _samples[i]["pos"].distance_to(_samples[j]["pos"]) / span
			if speed > float(best["speed"]):
				best = {"speed": speed, "t": _samples[i]["t"],
					"leg": _marks[k]["tag"], "blend": _samples[i]["blend"],
					"state": _samples[i]["state"]}
	return best


## Which leg a sample index fell in, by the marks around it.
func _leg_of(index: int) -> String:
	var tag := "(before the first mark)"
	for m in _marks:
		if int(m["index"]) <= index:
			tag = m["tag"]
		else:
			break
	return tag


## Set `SAYA_TRACE=<leg>` to dump every update of one leg. The summary says which
## act is wrong; this says whether the answer is smooth motion or a state flip,
## and it is env-gated because a leg is several thousand lines and only ever read
## once.
func _trace() -> void:
	var want := OS.get_environment("SAYA_TRACE")
	print("")
	print("── trace · %s" % want)
	for i in range(1, _samples.size()):
		if _leg_of(i) != want:
			continue
		var step: float = _samples[i - 1]["pos"].distance_to(_samples[i]["pos"])
		print("   t=%8.4f dt=%.5f step=%.5f speed=%7.2f blend=%.4f" % [
			_samples[i]["t"], _samples[i]["dt"], step,
			step / maxf(_samples[i]["dt"], 1e-6), _samples[i]["blend"]])


func _state_name(state: int) -> String:
	var names := ["IDLE", "ATTACK", "RIPOSTE", "SKILL", "CHARGE", "BLOCK", "PARRY",
		"CAST", "DODGE"]
	return names[state] if state >= 0 and state < names.size() else str(state)


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)
