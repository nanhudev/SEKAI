extends SceneTree
## PROBE · DOES ANY BLADE PASS THROUGH ITS OWN SCABBARD?
##
## ===========================================================================
## THE GATE §27 AND §35-C ASK FOR, GENERALISED OFF THE DRAW
## ===========================================================================
## `probe_draw_seating.gd` answers this for the DRAW and only the draw: it gates
## its samples on `equip_blend`, which is the draw's own clock and does not exist
## during a cut. That was the right instrument for the fault it found (0.93 m of
## transverse error at the pause), and it is blind to the three cuts that put the
## blade back on the mouth every 0.2 seconds.
##
## This one gates GEOMETRICALLY, so it covers every act that seats a blade:
##
##   INSERTED   how many metres of blade lie beyond the mouth, measured along the
##              blade's own axis. Zero or less means nothing is inside.
##   TRANSVERSE the perpendicular distance from the blade's own axis LINE to the
##              saya's mouth. If the mouth is on the blade, this is zero.
##   ANGLE      the angle between the two axes. Transverse distance cannot see a
##              blade pivoting INSIDE the bore: a 0.15 deg error puts the mouth
##              on the axis and the tip 1.8 mm through the wall.
##
## and the verdict is a single sentence: **while a blade is in the scabbard, its
## axis is the scabbard's axis.** `FIT_CLEAR` is 1.75 mm; a blade 20 mm off is
## not "misaligned", it is through the wall.
##
## ===========================================================================
## WHY THE GATE IS NOT `equip_blend`
## ===========================================================================
## The state flags are the wrong shape for this question in both directions.
## `equip_blend` says "the draw is running", which is neither necessary (A3
## seats the blade three times with the equip idle) nor sufficient (Beat 5 of
## the draw is a fully-drawn blade turning 89 degrees in 0.35 s, and a gate that
## still believed it was inside would report the guard pose as the fault).
##
## "The blade is in the scabbard" is a DISTANCE. So it is measured as one:
## `inserted`, plus the mouth actually being at the blade rather than merely on
## its infinite line. The second test is what keeps a blade held a metre away,
## pointing back past the mouth, from being read as seated.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_blade_clearance.gd

const STAGE := "res://scenes/combat/CombatSandbox.tscn"
const WEAPON_ROOT_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"

const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")

## The blade's own centreline, measured off the shipped GLB. The registry carries
## the BORE's sori (16.4 mm) and says in its own header that the blade bows
## 13.1 mm the same way; two different curves made for each other.
const BLADE_SORI := 0.0131

## The budget: the two curves' mismatch plus the fit's own clearance. Quoting
## `FIT_CLEAR` alone would be quoting the clearance of a straight bore that does
## not exist. 16.4 mm of bore against 13.1 mm of blade is 3.3 mm of mismatch at
## the far end no matter how well the move is animated.
const TRANSVERSE_LIMIT := (SwordClasses.BORE_SORI - BLADE_SORI) + SwordClasses.FIT_CLEAR

## A blade pivoting inside the bore spends the clearance at its TIP, so the
## angle allowance shrinks with how much blade is in there: `sin(a) * inserted`
## has to stay inside one clearance.
const ANGLE_LIMIT_PER_METRE := SwordClasses.FIT_CLEAR

## Below this much blade beyond the mouth the blade is out and the constraint
## does not apply. 10 mm is a third of the scabbard's own outer width.
const MIN_INSERTED := 0.010

## ...AND THE MOUTH HAS TO BE AT THE BLADE AT ALL. `inserted` is measured along
## the blade's own axis, so a blade held at arm's length and pointing back past
## the mouth scores a large `inserted` while being nowhere near the scabbard.
## This is the test that says the blade is actually in the neighbourhood, and it
## is generous on purpose: three times the scabbard's outer width. Everything
## inside it is judged by the real limit above, so this can only ever exclude
## gross misses.
const ENGAGED := 0.060

const DT := 1.0 / 60.0


var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var manager: Node
var slot: WeaponSlot
var visual: Node3D

