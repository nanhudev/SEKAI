extends SceneTree
## PROBE · IS THE BLADE IN THE BORE WHILE IT IS INSIDE THE SCABBARD?
##
## ===========================================================================
## THE QUESTION, AND WHY NOTHING ALREADY ASKED IT
## ===========================================================================
## `probe_saya_motion.gd` measures the SAYA: where its mouth is, how fast it
## travels, whether it teleports. `probe_draw_beats.gd` measures the SWORD: how
## far the grip travels, how many degrees the wrist turns, whether the beat list is
## self-consistent. Both pass.
##
## Neither measures THE RELATIONSHIP, and the relationship is the only one of the
## three the player can see. A draw is two objects and one constraint:
##
##      while any of the blade is inside the scabbard,
##      the blade's axis IS the scabbard's axis.
##
## That constraint is not a taste. `SwordClasses.FIT_CLEAR` is 1.75 mm — the gap
## the registry is dimensioned around — and `SAYA_WALL` is 3.2 mm of wall in front
## of it. A blade whose axis is 20 mm off the bore is not "slightly misaligned", it
## is a blade through the wall of its own scabbard; and because the scabbard is
## 36 mm across and dark, the frame it happens in reads as a shadow rather than as
## a fault. That is why the delivery clip found it and seven green probes did not.
##
## ===========================================================================
## THE THREE NUMBERS
## ===========================================================================
##   1  TRANSVERSE. The perpendicular distance from the blade's own axis LINE to
##      the saya's mouth. If the mouth is on the blade, this is zero. It is the
##      headline number, and it is the one a clearance is a limit on.
##
##   2  AXIS ANGLE. The angle between the blade's +Y and the saya's +Y. Transverse
##      distance alone cannot see a blade pivoting INSIDE the bore: a 0.15 degree
##      error puts the mouth on the axis and the tip 1.8 mm through the wall. So
##      the two are measured together and the allowance shrinks with how much
##      blade is actually in there.
##
##   3  MOUTH DEPTH. Where the mouth falls along the blade's own axis, measured
##      from the grip. Diagnostic, not a limit: it is what tells "the blade is
##      out" apart from "the blade is in and crooked" once number 1 has said
##      which of the two is happening, and it is the input the axis allowance
##      scales with.
##
## Read from the node the RENDERER moves, not from the pose sampler: the sampler's
## answer is one of the things between the sentence and the frame, and what is
## being judged here is the frame.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_draw_seating.gd

const STAGE := "res://scenes/combat/CombatSandbox.tscn"
const WEAPON_ROOT_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"

const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")

## The blade's own centreline, measured off the shipped GLB by
## `tools/measure_saya_curve.gd`. The registry carries the BORE's sori
## (`SwordClasses.BORE_SORI`, 16.4 mm) and says in its own header that the blade
## bows 13.1 mm the same way; the two curves were made for each other, which
## means they are still two different curves.
const BLADE_SORI := 0.0131

## THE BUDGET IS THE TWO CURVES PLUS THE CLEARANCE, and quoting `FIT_CLEAR` alone
## would be quoting the clearance of a straight bore that does not exist.
##
## A rigid blade in a curved tube can be on the centreline at one point and
## nowhere else: 16.4 mm of bore against 13.1 mm of blade is **3.3 mm** of
## mismatch at the far end no matter how well the draw is animated, and the draw
## spends its `SwordMove.beat_bows` against exactly that. Above the mismatch
## there is the fit's own 1.75 mm, so this is the distance at which a blade is
## unambiguously OUTSIDE its own scabbard rather than inside it with the shape the
## assets actually have.
##
## It is deliberately looser than what the rig now achieves, so it is not a
## threshold fitted to a result: the run prints the measured value next to it.
const TRANSVERSE_LIMIT := (SwordClasses.BORE_SORI - BLADE_SORI) + SwordClasses.FIT_CLEAR

## A blade pivoting inside the bore spends the clearance at its TIP, not at the
## mouth: at `inserted` metres in, `sin(angle) * inserted` is how far off the axis
## the far end has drifted. Expressed as the angle that spends one clearance per
## metre, so the test scales it by the actual insertion instead of inventing a
## second constant.
const ANGLE_LIMIT_PER_METRE := SwordClasses.FIT_CLEAR

## The equip's own beats, normalised onto the blend (1.40/1.75 = 0.80 is the
## instant the blade clears the mouth), so the report is a table of the beats the
## draw is authored in rather than of the frames a machine happened to give.
const WINDOWS := [
	["bring", 0.000, 0.201],
	["partial", 0.201, 0.429],
	["the pause", 0.429, 0.543],
	["glint", 0.543, 0.611],
	["extract", 0.611, 0.801],
	["seat", 0.801, 1.001],
]

