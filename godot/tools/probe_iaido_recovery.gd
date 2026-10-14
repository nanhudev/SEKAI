extends SceneTree
## PROBE · THE IAIDO RECOVERY IS ONE CONTROLLED ROTATION, NOT A FLOURISH
##
## ===========================================================================
## §35-E AS A GATE: "IAIDO RECOVERS TO TWO SPINS" IS A FAILURE
## ===========================================================================
## §21 of the Controlled Stillness brief retires the two-arc recovery outright
## and §22 puts the replacement in a band: 270-360 degrees, ONE rotation, its
## purpose being to bring the edge back to the slot the koiguchi is. §35 then
## lists "the Iaido has gone back to two spins" as a regression that fails the
## pass.
##
## That is a statement about a NUMBER, so it can be a gate rather than a memory
## of a review. Before this probe there was nothing that knew the difference:
## `PHASE K` could be re-authored to three revolutions and every existing test
## would still pass, because every existing test asks about the glass, the audio
## and the world, and none of them asks how far the sword turned.
##
## ===========================================================================
## WHY IT SWEEPS THE CEREMONY INSTEAD OF WATCHING IT
## ===========================================================================
## `IaidoDirector.set_debug_hold(t)` sets `elapsed` and solves the pose for that
## instant with one `_process(0.0)`. So the authored rotation can be read as a
## pure function of `t`, at any resolution, with no dependence on frame times,
## no dependence on how long the ceremony takes in real seconds, and identical
## numbers on every run.
##
## That is the OPPOSITE of what `set_debug_hold` is dangerous for. The movie
## tools must not use it to judge a freeze, because jumping time fakes a
## stationary frame -- but a rotation is not a duration, and reading it out of a
## skipped-to instant is exactly what it is for.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_iaido_recovery.gd
##   IAIDO_RECOVERY_TRACE=1 to dump the whole sweep.

const STAGE := "res://scenes/combat/CombatSandbox.tscn"
const SWORD_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual"

const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")
## For `angle_between`, which is the only well-conditioned way to ask how far
## apart two rotations are. See that function's comment for the 0.056-degree
## self-distance this avoids.
const SwordPoseSampler := preload("res://scripts/combat/sword_pose_sampler.gd")

## §22's band, in degrees. Quoted rather than derived because it is a quotation.
## (Consumed as the wrist/orientation band -- see `WRIST_MIN` below.)

## One step of the sweep, in seconds.
##
## 240 Hz is four samples per rendered frame, which is the resolution a rendered
## fault has to be caught at. It is overridable because a sweep can invent a
## fault that is not there -- if a step's size depends on the grid it was
## measured on, the grid is the thing that jumped -- and the only way to tell
## that from a real one is to run the same ceremony on a second grid. Set
## `IAIDO_RECOVERY_DT=0.001` and compare the step's own size and time.
const DT_DEFAULT := 1.0 / 240.0

var step_dt := DT_DEFAULT

## ===========================================================================
## A POP IS OUT OF LINE WITH ITS NEIGHBOURS, NOT BIG
## ===========================================================================
## The first edition of this gate asked "is any step bigger than 20 degrees",
## and it failed the ceremony for a step of 29.35 degrees at t = 4.742 s. That
## step is PHASE F, the draw: the blade leaves the mouth and whips from the bore
## to the drawn pose, 250 degrees in about 0.03 s. It is a fast authored ARC --
## a slerp, monotone, with neighbours of 20.6, 23.6, 18.5 and 14.0 degrees on
## either side of it. A degree threshold cannot tell that from a transform being
## cut, because both are a big number, and the big number is the point of a draw.
##
## What separates them is the SHAPE: a slerp's steps rise and fall smoothly, so
## every step is within a small factor of the largest one near it, while a snap is
## one step with nothing like it beside it. So the test is a ratio to the local
## maximum, which is resolution-independent and needs no degree budget at all --
## and it catches the fault wherever it happens rather than only where a number
## was guessed to be too big.
const NEIGHBOURHOOD := 6
const POP_RATIO_LIMIT := 2.5

