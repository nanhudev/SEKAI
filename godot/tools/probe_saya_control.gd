extends SceneTree
## PROBE · DOES THE SAYA MOVE FOR A REASON?
##
## ===========================================================================
## THE QUESTION, AND WHY IT IS THE OPPOSITE ONE FROM `probe_saya_motion.gd`
## ===========================================================================
## `probe_saya_motion.gd` asked "does the saya stand still?" and the answer came
## back "yes, to 0.0000 m", which was the right answer to Pass01 and the wrong
## answer to the game. A scabbard that never moves is not a held scabbard, it is
## a scabbard-shaped object welded to the camera. The complaint moved from
##
##   乱动   -- 0.21 m of travel per cut, following the blade
##   to
##   冻结   -- 0.00 m of travel per cut, following nothing
##
## and those two failures need ONE instrument, because the pass condition is a
## BAND and not a ceiling: the saya has to move, and it has to move a little.
##
## So this measures, per act:
##
##   1  TRAVEL. Metres of path walked, against the budget the move itself
##      authored. When a move carries `saya_ctrl_*` beats, the traveled
##      distance IS derivable from them; if the rig walks further than its own
##      data says, something is still deriving the pose from the blade.
##
##   2  SWING. Degrees of rotation, split into `aim` (where the scabbard POINTS)
##      and `spin` (the whole rotation, roll included). They are different
##      failures: a scabbard that re-points its mouth 20 deg is doing something,
##      and a scabbard that rolls 90 deg about its own axis is showing off.
##
##   3  FROZEN-ness. The floor. Every act that is supposed to be alive must
##      clear it, and the number that matters is the SMALLEST travel over the
##      whole run — because "frozen" is a property of the worst act, not the
##      average one.
##
## It drives the REAL sentence through the REAL entrances, for the same reason
## its sibling does: the fault lives at the seams.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_saya_control.gd

const WEAPON_ROOT := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"

## For `angle_between` -- the only well-conditioned way to ask how far apart two
## rotations are. `Quaternion.angle_to` answers 0.056 degrees for a rotation
## against itself. See `SwordPoseSampler.angle_between`.
const SwordPoseSampler := preload("res://scripts/combat/sword_pose_sampler.gd")

## ===========================================================================
## THE BAND (§2), AND IT HAD TO BE DERIVED RATHER THAN PICKED
## ===========================================================================
## §2 says an ordinary cut gets 2-8 cm of translation and 3-15 deg of rotation.
## Those are the thresholds, widened at the edges rather than narrowed:
##
##   FLOOR 3 mm. Deliberately BELOW §2's 2 cm, because the floor is not asking
##   "is this a §2-sized move", it is asking "is this thing alive". Idle
##   breathing (§5) is authored at 0.5-1.5 cm and a cut that has already spent
##   its control budget on a tuck can come in under 2 cm legitimately. Setting
##   the floor at 2 cm would fail honest quiet acts, and a gate that fails
##   honest work gets switched off.
##
##   CEILING 12 cm, and this one is the Pass01 regression alarm. §2's own top is
##   8 cm for ordinary cuts; past 12 cm the only thing that can produce the
##   motion is the blade, not the hand.
const TRAVEL_FLOOR := 0.003
const TRAVEL_CEIL := 0.120
## The draw and the Iaido sheathe are §2's "special actions" and are allowed
## more. They are still bounded, because "special" is not "unlimited": the
## switch-out's own beat list is the budget and it is under a third of a metre.
const TRAVEL_CEIL_SPECIAL := 0.340

## §2's special actions. The draw and the sheathe are the same beat list run in
## two directions and both are the hand CARRYING the scabbard somewhere, so both
## are in. `put-away` is the sheathe's own leg name in this probe's script.
const SPECIAL_ACTS := ["draw", "sheathe", "put-away"]