## One entry per act: {tag, samples}. Kept grouped rather than flat so the
## verdict can name the act that failed instead of a timestamp.
var _acts: Array[Dictionary] = []
var _current: Array[Dictionary] = []
var _fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load(STAGE)
	world = scene.instantiate()
	root.add_child(world)
	for _i in 14:
		await physics_frame
	player = world.get_node("Player")
	combat = player.get_node("CombatController")
	manager = player.get_node("WeaponManager")
	slot = player.get_node("WeaponSlot")
	var weapon_root: Node3D = player.get_node(WEAPON_ROOT_PATH)
	visual = weapon_root.get_node_or_null("TempSwordVisual") as Node3D
	if combat.saya_rig == null or visual == null:
		print("FAIL: no saya rig or no sword visual in this stage")
		quit(1)
		return

	var reach := SwordClasses.blade_reach(_weapon_id())
	print("")
	print("── the numbers this probe's limits come from")
	print("   FIT_CLEAR %.5f m · SAYA_WALL %.5f m · sori mismatch %.5f m · limit %.5f m"
		% [SwordClasses.FIT_CLEAR, SwordClasses.SAYA_WALL,
			SwordClasses.BORE_SORI - BLADE_SORI, TRANSVERSE_LIMIT])
	print("   blade_reach %.3f m · saya_body %.3f m"
		% [reach, SwordClasses.saya_body_len(_weapon_id())])

	# A sandbox hands the player the sword already drawn, so the draw has to be
	# run the way a weapon switch runs it: away to the chain, and back.
	manager.call("equip_weapon", slot.CHAIN)
	await _act("sheathe", Callable(), 2.4)
	await _act("draw", Callable(manager, "equip_weapon").bind(slot.SWORD), 3.0)
	# Every cut, from the stance the draw leaves the sword in. A1 starts on the
	# mouth, so the touch is measured on the act that owns it.
	await _act("a1", Callable(combat, "request").bind(&"light"), 0.0)
	await _act("a2", Callable(combat, "request").bind(&"light"), 0.0)
	await _act("a3", Callable(combat, "request").bind(&"light"), 0.0)
	await _act("a4", Callable(combat, "request").bind(&"light"), 0.0)
	await _act("settle", Callable(), 0.8)
	await _act("sheathe", Callable(manager, "equip_weapon").bind(slot.CHAIN), 3.0)

	_report()
	quit(1 if not _fails.is_empty() else 0)


func _weapon_id() -> StringName:
	var id := StringName(slot.get("weapon_id")) if slot.get("weapon_id") != null else &""
	return SwordBasic.WEAPON_ID if id == &"" or id == &"chain" else id


# ===========================================================================
#  DRIVING
# ===========================================================================

## One act: fire the trigger, then record every physics frame until the deadline.
## A zero `seconds` means "until the controller goes quiet", which is what the
## cuts need — their length is the move's own and a fixed window would either
## truncate A3 or spend most of its samples on the tail.
func _act(tag: String, trigger: Callable, seconds: float) -> void:
	_current = []
	if trigger.is_valid():
		trigger.call()
	var until := float(Time.get_ticks_msec()) + seconds * 1000.0
	while true:
		await physics_frame
		_current.append(_read())
		if seconds > 0.0:
			if float(Time.get_ticks_msec()) >= until:
				break
		elif combat.state == CombatController.State.IDLE \
				and _current.size() > 8:
			break
	_acts.append({"tag": tag, "samples": _current})