## ===========================================================================
## §22 IS A STATEMENT ABOUT THE WRIST, SO IT IS MEASURED AS ONE
## ===========================================================================
## The first edition of this gate integrated the angle between successive
## BLADE DIRECTION vectors. That is the path the TIP walks, and it is the wrong
## quantity for §22 in two separate ways:
##
##   It over-reports. The authored sweep carries a wobble (`sin`/`cos` of the
##   turn, windowed by `sin(PI * u)`), which swings the tip from side to side
##   and back. Path length counts every one of those swings, so a one-turn
##   rotation that is authored cleanly still reports 417 degrees -- the turn is
##   306, the rest is the tip walking around a cone.
##
##   It under-reports the part the brief actually names. §22 says the rotation
##   comes from the FOREARM AND WRIST and its job is to reset the EDGE. A pure
##   roll about the blade's own axis is a large wrist movement that moves the
##   tip NOT AT ALL, so the old metric would have scored the most literal
##   reading of §22 as zero degrees of rotation.
##
## What has to be counted is how far the SWORD turned, not how far its point
## travelled: the geodesic length of the ORIENTATION's own path. A single full
## turn about any axis is 360 of those. Two spins is 720 of them. And the
## retired recipe -- `TAU * (first + second)` -- is exactly the thing this
## number is supposed to expose, so the gate is meaningful either way.
##
## It is integrated from the quaternions with their sign fixed up as it goes,
## because `Quaternion.angle_to` returns the SHORT way round (0..180) and a
## sweep that passes 180 in one step would be booked as coming back the other
## way; `angle_to` on a sign-corrected pair is then monotone with the motion.
const WRIST_MIN := 270.0
const WRIST_MAX := 360.0

## The two halves of §23's catch, each on its own.
##
## REPOINT is the drawn pose's own pointing error -- the blade leaves the draw
## about 130 degrees off the bore, and something has to take it. The catch is
## what takes it, so this is not a tolerance on the craft, it is a bound on the
## ARITHMETIC: `slerp(identity, target, t)` is well conditioned while `target` is
## away from antipodal, and 150 is as near to 180 as this is allowed to go.
const REPOINT_LIMIT := 150.0

## ROLL is the one that has teeth. The turn's stated job is to reset the EDGE,
## and a roll about the blade's own axis is the only rotation that can do it. So
## whatever roll is LEFT for the catch is roll the turn failed to deliver. 75 is
## half of §22's smallest turn: a turn that needs the catch to roll more than
## that has not turned enough, and this is the gate that notices.
const ROLL_LIMIT := 75.0

## The seating the ceremony's own click has to land on. `IaidoTuning` places the
## sword's ORIGIN at `seat_origin - seat_basis.y * guard_setback` for its "fully
## seated" beat, and the contract is "the tsuba face is on the mouth". So this is
## the distance from the blade's tsuba face to the sheath anchor at the click,
## and it is §27's `Guard vs Mouth` line as a number.
const CLICK_GAP_LIMIT := 0.008