## Rotation, same shape of argument. §2's ordinary band top is 15 deg; idle
## breathing (§5) is authored at 1-2 deg, so the floor is a single degree.
##
## The ceiling is above §2's band on purpose. This probe measures the DIRECTION
## CHANGE over a whole act, which is the integral of the hand's motion and not
## any one of its offsets: a cut whose hand is asked for 5 degrees of roll at the
## mouth, through a wrist that turns and returns, accumulates more than 15 across
## the act while never being more than 5 from where §8 said it may go. 26 is
## "twice the authored budget", i.e. the point past which something is re-aiming
## the scabbard rather than working it.
##
## ===========================================================================
## AND THE CEREMONY IS EXEMPT, BECAUSE RE-AIMING IT IS THE CEREMONY
## ===========================================================================
## The draw and the sheathe DO re-point the mouth, by design and by 84.8 degrees:
## §19's beat list lifts the saya off the hip and presents it. A single ceiling
## cannot say both "a cut may not re-aim this" and "a draw must", so the special
## acts get their own -- high enough for the presentation, low enough that a
## scabbard spinning a full turn in the hand is still a failure.
const SWING_FLOOR := 0.8
const SWING_CEIL := 26.0
const SWING_CEIL_SPECIAL := 120.0

## A rendered frame may not carry the mouth more than this. Carried over
## unchanged from `probe_saya_motion.gd` — it was right there and nothing in
## Pass02 is allowed to spend it.
const JUMP_LIMIT := 0.020
const SPEED_LIMIT := JUMP_LIMIT * 60.0
## Every speed is measured over a fixed window, never one frame. See the long
## derivation in `probe_saya_motion.gd`: a headless renderer's frame times are
## not uniform and dividing by one frame's own dt turns a smooth traverse into
## a row of fake peaks.
const SPEED_WINDOW := 0.030


## The clock. The engine's own `delta`, accumulated by a node added to the tree
## LAST so it is counted after the pose it belongs to has been written.
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
	_budget()
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
	print("── the walk · every act, in WeaponRoot space")
	_last_total = _clock.total
	# The sandbox starts holding the sword, so the draw never runs unless the
	# sword is put away first. Timed in SECONDS, not frames: headless process
	# frames are uncapped and 240 of them is a fiftieth of a second.
	manager.call("equip_weapon", WeaponSlot.CHAIN)
	await _leg("put-away", Callable(), 2.6)
	await _leg("draw", func(): manager.call("equip_weapon", WeaponSlot.SWORD), 4.2)
	await _leg("idle", Callable(), 1.4)
	await _leg("a1", func(): combat.request(&"light"), 0.0)
	await _leg("idle", Callable(), 1.0)
	await _leg("a2", func(): combat.request(&"light"), 0.0)
	await _leg("idle", Callable(), 1.0)
	await _leg("a3", func(): combat.request(&"light"), 0.0)
	await _leg("idle", Callable(), 1.0)
	await _leg("a4", func(): combat.request(&"light"), 0.0)
	await _leg("idle", Callable(), 1.0)
	await _leg("sheathe",
		func(): manager.call("equip_weapon", WeaponSlot.CHAIN), 3.4)

	_report()
	root.remove_child(_clock)
	_clock.free()
	_clock = null
	quit(1 if not _fails.is_empty() else 0)


# ===========================================================================
# Offline · the authored budget
# ===========================================================================
#
# Printed first, and it is the half of the instrument that makes the live half a
# GATE rather than a reading. The rig's live travel is compared against the
# distance the move's OWN control beats imply: if the two disagree, the pose in
# the game is not the pose in the data, and no amount of looking at it will say
# so.
func _budget() -> void:
	print("── the authored budget · what each move asks of the left hand")
	print("   %-8s %9s %9s %9s" % ["move", "travel", "aim °", "spin °"])
	for entry in [["a1", SwordBasic.a1()], ["a2", SwordBasic.a2()],
			["a3", SwordBasic.a3()], ["a4", SwordBasic.a4()]]:
		_show_budget(String(entry[0]), entry[1] as SwordMove)
	_show_budget("draw", SwordBasic.equip())


func _show_budget(label: String, move: SwordMove) -> void:
	var track := _authored_track(move)
	print("   %-8s %9.4f %9.1f %9.1f" % [
		label, track["travel"], track["aim"], track["spin"]])


