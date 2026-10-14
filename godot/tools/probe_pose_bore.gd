extends SceneTree
## PROBE · DOES THE AUTHORED PATH EVER TAKE A SEATED BLADE OFF ITS BORE?
##
## ===========================================================================
## THE DETERMINISTIC HALF OF `probe_blade_clearance.gd`
## ===========================================================================
## `probe_blade_clearance.gd` is the right gate: it measures the RENDERED node,
## which is what the player sees and what §27 is about. But it can only see the
## pose at 60 Hz, gated on a trigger, through whatever phase the physics tick
## happens to land on -- and a fault that lives in one or two frames then reports
## DIFFERENTLY ON DIFFERENT RUNS. A3 did exactly that: four consecutive runs gave
## 0.0076 m, 0.0171 m, 0.0250 m and 0.0416 m for the same beat list.
##
## A number that changes run to run cannot be authored against. So this probe
## asks the same question of the BEAT LIST ITSELF, deterministically:
##
##     blade(t) = SwordPoseSampler.sample(move, t)
##     saya(t)  = the move's own `saya_ctrl_*` / `saya_*` beats, or the anchor
##
## sampled at `DT` = 1/600 s, with no scene, no trigger, no spring and no rider
## layer. Whatever it reports is the author's, so whatever it reports can be
## fixed in the beat list.
##
## ===========================================================================
## WHAT IT IS NOT
## ===========================================================================
## It is NOT a replacement for the rendered gate. A clean answer here means the
## beats are right; it says nothing about `TempSwordVisual`'s filter, the rider
## layers or the left hand, all of which sit downstream and all of which have put
## a blade through a wall on their own. Both probes have to be green. This one
## names the SEGMENT; that one is the verdict.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_pose_bore.gd
##   POSE_BORE_TRACE=a3 ... to dump one move, segment by segment.

const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")

## The same geometry the rendered probe uses, and deliberately the same numbers
## rather than a second opinion about them: `BLADE_SORI` is the registry's own
## measurement of the blade's centreline, and the allowance is the two curves'
## mismatch plus the fit's clearance.
const BLADE_SORI := 0.0131
const TRANSVERSE_LIMIT := (SwordClasses.BORE_SORI - BLADE_SORI) + SwordClasses.FIT_CLEAR
const MIN_INSERTED := 0.010
const ENGAGED := 0.060

## Six hundred samples a second: ten per rendered frame at 60 Hz, so a one-frame
## fault cannot hide between samples, and a 1.00 s move costs 600 evaluations.
const DT := 1.0 / 600.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("")
	print("── the numbers this probe's limits come from")
	print("   limit %.5f m · sampled every %.4f s, off the beat list, no scene"
		% [TRANSVERSE_LIMIT, DT])

	var fails: Array[String] = []
	var worst := 0.0
	var worst_name := ""
	var worst_where := ""

	# Typed loop variable rather than a bare one: `moves()` returns an untyped
	# `Array` once `equip()` is appended, and an untyped element makes every
	# `move.foo()` a Variant, which is a parse error under `:=`.
	for move: SwordMove in _roster():
		var r := _walk(move)
		print("   %-10s %7.3f s %6d samples   worst %.4f m %s" % [
			move.id, move.total_time(), r["count"], r["worst"], r["where"]])
		if float(r["worst"]) > worst:
			worst = float(r["worst"])
			worst_name = String(move.id)
			worst_where = String(r["where"])
		if float(r["worst"]) >= TRANSVERSE_LIMIT:
			fails.append("%s: %.4f m %s" % [move.id, r["worst"], r["where"]])

	print("")
	var verdict := "every seated sample of every move is on its bore"
	if worst >= TRANSVERSE_LIMIT:
		verdict = "a seated blade leaves its bore in the beat list itself"
	_judge(fails.is_empty(), "%s (worst %.4f m of %.4f m allowed, in `%s` %s)"
		% [verdict, worst, TRANSVERSE_LIMIT, worst_name, worst_where])
	for f in fails:
		print("        %s" % f)

	var want := OS.get_environment("POSE_BORE_TRACE")
	if want != "":
		_trace(want)
	else:
		print("")
		print("   set POSE_BORE_TRACE=<id> to dump one move, segment by segment")
	quit(1 if not fails.is_empty() else 0)


## Every move this probe is responsible for: the four cuts and the draw. The
## draw is in the list because it is the act that seats and unseats a blade for a
## living, and the four cuts are in it because each of them opens by putting the
## blade home.
func _roster() -> Array[SwordMove]:
	var list: Array[SwordMove] = SwordBasic.moves()
	list.append(SwordBasic.equip())
	return list


## Walks one move at `DT` and returns its worst seated departure, with the beat
## segment it happened in. The segment index is the point of the exercise: it is
## the only thing that says WHICH two beats to move.
func _walk(move: SwordMove) -> Dictionary:
	var total := move.total_time()
	var worst := 0.0
	var where := ""
	var count := 0
	var steps := int(ceil(total / DT))
	for i in steps + 1:
		var t := minf(float(i) * DT, total)
		var blade := SwordPoseSampler.sample(move, t)
		if blade.is_empty():
			continue
		var saya := _saya_at(move, t)
		var m := _measure(saya["position"], saya["rotation"],
			blade["position"], blade["rotation"])
		if not _seated(m):
			continue
		count += 1
		if float(m["transverse"]) > worst:
			worst = float(m["transverse"])
			where = "at t=%.3f s (%s), tip %.3f m inside" % [
				t, _segment(blade), float(m["inserted"])]
	return {"worst": worst, "where": where, "count": count}