## 1/60 s per physics frame, and the legs are timed in seconds rather than in
## frames because a headless process frame is not 1/60 s — 240 of them is a
## fiftieth of a second, which is how a probe ends up measuring nothing.
const DT := 1.0 / 60.0

class FrameClock extends Node:
	var total := 0.0
	func _process(delta: float) -> void:
		total += delta


var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var manager: Node
var slot: WeaponSlot
var visual: Node3D

var _samples: Array[Dictionary] = []
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

	var blade := SwordClasses.blade_reach(_weapon_id())
	print("")
	print("── the numbers this probe's limits come from")
	print("   FIT_CLEAR %.5f m · SAYA_WALL %.5f m · blade_reach %.3f m · saya_body %.3f m"
		% [SwordClasses.FIT_CLEAR, SwordClasses.SAYA_WALL, blade,
			SwordClasses.saya_body_len(_weapon_id())])

	# A sandbox hands the player the sword already drawn, so the draw has to be
	# run the way a weapon switch runs it: away to the chain, and back.
	manager.call("equip_weapon", slot.CHAIN)
	await _leg("sheathe 1", Callable(), 2.6)
	await _leg("draw 1", Callable(manager, "equip_weapon").bind(slot.SWORD), 3.6)
	await _leg("idle", Callable(), 1.0)
	await _leg("sheathe 2", Callable(manager, "equip_weapon").bind(slot.CHAIN), 3.6)
	await _leg("draw 2", Callable(manager, "equip_weapon").bind(slot.SWORD), 3.6)

	_report()
	quit(1 if not _fails.is_empty() else 0)


func _weapon_id() -> StringName:
	var id := StringName(slot.get("weapon_id")) if slot.get("weapon_id") != null else &""
	return SwordBasic.WEAPON_ID if id == &"" or id == &"chain" else id


# ===========================================================================
#  DRIVING
# ===========================================================================

## One leg: fire the trigger, then record every physics frame until the deadline.
func _leg(_tag: String, trigger: Callable, seconds: float) -> void:
	if trigger.is_valid():
		trigger.call()
	var until := float(Time.get_ticks_msec()) + seconds * 1000.0
	while float(Time.get_ticks_msec()) < until:
		await physics_frame
		_samples.append(_read())


# ===========================================================================
#  THE GEOMETRY
# ===========================================================================

## Everything here is in `WeaponRoot` space, which is the space BOTH actors are
## authored in and the space `probe_saya_motion.gd` measures the mouth in. The
## visual node's own transform IS that space: it is a child of `WeaponRoot` at
## identity, and its script authors `pose_position` in the root frame and converts
## back out through `root_inverse` for its children.
##
## THE WINDOW IS THE AUTHORED ONE, NOT A GEOMETRIC GUESS. The first version of
## this gated on "how many metres of blade are inside", computed from where the
## mouth happened to fall along the blade's axis — and that number is meaningless
## exactly when the fault is largest, because a blade pointing the other way from
## three feet off is not a blade with 0.76 m of itself in a scabbard. So the
## window is `equip_blend <= SwordBasic.NE_BLADE_CLEAR`: the stretch the sentence
## itself declares the blade to be home for. Outside it the blade is out and a
## 40 mm error is called a draw.
func _read() -> Dictionary:
	var saya := combat.saya_rig
	var mouth: Vector3 = saya.transform.origin
	var saya_axis: Vector3 = saya.transform.basis * Vector3.UP
	var origin: Vector3 = visual.position
	var blade_axis: Vector3 = Basis.from_euler(visual.rotation) * Vector3.UP

	var along: Vector3 = mouth - origin
	var depth := along.dot(blade_axis)
	var transverse := (along - blade_axis * depth).length()
	# A blade rotated 180 degrees in the bore is still in the bore, and reporting
	# that as a 180 degree fault would make the one number this probe exists for
	# unreadable. The axis is a LINE.
	var angle := rad_to_deg(blade_axis.angle_to(saya_axis))
	if angle > 90.0:
		angle = 180.0 - angle
	return {
		"blend": float(combat.equip_blend),
		"transverse": transverse,
		"angle": angle,
		# Diagnostic only: where the mouth falls along the blade's axis, from the
		# grip. It is what tells "the blade is out" apart from "the blade is in but
		# crooked" once the transverse number has already said which.
		"depth": depth,
	}


# ===========================================================================
#  VERDICT
# ===========================================================================