## How much alignment one turn is allowed to leave for the blend, in degrees.
## INFORMATIONAL SINCE §23's CATCH BECAME TWO ROTATIONS. It used to be a gate,
## because a single identity-to-residual slerp is only well-conditioned while
## the two are far from antipodal. That blend no longer exists: the residual is
## split into a repoint (a direction onto a direction) and a roll about the bore,
## and THOSE are what has to stay short. The number is still printed because a
## large one is the reason the split is there, and it is the number that says
## whether `spin_turns` is doing any of the work or all of it is the catch.
const RESIDUAL_LIMIT := 60.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load(STAGE)
	var world := scene.instantiate()
	root.add_child(world)
	for _i in 14:
		await physics_frame

	var director: Node = world.get_node("IaidoDirector")
	var player: Node3D = director.get("player")
	director.get("combat").set("iaido_ready_at", 0.0)
	player.set("stamina", 100.0)
	var tuning: Resource = director.get("tuning")
	var sword: Node3D = player.get_node(SWORD_PATH)

	var span_from: float = tuning.spin_start
	var span_to: float = tuning.spin_end
	# WHERE §22 STOPS BEING THE QUESTION. The phase contains two movements: the
	# turn (§22, about the blade's own axis, sized 270-360) and the catch (§23,
	# a repoint onto the bore plus a roll onto the slot). The band is a statement
	# about the first. Measured over the whole phase the catch's ~130 degrees of
	# pointing are counted against the turn's budget -- 378 degrees of "turn" for
	# a 306 degree turn -- and the gate fails a ceremony that is correct. So the
	# turn is measured where the turn is: `u` from 0 to `spin_turn_share`.
	var turn_to: float = lerpf(span_from, span_to, tuning.spin_turn_share)
	var end: float = tuning.restore_end
	var want_dt := OS.get_environment("IAIDO_RECOVERY_DT")
	if want_dt != "":
		step_dt = maxf(float(want_dt), 0.0001)

	print("")
	print("── the ceremony this reads")
	print("   phase K %.2f → %.2f s · blade reach %.3f m · sweep %.4f s a step"
		% [span_from, span_to, tuning.blade_reach, step_dt])

	# ---- THE SWEEP -------------------------------------------------------
	var steps := int(ceil(end / step_dt))
	var prev_dir := Vector3.ZERO
	var prev_q := Quaternion.IDENTITY
	var prev_pos := Vector3.ZERO
	var have_prev := false
	var turned := 0.0
	var turned_k := 0.0
	var wrist_k := 0.0
	var wrist_phase := 0.0
	var turned_phase := 0.0
	var wrist := 0.0
	var trace := OS.get_environment("IAIDO_RECOVERY_TRACE") != ""
	var times: PackedFloat32Array = PackedFloat32Array()
	var deltas: PackedFloat32Array = PackedFloat32Array()
	var pos_deltas: PackedFloat32Array = PackedFloat32Array()

	for i in steps + 1:
		var t := minf(float(i) * step_dt, end)
		director.call("set_debug_hold", t)
		var q := Basis.from_euler(sword.rotation).get_rotation_quaternion()
		var dir := q * Vector3.UP
		if have_prev:
			var step := rad_to_deg(prev_dir.angle_to(dir))
			turned += step
			# The wrist's own count: the geodesic length of the orientation's
			# path, through `SwordPoseSampler.angle_between` rather than through
			# `Quaternion.angle_to`. That one returns 0.056 degrees for a
			# rotation against ITSELF, so at 240 Hz it hands every still second
			# thirteen and a half degrees of movement that is not there.
			var wrist_step := SwordPoseSampler.angle_between(prev_q, q)
			wrist += wrist_step
			if t >= span_from and t <= turn_to:
				turned_k += step
				wrist_k += wrist_step
			if t >= span_from and t <= span_to:
				wrist_phase += wrist_step
				turned_phase += step
			times.append(t)
			deltas.append(step)
			pos_deltas.append(sword.position.distance_to(prev_pos))
		prev_dir = dir
		prev_q = q
		prev_pos = sword.position
		have_prev = true

	# ---- THE POP, AS A SHAPE ---------------------------------------------
	# Run over the orientation AND over the position. §18 is about orientation,
	# but "cut a Transform" does not care which half of a Transform was cut: the
	# two faults this found were both in translation, and neither would have been
	# visible to any test in this file before it was written.
	var shape := _shape(times, deltas)
	var pos_shape := _shape(times, pos_deltas)
	var worst_ratio: float = shape["ratio"]
	var worst_ratio_at: float = shape["at"]
	var worst_step: float = shape["step"]
	var worst_step_at: float = shape["step_at"]
	var pos_ratio: float = pos_shape["ratio"]
	var pos_ratio_at: float = pos_shape["at"]
	var pos_step: float = pos_shape["step"]
	var pos_step_at: float = pos_shape["step_at"]
	if trace:
		for i in deltas.size():
			if deltas[i] / maxf(_neighbour(deltas, i), 0.0001) > 3.0:
				print("   %7.3f  step %7.3f deg  %6.2fx neighbourhood  total %8.1f deg"
					% [times[i], deltas[i],
						deltas[i] / maxf(_neighbour(deltas, i), 0.0001),
						_running(deltas, i)])

	# ---- WHAT IT ARRIVED AT ----------------------------------------------
	#
	# §23's Mouth Catch is the thing that has to survive the change: the last
	# third of the recovery slerps the blade onto the bore's own axis, so phase
	# L is a translation. If that is broken the blade arrives at the koiguchi
	# pointing somewhere else and the rest of the ceremony is a scrape.
	#
	# ...AND IT HAS TO BE READ INSIDE PHASE K. `span_to` is `spin_end`, and the
	# branch test is `t < spin_end`, so asking at exactly `span_to` answers with
	# phase L's first frame -- which is `_bore_pose`, whose rotation IS
	# `seat_euler` by construction. That made this gate report 0.00 degrees no
	# matter what phase K did, including while phase K was ending somewhere
	# completely different and phase L was snapping to it. A gate that cannot
	# fail is not a gate; it is a decoration with a passing colour.
	var seat_basis: Basis = director.get("seat_basis")
	var last_k := maxf(span_to - step_dt, span_from)
	director.call("set_debug_hold", last_k)
	var at_end := Basis.from_euler(sword.rotation) * Vector3.UP
	var arrival := rad_to_deg(at_end.angle_to(seat_basis * Vector3.UP))

	# ...and the same question at the moment the ceremony CLICKS, which is the
	# one instant the player is being told "the blade is home". The tsuba face
	# against the mouth is that claim; the sound is not allowed to make it on
	# its own.
	var anchor: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/SheathAnchor")
	var reach: float = SwordClasses.blade_reach(&"iaito")
	director.call("set_debug_hold", tuning.final_click)
	var tsuba := sword.position \
		+ Basis.from_euler(sword.rotation) * Vector3.UP * SwordClasses.guard_setback(&"iaito")
	var click_gap := tsuba.distance_to(anchor.position)
	director.call("set_debug_hold", tuning.final_click - 0.15)
	var tsuba_before := sword.position \
		+ Basis.from_euler(sword.rotation) * Vector3.UP * SwordClasses.guard_setback(&"iaito")
	var click_travel := tsuba_before.distance_to(tsuba)

	print("")
	print("   THE TURN (§22): %.1f deg in %.2f s, over the first %.0f%% of the phase"
		% [wrist_k, turn_to - span_from, tuning.spin_turn_share * 100.0])
	print("   (the whole phase is %.1f deg; the rest is §23's catch, below)"
		% wrist_phase)
	print("   it arrives %.2f deg off the bore's own axis" % arrival)
	print("   at the click the tsuba stands %.2f mm from the mouth, having "
		% (click_gap * 1000.0) + "covered %.1f mm in the last 0.15 s" % (click_travel * 1000.0))
	# THE RESIDUAL, AND THE TWO ROTATIONS IT IS SPLIT INTO. What one turn failed
	# to line up with the bore, as a rotation between two FIXED bases -- so it is
	# a property of the tuning rather than of any frame. A small residual means
	# `spin_turns` is nearly right on its own; a large one means the turn count
	# is doing little of the work and the catch is doing most of it.
	var drawn_rot: Vector3 = tuning.drawn_rotation
	var drawn_basis := Basis.from_euler(drawn_rot)
	var own_axis := (drawn_basis * Vector3.UP).normalized()
	# THE RECIPE, WRITTEN ONCE. `landed` is `spin` at the end of the sweep: the
	# wobble is zero there and the roll has run its authored angle. This block,
	# the candidate table below, and `iaido_director.gd`'s PHASE K all have to be
	# the same rotation, or the numbers describe three different ceremonies --
	# which is exactly how the residual gate spent a run measuring a pose that
	# was already retired.
	var landed := Basis(own_axis, -TAU * tuning.spin_turns) * drawn_basis
	var residual := rad_to_deg(landed.get_rotation_quaternion().angle_to(
		seat_basis.get_rotation_quaternion()))
	# ...read out of the director, so the gate is measuring the numbers the
	# CEREMONY actually uses rather than a second copy of the arithmetic.
	var repoint_deg: float = director.get("dbg_recovery_repoint_deg")
	var roll_deg: float = director.get("dbg_recovery_roll_deg")

	print("   the largest step is %.2f deg at t=%.3f s, %.2fx its neighbourhood"
		% [worst_step, worst_step_at, _ratio_at(times, deltas, worst_step_at)])
	print("   ...and the worst step in the whole ceremony is %.2fx its "
		% worst_ratio + "neighbourhood, at t=%.3f s" % worst_ratio_at)
	print("   in TRANSLATION the largest step is %.2f mm at t=%.3f s, %.2fx its "
		% [pos_step * 1000.0, pos_step_at, pos_ratio]
		+ "neighbourhood (worst anywhere: %.2fx at t=%.3f s)" % [pos_shape["ratio"],
			pos_shape["at"]])
	print("   its tip walks %.1f deg of path over the turn (the rest of the "
		% turned_k + "phase's %.1f was the cone the sweep used to be)" % turned_phase)
	print("   §23's catch has to find %.1f deg; it splits into %.1f of repoint "
		% [residual, repoint_deg] + "and %.1f of roll to the slot" % roll_deg)

	# =====================================================================
	# ...AND HOW MANY DEGREES OF TURN THE GEOMETRY ACTUALLY WANTS
	# =====================================================================
	# Now that the turn is a roll about the blade's own axis, its SIZE is the one
	# free number left, and the geometry has an opinion about it: of all the roll
	# angles, the one that leaves the least for the catch's roll-to-slot is the
	# one that puts the edge where the koiguchi wants it. If that number is
	# inside §22's band then it is not a taste, it is arithmetic, and it should
	# BE `spin_turns`. If it is outside the band, the two requirements genuinely
	# disagree and it is worth knowing by how much.
	var best := 999.0
	var best_at := 0.0
	for k in 601:
		var t_turns := float(k) / 400.0            # 0.00 .. 1.50 turns
		var landed_at := Basis(own_axis, -TAU * t_turns) * drawn_basis
		var ang := rad_to_deg(
			(landed_at.inverse() * seat_basis).get_rotation_quaternion()
				.angle_to(Quaternion.IDENTITY))
		if ang < best:
			best = ang
			best_at = t_turns
	print("   the geometry's own best: %.1f deg of residual at %.3f turns (%.0f deg)"
		% [best, best_at, best_at * 360.0])

	# =====================================================================
	# WHICH AXIS IS THE TURN ABOUT? (§22, asked as a design question)
	# =====================================================================
	# Kept as a RECORD rather than as a measurement, because it is the one table
	# that settles the question the phase got wrong for two passes. The sweep
	# used to be `Rz` inside the euler, and the euler's Z is TRANSVERSE to the
	# blade -- `+Y` is the tip, the convention `aim_euler` builds. So that sweep
	# swings the tip around a cone, which is why the tip used to walk 376 degrees
	# of path to cover a 306 degree turn, and why the alignment it left behind
	# was 168 degrees. A turn that swings the tip cannot "reset the edge
	# orientation", which is the job §22 gives it: the edge is reset by turning
	# the blade ABOUT ITSELF, which moves the tip not at all.
	var retired := Basis.from_euler(drawn_rot + Vector3(0.0, 0.0, -TAU * tuning.spin_turns))
	var cand_landed: Array[Basis] = [retired, landed]
	var cand_name := ["Rz transverse (retired)", "roll about the blade's own axis"]
	for c in cand_landed.size():
		var row := _split(cand_landed[c], seat_basis)
		print("   %-32s leaves %6.1f deg  = %6.1f repoint + %6.1f roll" % [
			cand_name[c], row["total"], row["repoint"], row["roll"]])
	print("   the tip ends %.4f deg from where it started under the roll, %.1f deg "
		% [rad_to_deg(own_axis.angle_to(cand_landed[1] * Vector3.UP)),
			rad_to_deg(own_axis.angle_to(cand_landed[0] * Vector3.UP))]
		+ "under the cone")
	print("   the drawn pose points the blade %.1f deg off the bore, which is the "
		% rad_to_deg(own_axis.angle_to(seat_basis * Vector3.UP))
		+ "catch's repoint and not the turn's business")

	if trace:
		print("   the whole ceremony turns %.1f deg in %.2f s (reach %.3f m)"
			% [turned, end, reach])

	var fails := 0
	fails += _judge(wrist_k >= WRIST_MIN,
		"the turn (§22) is at least %.0f deg — it turns %.1f" % [WRIST_MIN, wrist_k])
	fails += _judge(wrist_k <= WRIST_MAX,
		"and no more than %.0f (§22's ceiling; two spins is 720) — it turns %.1f"
			% [WRIST_MAX, wrist_k])
	fails += _judge(worst_ratio <= POP_RATIO_LIMIT,
		"no orientation arrives by a jump (worst step is %.2fx its neighbourhood, "
			% worst_ratio + "at t=%.3f s)" % worst_ratio_at)
	# ...and the same test on the other half of the Transform. A position pop is
	# the same fault with the same signature and it was living in this phase at
	# both edges, invisible.
	fails += _judge(pos_ratio <= POP_RATIO_LIMIT,
		"and no POSITION arrives by a jump either (worst step is %.2fx its "
			% pos_ratio + "neighbourhood, at t=%.3f s)" % pos_ratio_at)
	fails += _judge(arrival <= 12.0,
		"the blade reaches the mouth already on the bore's own axis (%.2f deg off it)"
			% arrival)
	fails += _judge(click_gap <= CLICK_GAP_LIMIT,
		"and the click is made by a tsuba AT the mouth (%.2f mm away, limit %.1f)"
			% [click_gap * 1000.0, CLICK_GAP_LIMIT * 1000.0])
	# §23's catch is two well-conditioned rotations, and each of them has to be
	# short. This is what the residual gate became when the single residual slerp
	# was retired: the question is no longer "is the whole residual small", it is
	# "is either HALF of it near-antipodal, because that is the only thing that
	# can make an identity-to-target blend misbehave -- and is the half that has
	# a stated job being done by the thing that is supposed to do it".
	fails += _judge(repoint_deg <= REPOINT_LIMIT,
		"the catch's repoint is an arc, not a reversal (%.1f deg, limit %.0f)"
			% [repoint_deg, REPOINT_LIMIT])
	fails += _judge(roll_deg <= ROLL_LIMIT,
		"and the turn already reset the edge, so little roll is left (%.1f deg, limit %.0f)"
			% [roll_deg, ROLL_LIMIT])

	print("")
	print("   %s" % ("ok   the recovery is one controlled rotation"
		if fails == 0 else "FAIL %d of the recovery's gates" % fails))
	quit(1 if fails > 0 else 0)


