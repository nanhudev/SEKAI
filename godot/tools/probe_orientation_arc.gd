extends SceneTree
## PROBE · DOES EVERY ROTATION IN THE SWORD LANGUAGE TRAVEL AN ARC?
##
## ===========================================================================
## §18 AS A GATE: "ORIENTATION POP" IS A DEFECT, NOT A TASTE
## ===========================================================================
## §18 of the Controlled Stillness brief: a large pose change must be carried by
## a REAL ARC — the quaternion's shortest path, or an explicitly authored
## intermediate pose — and never by cutting from one Transform to another. §35
## turns that into a regression gate, and this is the instrument.
##
## ===========================================================================
## WHAT WAS WRONG, AND WHY NOTHING HAD CAUGHT IT
## ===========================================================================
## Every pose in this project is a euler TRIPLE, because that is what `aim_euler`
## solves and what the beat lists store. So every blend between two poses was
## written as a blend of three numbers:
##
##     a.lerp(b, u)                                        # a line in ANGLE space
##     Basis.from_euler(a).slerp(Basis.from_euler(b), u)   # an arc in ROTATION space
##
## The two agree EXACTLY at `u = 0` and `u = 1`. Every beat is reached exactly,
## every endpoint assertion passes, and the entire disagreement lives in the
## interior of each segment, where nothing was looking.
##
## The table below — `THE KEYS, READ AS ANGLE SPACE STILL WOULD` — is the size of
## what was hiding there, computed on the authored key pairs themselves. It is no
## longer a gate, because the operation it describes has been retired; it is kept
## as a DIAGNOSTIC, because it is what says which segments had room to go wrong
## and how nearly they did.
##
## ===========================================================================
## SO THE GATE IS ON THE POSE THAT SHIPS
## ===========================================================================
## Two questions, both asked of `SwordPoseSampler.sample()` — the same function
## the renderer calls — walked at 600 Hz:
##
##   ROUTE  how far did the orientation actually turn inside each authored
##          segment, against how far apart that segment's two poses are?
##          A segment that turns 226 degrees to reach a pose 138 away is not
##          following its own shortest path; it is going the long way round,
##          which is a wrong trajectory rather than a wrong speed.
##
##   SHAPE  is any single step out of line with the steps beside it? A slerp's
##          steps rise and fall smoothly, so every step is within a small factor
##          of the largest one near it, while a snap is one step with nothing
##          like it beside it. Resolution-independent, and it needs no guess
##          about how big a step is too big.
##
## Position gets the same shape test, for the same reason it does in the Iaido
## probe: §18 is about orientation, but "cut a Transform" does not care which
## half of a Transform was cut, and the phase this probe was written for had two
## translational pops that every orientation test in the project was blind to.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_orientation_arc.gd
##   ORIENTATION_TRACE=1 to list every segment rather than only the offenders.

const SwordBasic := preload("res://scripts/combat/sword_basic.gd")
const SwordPoseSampler := preload("res://scripts/combat/sword_pose_sampler.gd")

## One step of the walk, in seconds. 600 Hz is ten samples per rendered frame,
## which is fine enough that a single-frame snap cannot pass between two samples.
const DT := 1.0 / 600.0

## How much longer than its own shortest path a segment may be, as a ratio.
##
## 1.02 is not a tolerance on the picture, it is a tolerance on the INTEGRATOR: a
## path measured on a finite grid of a geodesic is always a shade longer than the
## geodesic, and `ease_in_out` spends most of the segment near its ends, where
## the samples are almost coincident. A segment that is 2% longer than its arc is
## the same trajectory measured carefully; a segment that is 50% longer is the
## long way round, and the measured gap between those two cases is 226.5 against
## 138.2 — it is not a close call and does not need a tight threshold.
const ROUTE_RATIO_LIMIT := 1.02

## Radians and metres per step above which a step must be looked at. Not a
## pass/fail: a cut is allowed to be fast. What matters is the SHAPE.
const POP_RATIO_LIMIT := 2.5
const NEIGHBOURHOOD := 6

## How far the euler-space blend of an authored key pair is allowed to stray from
## the true arc. Kept as the diagnostic's own yardstick so a reader can see how
## much room a segment left — the numbers in the retired table above are what
## this was chosen against.
const ARC_STRAY_LIMIT := 1.0

const STEPS := 128