## The path the move's own beats imply, and the rotation along it. `travel` is
## the sum of the chords — the beats are the only thing asking for motion, and a
## straight chord between two beats is what the sampler walks.
##
## A move with no control beats returns zeroes, which is the honest answer and
## the one that makes the live half meaningful: "the data asks for nothing, so
## anything measured on screen is somebody else's motion".
func _authored_track(move: SwordMove) -> Dictionary:
	var out := {"travel": 0.0, "aim": 0.0, "spin": 0.0}
	if move == null or not move.has_saya_ctrl():
		return out
	var pos := move.saya_ctrl_positions
	for i in pos.size() - 1:
		out["travel"] = float(out["travel"]) + pos[i].distance_to(pos[i + 1])
	var rot := move.saya_ctrl_rotations
	for i in rot.size() - 1:
		var a := Basis.from_euler(rot[i])
		var b := Basis.from_euler(rot[i + 1])
		out["aim"] = maxf(float(out["aim"]),
			rad_to_deg((a * Vector3.UP).angle_to(b * Vector3.UP)))
		out["spin"] = maxf(float(out["spin"]),
			SwordPoseSampler.angle_between(a.get_rotation_quaternion(),
				b.get_rotation_quaternion()))
	return out


# ===========================================================================
# Driving
# ===========================================================================

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
		"pos": _mouth(), "basis": _basis(), "blend": float(combat.equip_blend)})


func _sample() -> void:
	var delta := _clock.total - _last_total
	_last_total = _clock.total
	_t = _clock.total
	_samples.append({"pos": _mouth(), "basis": _basis(), "dt": delta, "t": _t,
		"state": combat.state, "blend": float(combat.equip_blend)})


func _mouth() -> Vector3:
	if combat.saya_rig == null or not is_instance_valid(combat.saya_rig):
		return Vector3.ZERO
	return combat.saya_rig.mouth_point()


func _basis() -> Basis:
	if combat.saya_rig == null or not is_instance_valid(combat.saya_rig):
		return Basis.IDENTITY
	return combat.saya_rig.transform.basis


# ===========================================================================
# Verdict
# ===========================================================================