# ===========================================================================
#  THE GEOMETRY
# ===========================================================================
#
# Everything is in `WeaponRoot` space: it is the frame both actors are authored
# in, and the visual node's own transform IS that space.
func _read() -> Dictionary:
	var saya := combat.saya_rig
	var mouth: Vector3 = saya.transform.origin
	var saya_axis: Vector3 = saya.transform.basis * Vector3.UP
	var origin: Vector3 = visual.position
	var blade_axis: Vector3 = Basis.from_euler(visual.rotation) * Vector3.UP

	var out := _measure(mouth, saya_axis, origin, blade_axis)
	out["state"] = combat.state

	# =====================================================================
	# AND THE SAME MEASUREMENT ON THE AUTHORED POSE, WITHOUT THE OFFSET LAYER
	# =====================================================================
	#
	# `TempSwordVisual` draws `pose_position + _loc_offset + _contact_offset`
	# and `pose_rotation + _loc_rotation + _contact_rotation`. The first pair is
	# the authored beat list; the second pair is the locomotion / contact
	# deflection layer, which exists so a sprinting or landing body drags the
	# blade with it.
	#
	# Both layers are on the node the player sees, so the rendered number is the
	# one §27 is about and the one the verdict uses. But they have different
	# owners: a dirty pose is a beat list to re-author, and a clean pose under a
	# dirty render is an OFFSET LAYER that forgot it is not allowed to move a
	# blade that is inside a 1.75 mm tube. Reporting one number cannot tell those
	# apart, and they need opposite fixes -- so the probe reports both.
	#
	# Read through `Object.get()` rather than typed, because the offset layer is
	# `TempSwordVisual`'s private business and a probe that hard-depends on it
	# stops compiling the day the node is swapped. A node that does not have
	# them simply reports the same numbers twice, which is the harmless answer.
	var pp = visual.get("pose_position")
	var pr = visual.get("pose_rotation")
	if pp is Vector3 and pr is Vector3:
		var posed := _measure(mouth, saya_axis, pp as Vector3,
			Basis.from_euler(pr as Vector3) * Vector3.UP)
		out["pose_transverse"] = posed["transverse"]
		out["pose_angle"] = posed["angle"]
		out["pose_inserted"] = posed["inserted"]
	# How much rider layer is still on a seated blade, and where the two axes
	# disagree about where the mouth is. Either can be the reason the rendered
	# number is worse than the pose, and they are one line apart in the driver.
	out["rider"] = _rider()
	out["mouth_rest"] = mouth.distance_to(SwordBasic.saya_home(_weapon_id()))
	# ...AND THE TWO WAYS THE SAYA ITSELF CAN BE WRONG, which are one line apart
	# in `seat_home()` and need opposite fixes: translated off its base, or
	# TILTED off the bore. A translated scabbard costs the blade its clearance in
	# proportion to the offset; a tilted one costs it in proportion to how much
	# blade is in there.
	var hand: Node3D = combat.saya_hand
	if hand != null and is_instance_valid(hand):
		out["hand_off"] = hand.position.distance_to(
			SwordBasic.saya_home(_weapon_id()))
		out["saya_tilt"] = rad_to_deg(saya_axis.angle_to(
			SwordBasic.bore_axis(_weapon_id())))
	# WHICH MOVE IS ACTUALLY RUNNING, and on which clock. The act's tag is what
	# this probe ASKED for; the combo chain is what it got, and the two are not
	# the same statement -- a request that lands outside the combo window starts
	# the chain over at A1, and then the report blames a move that never ran.
	var mv = combat.get("active_move")
	out["move"] = String(mv.id) if mv != null else "-"
	# The last solve: what the pose was aimed at, and how much of it was let
	# through. `targ` on the bore with `follow` below 1 means the filter put the
	# blade through the wall; `targ` off the bore means the beats did.
	var tp = visual.get("dbg_target_position")
	var tr = visual.get("dbg_target_rotation")
	var fl = visual.get("dbg_follow")
	if tp is Vector3 and tr is Vector3:
		var t_axis := Basis.from_euler(tr as Vector3) * Vector3.UP
		var t_along: Vector3 = mouth - (tp as Vector3)
		var t_depth := t_along.dot(t_axis)
		out["targ"] = (t_along - t_axis * t_depth).length()
		out["lag"] = (pp as Vector3).distance_to(tp as Vector3) if pp is Vector3 else -1.0
	if fl is float:
		out["follow"] = fl
	return out


## The rider layers' own magnitudes, read off the node that owns them.
func _rider() -> float:
	var off = visual.get("_loc_offset")
	var con = visual.get("_contact_offset")
	var total := Vector3.ZERO
	if off is Vector3:
		total += off as Vector3
	if con is Vector3:
		total += con as Vector3
	return total.length()


## The geometry, once, for whichever pair of axes is handed to it.
func _measure(mouth: Vector3, saya_axis: Vector3, origin: Vector3,
		blade_axis: Vector3) -> Dictionary:
	var along: Vector3 = mouth - origin
	var depth := along.dot(blade_axis)
	var transverse := (along - blade_axis * depth).length()
	# A blade rotated 180 degrees in the bore is still in the bore, and reporting
	# that as a 180 degree fault would make the one number this probe exists for
	# unreadable. The axis is a LINE.
	var angle := rad_to_deg(blade_axis.angle_to(saya_axis))
	if angle > 90.0:
		angle = 180.0 - angle
	var reach := SwordClasses.blade_reach(_weapon_id())
	return {
		"inserted": reach - depth,
		"depth": depth,
		"transverse": transverse,
		"angle": angle,
		"reach": reach,
		"origin": origin,
		"tip": origin + blade_axis * reach,
		"mouth": mouth,
	}


## Whether this sample is one the constraint applies to. See `MIN_INSERTED` and
## `ENGAGED`.
func _seated(s: Dictionary) -> bool:
	if float(s["inserted"]) <= MIN_INSERTED:
		return false
	# The mouth may not sit BEHIND the grip: a blade held tip-toward the player
	# with the mouth behind their hand is a miss, not a seating.
	if float(s["depth"]) < -SwordClasses.FIT_CLEAR:
		return false
	return float(s["transverse"]) <= ENGAGED


# ===========================================================================
#  VERDICT
# ===========================================================================