## The residual `landed⁻¹ * seat_basis`, split the way §23's catch splits it:
## a REPOINT that carries the blade's direction onto the bore, and a ROLL about
## that bore that carries the spine to the slot. Both are what the identity-blend
## has to travel, so both are what has to stay short.
##
## This is a second copy of the director's arithmetic on purpose: the director
## reports the numbers it uses, and this reports what the numbers OUGHT to be for
## an arbitrary candidate axis. If the two disagree, the director is wrong.
func _split(landed: Basis, seat_basis: Basis) -> Dictionary:
	var bore_dir := (seat_basis * Vector3.UP).normalized()
	var blade_dir := (landed * Vector3.UP).normalized()
	var repoint_deg := rad_to_deg(blade_dir.angle_to(bore_dir))
	var aimed := landed
	if blade_dir.cross(bore_dir).length() > 0.0001:
		aimed = Basis(blade_dir.cross(bore_dir).normalized(),
			blade_dir.angle_to(bore_dir)) * landed
	var from_spine := (aimed * Vector3.RIGHT) \
		- bore_dir * (aimed * Vector3.RIGHT).dot(bore_dir)
	var to_spine := (seat_basis * Vector3.RIGHT) \
		- bore_dir * (seat_basis * Vector3.RIGHT).dot(bore_dir)
	var roll_deg := rad_to_deg(from_spine.normalized().angle_to(to_spine.normalized()))
	var total := rad_to_deg(
		(landed.inverse() * seat_basis).get_rotation_quaternion()
			.angle_to(Quaternion.IDENTITY))
	return {"total": total, "repoint": repoint_deg, "roll": roll_deg}