func _report() -> void:
	# The idle legs are all called "idle", so they are folded into one row: five
	# rows of the same number says "idle" five times and hides the thing worth
	# knowing, which is how far the quietest one drifted.
	print("")
	print("   %-10s %8s %8s %9s %9s %8s %8s" % [
		"act", "travel", "hover", "leap@60", "m/s", "aim °", "spin °"])
	var worst_speed := 0.0
	var worst_speed_at := ""
	var smallest_cut := {"travel": INF, "act": ""}
	var idle_travel := 0.0
	var idle_swing := 0.0
	for i in _marks.size():
		var from: int = _marks[i]["index"]
		var to: int = _marks[i + 1]["index"] if i + 1 < _marks.size() else _samples.size()
		if to <= from:
			continue
		var tag: String = _marks[i]["tag"]
		var stat := _stats(from, to)
		var speed := _peak_speed(from, to)
		print("   %-10s %8.4f %8.4f %9.1f %9.2f %8.1f %8.1f" % [
			tag, stat["travel"], stat["hover"], speed / 60.0 * 1000.0, speed,
			stat["aim"], stat["spin"]])
		if speed > worst_speed:
			worst_speed = speed
			worst_speed_at = tag
		if tag == "idle":
			idle_travel = maxf(idle_travel, float(stat["travel"]))
			idle_swing = maxf(idle_swing, float(stat["aim"]))
		else:
			if float(stat["travel"]) < float(smallest_cut["travel"]):
				smallest_cut = {"travel": stat["travel"], "act": tag}

	print("")
	_judge(worst_speed < SPEED_LIMIT,
		"no rendered frame carries the mouth more than %.0f mm (worst %.2f m/s "
			% [JUMP_LIMIT * 1000.0, worst_speed]
		+ "= %.1f mm at 60 Hz, during `%s`)" % [worst_speed / 60.0 * 1000.0,
			worst_speed_at])
	_judge(idle_travel >= TRAVEL_FLOOR,
		"with the blade out and nobody asking anything, the mouth is ALIVE: "
		+ "%.4f m of breathing and %.1f deg of sway (floor %.3f m)"
			% [idle_travel, idle_swing, TRAVEL_FLOOR])
	_judge(float(smallest_cut["travel"]) >= TRAVEL_FLOOR,
		"the quietest act (`%s`) still moves %.4f m (floor %.3f m)"
			% [smallest_cut["act"], smallest_cut["travel"], TRAVEL_FLOOR])
	_judge(float(smallest_cut["travel"]) <= TRAVEL_CEIL_SPECIAL,
		"and no act runs away: the largest is within the special-action budget")

	# THE BAND, act by act, and the ceiling is the Pass01 regression alarm.
	var worst_over := {"act": "", "travel": 0.0, "limit": 0.0}
	var worst_swing := {"act": "", "aim": 0.0, "limit": SWING_CEIL}
	for i in _marks.size():
		var from: int = _marks[i]["index"]
		var to: int = _marks[i + 1]["index"] if i + 1 < _marks.size() else _samples.size()
		if to <= from:
			continue
		var tag: String = _marks[i]["tag"]
		var stat := _stats(from, to)
		var limit := TRAVEL_CEIL_SPECIAL if tag in SPECIAL_ACTS else TRAVEL_CEIL
		if float(stat["travel"]) - limit > float(worst_over["travel"]) - float(worst_over["limit"]):
			worst_over = {"act": tag, "travel": stat["travel"], "limit": limit}
		var swing_limit := SWING_CEIL_SPECIAL if tag in SPECIAL_ACTS else SWING_CEIL
		# Measured as headroom against its own limit, the same way `travel` is,
		# so the two ceilings stay comparable and the reported act is the one
		# that came CLOSEST to failing rather than the one with the biggest
		# number. A ceremony's 84.8 degrees of 120 is 71% spent; a cut's 5.5 of 26
		# is 21%, and the cut is not the interesting one.
		if float(stat["aim"]) / swing_limit > float(worst_swing["aim"]) / float(worst_swing["limit"]):
			worst_swing = {"act": tag, "aim": stat["aim"], "limit": swing_limit}
	_judge(float(worst_over["travel"]) <= float(worst_over["limit"]),
		"every act stays inside its band (widest `%s` at %.4f m, limit %.3f)"
			% [worst_over["act"], worst_over["travel"], worst_over["limit"]])
	_judge(float(worst_swing["aim"]) <= float(worst_swing["limit"]),
		"nothing re-points the scabbard beyond its budget (widest `%s` at %.1f of %.1f deg)"
			% [worst_swing["act"], worst_swing["aim"], worst_swing["limit"]])

	var fastest := _fastest_window()
	print("   fastest %.2f m/s at t=%.3fs · `%s` · blend %.3f · %s" % [
		fastest["speed"], fastest["t"], fastest["leg"], fastest["blend"],
		_state_name(fastest["state"])])


## Travel, hover and swing over one leg. `hover` is the furthest the mouth got
## from where the leg started, which is the number that says "this act asked the
## hand to move" rather than "this act jittered in place".
func _stats(from: int, to: int) -> Dictionary:
	var travel := 0.0
	var hover := 0.0
	var aim := 0.0
	var spin := 0.0
	var start: Vector3 = _samples[from]["pos"]
	var start_basis: Basis = _samples[from]["basis"]
	for k in range(from, to):
		if k > from:
			travel += _samples[k - 1]["pos"].distance_to(_samples[k]["pos"])
		hover = maxf(hover, start.distance_to(_samples[k]["pos"]))
		var b: Basis = _samples[k]["basis"]
		aim = maxf(aim, rad_to_deg((start_basis * Vector3.UP).angle_to(b * Vector3.UP)))
		spin = maxf(spin, SwordPoseSampler.angle_between(
			start_basis.get_rotation_quaternion(), b.get_rotation_quaternion()))
	return {"travel": travel, "hover": hover, "aim": aim, "spin": spin}


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


func _state_name(state: int) -> String:
	var names := ["IDLE", "ATTACK", "RIPOSTE", "SKILL", "CHARGE", "BLOCK", "PARRY",
		"CAST", "DODGE"]
	return names[state] if state >= 0 and state < names.size() else str(state)


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)