func _report() -> void:
	print("")
	print("   %-9s %6s %10s %10s %9s %10s %11s" % [
		"act", "n", "inserted", "transverse", "angle", "tip error", "pose-only"])
	var worst_t := 0.0
	var worst_tip := 0.0
	var worst_pose := 0.0
	var tightest := 90.0
	var worst_act := ""
	var seated_total := 0
	for act in _acts:
		var tag: String = act["tag"]
		var n := 0
		var best_inserted := 0.0
		var a_t := 0.0
		var a_angle := 0.0
		var a_tip := 0.0
		var a_pose := 0.0
		var tight := 90.0
		for s in act["samples"]:
			if not _seated(s):
				continue
			n += 1
			seated_total += 1
			var out_len := maxf(float(s["inserted"]), 0.0)
			best_inserted = maxf(best_inserted, out_len)
			a_t = maxf(a_t, float(s["transverse"]))
			a_angle = maxf(a_angle, float(s["angle"]))
			a_tip = maxf(a_tip, sin(deg_to_rad(float(s["angle"]))) * out_len)
			a_pose = maxf(a_pose, float(s.get("pose_transverse", 0.0)))
			tight = minf(tight, rad_to_deg(asin(clampf(
				ANGLE_LIMIT_PER_METRE / maxf(out_len, 0.0001), 0.0, 1.0))))
		print("   %-9s %6d %10.3f %10.4f %9.3f %10.4f %11.4f" % [
			tag, n, best_inserted, a_t, a_angle, a_tip, a_pose])
		if a_t > worst_t:
			worst_t = a_t
			worst_act = tag
			# The blame belongs to the act that set the worst, not to the worst
			# act in the file: `a1` can be clean as authored while `a3` is not,
			# and a global max would report the other one's number.
			worst_pose = a_pose
		worst_tip = maxf(worst_tip, a_tip)
		tightest = minf(tightest, tight)

	print("")
	print("   %d seated samples across %d acts" % [seated_total, _acts.size()])
	if seated_total == 0:
		print("FAIL: no act put a blade in the scabbard at all — the gate never ran")
		_fails.append("nothing was seated")
		return
	_judge(worst_t < TRANSVERSE_LIMIT,
		"while a blade is in the scabbard the mouth is on its axis to within "
		+ "%.4f m (worst %.4f m, during `%s`%s)" % [
			TRANSVERSE_LIMIT, worst_t, worst_act, _blame(worst_pose)])
	_judge(worst_tip < TRANSVERSE_LIMIT,
		"and no part of it leaves the bore (worst tip error %.4f m)" % worst_tip)
	_judge(tightest >= 0.0,
		"the axis allowance is never spent (tightest %.3f deg of clearance)"
			% tightest)

	# Set CLEARANCE_TRACE=<act> to dump one act sample by sample. The summary
	# says WHICH act is wrong; only the trace says whether the blade is really
	# entering the scabbard crooked or merely passing near it, and those two need
	# opposite fixes.
	var want := OS.get_environment("CLEARANCE_TRACE")
	if want != "":
		_trace(want)
	else:
		print("")
		print("   set CLEARANCE_TRACE=<act> to dump one act, sample by sample")


## Which layer owns the fault. A pose that is already clean means the beat list
## is right and the offset layer moved a seated blade; a pose that is dirty too
## means the beat list itself has to be re-authored. Printed rather than judged,
## because "the pose is clean" is not a pass -- the rendered blade is what the
## player sees and what the limit above is about.
func _blame(worst_pose: float) -> String:
	if worst_pose <= 0.0:
		return ""
	if worst_pose >= TRANSVERSE_LIMIT:
		return ", and the authored pose is dirty too: re-author the beats"
	return ", pose alone is clean (%.4f m): the offset layer did it" % worst_pose


func _trace(want: String) -> void:
	for act in _acts:
		if String(act["tag"]) != want:
			continue
		print("")
		print("── trace · %s" % want)
		print("   %7s %9s %9s %9s %10s %9s %9s %9s %9s %8s %-8s %8s" % [
			"t", "depth", "insert", "transv", "angle", "pose", "rider",
			"lag", "targ", "follow", "move", "sayaTilt"])
		var i := 0
		for s in act["samples"]:
			i += 1
			var flag := "  *" if _seated(s) else ""
			print("   %7.4f %9.3f %9.3f %9.4f %10.3f %9.4f %9.4f %9.4f %9.4f %8.4f %-8s %8.3f%s" % [
				float(i) * DT, float(s["depth"]), float(s["inserted"]),
				float(s["transverse"]), float(s["angle"]),
				float(s.get("pose_transverse", -1.0)), float(s.get("rider", -1.0)),
				float(s.get("lag", -1.0)), float(s.get("targ", -1.0)),
				float(s.get("follow", -1.0)), String(s.get("move", "?")),
				float(s.get("saya_tilt", -1.0)), flag])


func _v3(p: Vector3) -> String:
	return "(%+.3f,%+.3f,%+.3f)" % [p.x, p.y, p.z]


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)