## Which stretch of the move a sample is in, spelled the same way for a beat list
## and for a phase move -- because the two are the same question ("which two keys
## does this sit between") and a report that named one of them differently would
## send the reader to the wrong half of the file.
func _segment(blade: Dictionary) -> String:
	var phase := StringName(blade["phase"])
	if phase == &"beat":
		return "beat %d→%d, u=%.3f" % [int(blade["phase_index"]),
			int(blade["phase_index"]) + 1, float(blade["progress"])]
	return "%s, u=%.3f" % [phase, float(blade["progress"])]


## Where the scabbard is at `t`, by the same precedence `CombatController` uses:
## the move's control beats if it has them, else its absolute beats, else the
## seating anchor. Written here rather than called through the controller because
## this probe has no scene -- and the precedence is three lines, so the cost of
## it being a second copy is that a change has to be made in two places, which is
## cheaper than a probe that cannot run without a world.
func _saya_at(move: SwordMove, t: float) -> Dictionary:
	if move.has_saya_ctrl():
		var off := SwordPoseSampler.sample_arrays(
			move.saya_ctrl_times, move.saya_ctrl_positions,
			move.saya_ctrl_rotations, PackedVector3Array(), t)
		if not off.is_empty():
			return {
				"position": SwordBasic.SAYA_MOUTH + off["position"],
				"rotation": SwordBasic.SAYA_MOUTH_R + off["rotation"],
			}
	if move.has_saya_beats():
		var shot := SwordPoseSampler.sample_arrays(
			move.beat_times, move.saya_positions, move.saya_rotations,
			move.saya_bows, t)
		if not shot.is_empty():
			return shot
	return {"position": SwordBasic.SAYA_MOUTH, "rotation": SwordBasic.SAYA_MOUTH_R}


func _measure(saya_position: Vector3, saya_rotation: Vector3,
		origin: Vector3, blade_rotation: Vector3) -> Dictionary:
	var saya_axis := Basis.from_euler(saya_rotation) * Vector3.UP
	var blade_axis := Basis.from_euler(blade_rotation) * Vector3.UP
	var along := saya_position - origin
	var depth := along.dot(blade_axis)
	var transverse := (along - blade_axis * depth).length()
	var angle := rad_to_deg(blade_axis.angle_to(saya_axis))
	if angle > 90.0:
		angle = 180.0 - angle
	return {
		"inserted": SwordClasses.blade_reach(SwordBasic.WEAPON_ID) - depth,
		"depth": depth,
		"transverse": transverse,
		"angle": angle,
	}


func _seated(m: Dictionary) -> bool:
	if float(m["inserted"]) <= MIN_INSERTED:
		return false
	if float(m["depth"]) < -SwordClasses.FIT_CLEAR:
		return false
	return float(m["transverse"]) <= ENGAGED


## Segment by segment, so a bad one can be read against its own two beats.
func _trace(want: String) -> void:
	for move: SwordMove in _roster():
		if String(move.id) != want:
			continue
		print("")
		print("── trace · %s, %.3f s, %d beats" % [
			move.id, move.total_time(), move.beat_times.size()])
		print("   %7s %5s %6s %9s %9s %9s %-24s %-24s" % [
			"t", "beat", "u", "insert", "transv", "angle", "from pos", "to pos"])
		var total := move.total_time()
		var steps := int(ceil(total / DT))
		for i in steps + 1:
			var t := minf(float(i) * DT, total)
			var blade := SwordPoseSampler.sample(move, t)
			if blade.is_empty():
				continue
			var saya := _saya_at(move, t)
			var m := _measure(saya["position"], saya["rotation"],
				blade["position"], blade["rotation"])
			if not _seated(m):
				continue
			var b := int(blade["phase_index"])
			# Only the frames near a segment's start, plus every bad frame: a
			# 600-point dump is unreadable and the fault is never in the middle of
			# a segment that begins and ends on the bore.
			var u := float(blade["progress"])
			var bad := float(m["transverse"]) >= TRANSVERSE_LIMIT
			# Every seated sample when asked for; otherwise only the ones near a
			# segment's own ends, plus every bad one. A 600-point dump is
			# unreadable, and the middle of a segment that begins and ends on the
			# bore cannot be the fault -- which is a claim worth being able to
			# check, so `POSE_BORE_ALL=1` checks it.
			if OS.get_environment("POSE_BORE_ALL") == "" \
					and not bad and u > 0.02 and u < 0.98:
				continue
			print("   %7.3f %5d %6.3f %9.3f %9.4f %9.3f %-24s %-24s%s" % [
				t, b, u, float(m["inserted"]), float(m["transverse"]),
				float(m["angle"]), _v3(move.beat_positions[b]),
				_v3(move.beat_positions[b + 1]), "  *" if bad else ""])


func _v3(p: Vector3) -> String:
	return "(%+.3f,%+.3f,%+.3f)" % [p.x, p.y, p.z]


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