func _report() -> void:
	if _samples.is_empty():
		print("FAIL: no samples were taken")
		_fails.append("no samples")
		return
	print("")
	print("   samples %d" % _samples.size())
	print("")
	print("   %-11s %10s %9s %10s %11s" % [
		"beat", "mouth depth", "transverse", "angle", "tip error"])
	var reach := SwordClasses.blade_reach(_weapon_id())
	for w in WINDOWS:
		var label: String = w[0]
		var lo: float = w[1]
		var hi: float = w[2]
		var worst_t := 0.0
		var worst_a := 0.0
		var worst_tip := 0.0
		var last_d := 0.0
		var worst: Dictionary = {}
		var n := 0
		for s in _samples:
			var blend := float(s["blend"])
			if blend < lo or blend >= hi:
				continue
			n += 1
			# HOW FAR THE BLADE STICKS OUT OF THE MOUTH, which is the lever the
			# angle error acts on: the far end of a blade that is 0.76 m IN has
			# 0.76 m of travel per radian, and the same blade fully out has none.
			# Written the wrong way round first (the depth instead of its
			# complement), which reported the worst case in the whole run — the
			# 85-degree carry-up, with the entire blade in the scabbard — as a
			# 1.5 mm error.
			var out_len := maxf(reach - float(s["depth"]), 0.0)
			worst_t = maxf(worst_t, float(s["transverse"]))
			worst_a = maxf(worst_a, float(s["angle"]))
			worst_tip = maxf(worst_tip, sin(deg_to_rad(float(s["angle"]))) * out_len)
			last_d = float(s["depth"])
			if float(s["transverse"]) >= worst_t:
				worst = s
		if n == 0:
			print("   %-11s %10s" % [label, "-- no samples --"])
			continue
		print("   %-11s %10.4f %9.4f %10.4f %11.4f" % [
			label, last_d, worst_t, worst_a, worst_tip])
		print("   %-11s   worst at blend=%.3f  depth=%.3f  transverse=%.4f  angle=%.3f"
			% ["", float(worst.get("blend", 0.0)), float(worst.get("depth", 0.0)),
				float(worst.get("transverse", 0.0)), float(worst.get("angle", 0.0))])

	print("")
	var worst_t := 0.0
	var worst_a := 0.0
	var tightest_allowed := 90.0
	var worst_tip := 0.0
	var home := 0
	for s in _samples:
		if float(s["blend"]) > SwordBasic.NE_BLADE_CLEAR:
			continue
		# AND THE BLADE HAS TO ACTUALLY BE IN THERE. `blend` alone is not enough at
		# its own boundary: Beat 4 is the instant the blade clears, so the samples
		# either side of it are a fully-drawn blade and a fully-drawn blade one
		# frame into a 89-degree turn to guard — the measurement the whole probe is
		# for, reported as a fault. "Inside" means the mouth has not passed the
		# blade's own tip, which is a distance and not a state.
		var depth_now := float(s["depth"])
		if reach - depth_now < 0.01:
			continue
		home += 1
		if float(s["transverse"]) > worst_t:
			worst_t = float(s["transverse"])
		# The blade pivoting inside the bore spends the clearance at its own far
		# end, so the allowance is the angle that keeps `sin(angle) * out_len`
		# inside one clearance.
		var out_len := maxf(reach - depth_now, 0.0)
		var allowed := rad_to_deg(asin(clampf(ANGLE_LIMIT_PER_METRE / maxf(out_len, 0.0001), 0.0, 1.0)))
		if float(s["angle"]) > worst_a:
			worst_a = float(s["angle"])
		# THE TIGHTEST ALLOWANCE, not the one attached to the worst angle. Taken
		# the other way round, a run whose angles are all exactly zero never enters
		# the branch that records an allowance, and the verdict prints
		# "0.000 deg, allowance 0.000" — a comparison of nothing against nothing,
		# which is a green line that would stay green if the allowance were a
		# hundredth of what it should be.
		tightest_allowed = minf(tightest_allowed, allowed)
		worst_tip = maxf(worst_tip, sin(deg_to_rad(float(s["angle"]))) * out_len)
	print("   %d of %d samples have the blade in the scabbard (blend <= %.3f and tip not out)"
		% [home, _samples.size(), SwordBasic.NE_BLADE_CLEAR])
	_judge(worst_t < TRANSVERSE_LIMIT,
		"the mouth stays on the blade's own axis to within %.4f m (worst %.4f m)"
			% [TRANSVERSE_LIMIT, worst_t])
	_judge(worst_tip < TRANSVERSE_LIMIT,
		"no part of a blade inside the scabbard leaves the bore by %.4f m (worst %.4f m)"
			% [TRANSVERSE_LIMIT, worst_tip])
	_judge(worst_a <= tightest_allowed,
		"a blade inside the scabbard never pivots past its clearance (worst %.3f deg, allowance %.3f)"
			% [worst_a, tightest_allowed])


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)