## The five phase keys of a four-phase move, in the order they are walked.
const PHASE_KEYS := ["anchor_rot", "wind_rot", "contact_rot", "follow_rot", "recover_rot"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var trace := OS.get_environment("ORIENTATION_TRACE") != ""
	print("")
	print("── the arc test · a segment may take at most %.0f%% more path than its own arc"
		% ((ROUTE_RATIO_LIMIT - 1.0) * 100.0))
	print("   walked at %d Hz · %d×%d the density of a rendered frame" % [
		int(1.0 / DT), int((1.0 / 60.0) / DT), 1])
	print("")
	print("── DIAGNOSTIC · the keys, read the way angle space still would")
	print("   (not a gate: the operation this describes has been retired. It is kept")
	print("    because it is what says how much room a segment had to go wrong.)")

	var worst_route := 0.0
	var worst_route_label := ""
	var route_offenders := 0
	var worst_pop := 0.0
	var worst_pop_at := ""
	var worst_pos_pop := 0.0
	var worst_pos_at := ""
	var segments := 0

	for move: SwordMove in _roster():
		var plan := _plan(move)
		if plan.is_empty():
			continue
		# ---- the diagnostic: what a lerp WOULD have done to these keys -----
		var stray_worst := 0.0
		var stray_worst_label := ""
		for seg in plan:
			var s := _stray(seg["from_rot"], seg["to_rot"])
			if s > stray_worst:
				stray_worst = s
				stray_worst_label = seg["name"]
			if s > ARC_STRAY_LIMIT:
				print("   %-12s %-16s would stray %7.2f deg from its own arc"
					% [move.id, seg["name"], s])
		if stray_worst <= ARC_STRAY_LIMIT:
			print("   %-12s every segment already near its own arc (worst %.2f deg)"
				% [move.id, stray_worst])
		else:
			print("   %-12s worst %-16s %7.2f deg of room"
				% [move.id, stray_worst_label, stray_worst])

		# ---- the gate: what the sampler DOES do ---------------------------
		var walk := _walk(move)
		var move_worst := 0.0
		var move_worst_label := ""
		for seg in plan:
			segments += 1
			var walked := _path_length(walk, seg["from_t"], seg["to_t"])
			var arc: float = seg["arc"]
			# A segment whose two poses are the same has no direction to be
			# right or wrong about, and its arc is zero.
			if arc < 0.01:
				continue
			var ratio := walked / arc
			if ratio > ROUTE_RATIO_LIMIT:
				route_offenders += 1
			if ratio > move_worst:
				move_worst = ratio
				move_worst_label = seg["name"]
			if trace or ratio > ROUTE_RATIO_LIMIT:
				print("   %-12s %-16s turns %7.1f deg to reach a pose %6.1f away  (%.3f×)"
					% [move.id, seg["name"], walked, arc, ratio])
		if move_worst > worst_route:
			worst_route = move_worst
			worst_route_label = "%s · %s" % [move.id, move_worst_label]

		if not trace:
			print("   %-12s worst segment %-16s %.3f× its own arc"
				% [move.id, move_worst_label, move_worst])

		# ---- and the shape of both halves of the Transform ----------------
		var rot := _shape(walk, true)
		var pos := _shape(walk, false)
		if float(rot["ratio"]) > worst_pop:
			worst_pop = rot["ratio"]
			worst_pop_at = "%s · %.3f s (%.2f deg, %.2fx its neighbours)" % [
				move.id, rot["at"], rot["step"], rot["ratio"]]
		if float(pos["ratio"]) > worst_pos_pop:
			worst_pos_pop = pos["ratio"]
			worst_pos_at = "%s · %.3f s (%.1f mm, %.2fx its neighbours)" % [
				move.id, pos["at"], pos["step"] * 1000.0, pos["ratio"]]

	print("")
	print("── GATE · what the sampler actually does")
	print("   %d segments over %d moves" % [segments, _roster().size()])
	print("   ROUTE  worst %.3f× its own arc — %s" % [worst_route, worst_route_label])
	print("   SHAPE  worst orientation step %s" % worst_pop_at)
	print("   SHAPE  worst position step    %s" % worst_pos_at)

	var fails := 0
	fails += _judge(route_offenders == 0,
		"every segment follows its own shortest path (%d of %d take a longer route)"
			% [route_offenders, segments])
	fails += _judge(worst_pop <= POP_RATIO_LIMIT,
		"no orientation arrives by a jump (worst is %.2fx its neighbourhood)"
			% worst_pop)
	fails += _judge(worst_pos_pop <= POP_RATIO_LIMIT,
		"and no position either (worst is %.2fx its neighbourhood)" % worst_pos_pop)

	print("")
	print("   %s" % ("ok   every rotation in the language travels an arc" if fails == 0
		else "FAIL %d of the arc gates" % fails))
	quit(1 if fails > 0 else 0)


## Every move the sword language owns, plus the draw. Typed, because an untyped
## `Array` makes `move.foo()` a Variant and turns the next line into a parse
## error rather than a measurement.
func _roster() -> Array[SwordMove]:
	var out: Array[SwordMove] = []
	out.append_array(SwordBasic.moves())
	out.append(SwordBasic.equip())
	return out


## The move's authored segments: when each starts and ends, the two rotations it
## runs between, and how far apart those two orientations are.
##
## Built from the move's OWN clock — beat times for a beat list, the four phase
## durations for a four-phase move — so the windows here are the same windows the
## sampler walks and a segment here is a segment there.
func _plan(move: SwordMove) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if move.has_beats():
		var times := move.beat_times
		for i in times.size() - 1:
			var a: Vector3 = move.beat_rotations[i]
			var b: Vector3 = move.beat_rotations[i + 1]
			out.append({
				"name": "beat %d→%d" % [i, i + 1],
				"from_t": times[i], "to_t": times[i + 1],
				"from_rot": a, "to_rot": b, "arc": _arc(a, b),
			})
		return out
	var bounds: Array[float] = [
		0.0, move.startup, move.startup + move.strike,
		move.startup + move.strike + move.follow_time,
		move.startup + move.strike + move.follow_time + move.recovery,
	]
	for i in PHASE_KEYS.size() - 1:
		var a: Vector3 = move.get(PHASE_KEYS[i])
		var b: Vector3 = move.get(PHASE_KEYS[i + 1])
		out.append({
			"name": "%s→%s" % [PHASE_KEYS[i].replace("_rot", ""),
				PHASE_KEYS[i + 1].replace("_rot", "")],
			"from_t": bounds[i], "to_t": bounds[i + 1],
			"from_rot": a, "to_rot": b, "arc": _arc(a, b),
		})
	return out


## The sampler's own answer for this move, at `DT`, as
## `{t, rotation (as a quaternion), position}` per step.
func _walk(move: SwordMove) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var end := maxf(move.total_time(), DT)
	var steps := int(ceil(end / DT))
	for i in steps + 1:
		var t := minf(float(i) * DT, end)
		var pose := SwordPoseSampler.sample(move, t)
		out.append({
			"t": t,
			"q": Basis.from_euler(pose["rotation"]).get_rotation_quaternion(),
			"p": pose["position"],
		})
	return out


## How far the ORIENTATION turns between two instants, integrated along the walk.
##
## Through `SwordPoseSampler.angle_between` and NOT `Quaternion.angle_to`, and
## the difference is the difference between a measurement and a number: Godot's
## own `angle_to` returns 0.056 degrees for a rotation against ITSELF, so a
## segment in which nothing moves still accumulates a tenth of a degree, and a
## long still hold accumulates ten. See that function's comment.
func _path_length(walk: Array[Dictionary], from_t: float, to_t: float) -> float:
	var total := 0.0
	var prev := Quaternion.IDENTITY
	var have := false
	for step in walk:
		var t: float = step["t"]
		if t < from_t or t > to_t:
			continue
		var q: Quaternion = step["q"]
		if have:
			total += SwordPoseSampler.angle_between(prev, q)
		prev = q
		have = true
	return total


## The largest step in the walk and the largest ratio of a step to its
## neighbours, for the rotation or for the position.
##
## See `POP_RATIO_LIMIT`. The SHAPE is the test, not the size: a slerp's steps
## rise and fall smoothly so every step is within a small factor of the largest
## one near it, while a snap is one step with nothing like it beside it.
func _shape(walk: Array[Dictionary], rotation: bool) -> Dictionary:
	var deltas: PackedFloat32Array = PackedFloat32Array()
	var times: PackedFloat32Array = PackedFloat32Array()
	var prev_q := Quaternion.IDENTITY
	var prev_p := Vector3.ZERO
	var have := false
	for step in walk:
		var q: Quaternion = step["q"]
		var p: Vector3 = step["p"]
		if have:
			if rotation:
				deltas.append(SwordPoseSampler.angle_between(prev_q, q))
			else:
					deltas.append(p.distance_to(prev_p))
			times.append(step["t"])
		prev_q = q
		prev_p = p
		have = true
	var step_max := 0.0
	var step_at := 0.0
	var ratio := 0.0
	var ratio_at := 0.0
	for i in deltas.size():
		var neighbour := 0.0
		for j in range(maxi(i - NEIGHBOURHOOD, 0), mini(i + NEIGHBOURHOOD + 1, deltas.size())):
			if j != i:
				neighbour = maxf(neighbour, deltas[j])
		if deltas[i] > step_max:
			step_max = deltas[i]
			step_at = times[i]
		if neighbour > 0.0001:
			var r := deltas[i] / neighbour
			if r > ratio:
				ratio = r
				ratio_at = times[i]
	return {"ratio": ratio, "at": ratio_at, "step": step_max, "step_at": step_at}


## How far apart two authored poses are, as ORIENTATIONS, in degrees.
func _arc(a: Vector3, b: Vector3) -> float:
	return SwordPoseSampler.angle_between(
		Basis.from_euler(a).get_rotation_quaternion(),
		Basis.from_euler(b).get_rotation_quaternion())


## THE DIAGNOSTIC. The largest angle, in degrees, between the euler-space blend
## of `a` and `b` and their true arc.
##
## `ease_in_out` is deliberately absent: it is a reparameterisation of `u`, and
## it is applied identically to both sides, so it cannot change the SIZE of the
## disagreement — only where along the segment it peaks.
func _stray(a: Vector3, b: Vector3) -> float:
	var qa := Basis.from_euler(a).get_rotation_quaternion()
	var qb := Basis.from_euler(b).get_rotation_quaternion()
	var worst := 0.0
	# The ends are equal by construction; the interior is the question.
	for k in range(1, STEPS):
		var u := float(k) / float(STEPS)
		var lerped := Basis.from_euler(a.lerp(b, u)).get_rotation_quaternion()
		var arced: Quaternion = qa.slerp(qb, u)
		worst = maxf(worst, SwordPoseSampler.angle_between(lerped, arced))
	return worst


func _judge(condition: bool, reason: String) -> int:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	return 0 if condition else 1