## The largest step in a series, the largest ratio of a step to its neighbours,
## and where each happened. See `NEIGHBOURHOOD`.
func _shape(times: PackedFloat32Array, deltas: PackedFloat32Array) -> Dictionary:
	var ratio := 0.0
	var ratio_at := 0.0
	var step := 0.0
	var step_at := 0.0
	for i in deltas.size():
		var neighbour := _neighbour(deltas, i)
		if neighbour > 0.0001:
			var r := deltas[i] / neighbour
			if r > ratio:
				ratio = r
				ratio_at = times[i]
		if deltas[i] > step:
			step = deltas[i]
			step_at = times[i]
	return {"ratio": ratio, "at": ratio_at, "step": step, "step_at": step_at}


## The largest step beside `i`, excluding `i` itself.
func _neighbour(deltas: PackedFloat32Array, i: int) -> float:
	var neighbour := 0.0
	for j in range(maxi(i - NEIGHBOURHOOD, 0), mini(i + NEIGHBOURHOOD + 1, deltas.size())):
		if j != i:
			neighbour = maxf(neighbour, deltas[j])
	return neighbour


## The neighbourhood ratio at a remembered instant, for the report.
func _ratio_at(times: PackedFloat32Array, deltas: PackedFloat32Array,
		at: float) -> float:
	for i in times.size():
		if not is_equal_approx(times[i], at):
			continue
		var neighbour := _neighbour(deltas, i)
		return deltas[i] / neighbour if neighbour > 0.0001 else 0.0
	return 0.0


func _running(deltas: PackedFloat32Array, upto: int) -> float:
	var sum := 0.0
	for i in range(upto + 1):
		sum += deltas[i]
	return sum


func _judge(condition: bool, reason: String) -> int:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	return 0 if condition else 1
