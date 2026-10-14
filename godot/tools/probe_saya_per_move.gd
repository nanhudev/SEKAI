extends SceneTree
## PROBE · §34 MOTION METRICS, ONE ACT AT A TIME
##
## ===========================================================================
## WHY THIS EXISTS, AND WHAT IT IS REPLACING
## ===========================================================================
## §34 asks for a number per act:
##
##   "A1 saya travel / A2 saya travel / A3 saya travel / A4 saya travel"
##
## and says why: "避免下次又悄悄变成大幅跟 Sword" -- so that the saya can never
## quietly go back to following the sword.
##
## The line already had a probe that LOOKS like it answers this.
## `probe_saya_motion.gd` files five legs under the names `a1`, `a1-again`, `a2`,
## `a3`, `a4`. Measured by `tools/probe_chain_identity.gd`, that probe's own
## timing (1.1 s of idle between requests, against a 0.90 s `combo_window`)
## resets the chain every time, so all five of its requests produce `sb_a1`:
##
##   A#1 combo_index=1 active_move_id=sb_a1
##   A#2 combo_index=1 active_move_id=sb_a1
##   ... A#5 combo_index=1 active_move_id=sb_a1
##
## THE THREE ROWS IT LABELS a2/a3/a4 ARE A1. A2, A3 and A4 have never been
## measured on the live rig by anything, which also means §35's A/B/C/D gates
## about them ("saya follows the sword", "A3 the sword crosses the saya", "A4 the
## blade touches the saya") were never gates: a gate that cannot be reached is
## decoration.
##
## So this file measures the four acts, and it does the two things the old one
## did not:
##
##   1  IT ADVANCES THE CHAIN THE WAY A PLAYER DOES -- by cancelling into the
##      next cut inside the window (`_can_cancel`), and then ASSERTING that the
##      move that started is the one that was asked for. An unchecked `request`
##      is exactly how four acts went missing once already; see the note in
##      `saya_controlled_stillness_movie.gd` that says so.
##
##   2  IT MEASURES ROTATION AS WELL AS TRANSLATION. §34 asks for both, and §2
##      gives both a band (2-8 cm, 3-15 deg). A travel-only probe cannot see a
##      scabbard that holds its position and spins.
##
## All positions are in WeaponRoot's space, which is the space the sheathed
## seating is written in -- the same space `probe_saya_motion.gd` measures the
## mouth in, so the two files' numbers can be compared.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_saya_per_move.gd

const WEAPON_ROOT := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"
const SWORD_PATH := WEAPON_ROOT + "/TempSwordVisual"

const SwordPoseSampler := preload("res://scripts/combat/sword_pose_sampler.gd")
## Read as a table, which is what it is: the draw's absolute scabbard beats live
## here, and the probe has to read the SAME ones the controller places from.
const SwordBasicScript := preload("res://scripts/combat/sword_basic.gd")

## A hand has no mechanism to teleport, so this is the one number that must be
## small in every act. Same value and same reason as `probe_saya_motion.gd`.
##
## Expressed PER RENDERED FRAME AT 60 Hz, i.e. as a speed divided by 60, because
## a raw per-frame step measured in a headless run is a measurement of this
## machine's frame rate and not of the rig. The raw step is still printed next to
## it, labelled as what it is.
const JUMP_LIMIT := 0.020
const SPEED_WINDOW := 0.030

## §34's bands, PER ACT AND SOURCED FROM THE BRIEF RATHER THAN FROM THE CODE.
##
## Taking them from the authored `saya_ctrl_*` values would make every gate pass
## by construction -- it would assert that the code equals itself, and no future
## change to a track could ever fail it. These come from the brief's own numbers:
##
##   §2   ordinary combat: 2-8 cm of travel, 3-15 deg
##   §8   A1's counter-pull: 3-6 cm, 5-10 deg
##   §10  A2: 3-8 cm, and "a small angle is enough"
##   §12  A3: "very stable". Its anchor is deliberately NOT rotated, and the
##        source argues why -- 5 deg of mouth turn is 20 mm of blade direction at
##        the tip of a blade 0.71 m inside a tube with 1.75 mm of clearance. So
##        A3 is the one act where a near-zero rotation is the ANSWER and a
##        rotation floor would be inventing a fault.
##   §17  A4: "the one act where a large excursion is not a fault", and §17
##        forbids leaving the frame as the way to get out of the blade's path, so
##        even here the ceiling is bounded.
const BANDS := {
	&"sb_a1": {"pos_lo": 0.030, "pos_hi": 0.080, "rot_lo": 2.0, "rot_hi": 15.0},
	&"sb_a2": {"pos_lo": 0.030, "pos_hi": 0.080, "rot_lo": 2.0, "rot_hi": 15.0},
	&"sb_a3": {"pos_lo": 0.020, "pos_hi": 0.080, "rot_lo": 0.0, "rot_hi": 2.0},
	&"sb_a4": {"pos_lo": 0.030, "pos_hi": 0.090, "rot_lo": 2.0, "rot_hi": 15.0},
}

## §35-A, as a number. "Saya starts following the sword again, largely
## synchronised" is the first thing that gate forbids -- so the saya's travel is
## expressed as a FRACTION of the sword's. A controlled hold is a small fraction
## of a big cut; a follower is near 1.0.
const COUPLING_MAX := 0.50

## How far the scabbard's mouth may leave the hand that is holding it.
##
## The scabbard is 36 mm across and the hand grips it at the koiguchi, so a mouth
## more than a quarter of its own width from the hand is a hand that is not on
## it. This is §27's "Saya vs Left Hand" class read from the other side -- not a
## mesh crossing a mesh, but a held object letting go -- and it is the one
## relationship §30's arm mechanics depend on: an arm solved onto the hand cannot
## show a scabbard that has left the hand, however correct the scabbard's own
## trajectory is.
##
## The rest gap is zero by construction (the hand's rest IS `saya_home`), so any
## separation this reports during an act is exactly the act's own offset applied
## to the scabbard instead of to the hand.
const GRIP_GAP_MAX := 0.010

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var manager: Node
var weapon_root: Node3D
var sword: Node3D

var _samples: Array[Dictionary] = []
var _fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	await _frames(14)
	player = world.get_node("Player")
	combat = player.get_node("CombatController")
	manager = player.get_node_or_null("WeaponManager")
	if combat == null or manager == null or combat.saya_rig == null:
		print("FAIL: no combat controller, manager or saya rig")
		quit(1)
		return
	weapon_root = player.get_node_or_null(WEAPON_ROOT)
	sword = player.get_node_or_null(SWORD_PATH)
	if weapon_root == null or sword == null:
		print("FAIL: no WeaponRoot or no TempSwordVisual")
		quit(1)
		return

	var chain: Array = combat.moveset.light_chain
	print("")
	print("   chain %s · combo_window %.2f s" % [str(chain), combat.moveset.combo_window])
	# NO SEPARATE "TAKE THE SWORD OUT" STEP. The sandbox starts holding it, and the
	# only way to measure a draw is to put the sword away and take it out again --
	# which is what `_measure_draw` does. A preamble draw would be a second one, and
	# the four cuts need it out anyway, so it leaves the rig where they need it.
	var rows: Array[Dictionary] = []
	# THE DRAW FIRST, because it has to put the sword away again to be measured and
	# that is cheap here and awkward later. It is also where §30's arm claim is
	# hardest: the scabbard climbs from the waist to the combat rest, so a hand that
	# does not come with it is a hand 25 cm from what it is holding.
	rows.append(await _measure_draw())
	for index in 4:
		var row := await _measure(index, String(chain[index]))
		rows.append(row)

	_report(rows)
	_release()
	quit(1 if not _fails.is_empty() else 0)


## The world is a node this script added, so it is a node this script has to take
## away. Quitting with it installed reports both an instance leak and a script
## still in use -- i.e. a probe printing errors on a clean run, which is the
## fastest way to teach the next reader to ignore its output.
func _release() -> void:
	if world != null and is_instance_valid(world):
		root.remove_child(world)
		world.free()
	world = null
	sword = null
	weapon_root = null


# ===========================================================================
# One act
# ===========================================================================

## The draw, measured on the REAL entrance: the sword is put away through the
## weapon switch and taken out again, and the scabbard is sampled the whole way.
##
## A DIFFERENT SHAPE OF ACT, which is why it gets its own function. The four cuts
## move the scabbard by an OFFSET from the hand; the draw authors its whole pose
## (`saya_positions`), so there is no `saya_ctrl_*` track to compare against and
## the authored number is the excursion of the absolute beats instead.
##
## Its `index` is -1 on purpose: `_report` gates the four cuts against §2's band,
## and this act is not one of them -- it is allowed 25 cm, because a draw that
## moves the scabbard less than the distance from the waist to the combat rest is
## not a draw.
func _measure_draw() -> Dictionary:
	await _ensure_idle()
	_samples.clear()
	var row := {"index": -1, "id": "draw", "got": "draw", "ok": true,
		"travel": 0.0, "rot": 0.0, "jump": 0.0, "leap60": 0.0, "sword": 0.0,
		"hand": 0.0, "gap": 0.0, "authored_pos": 0.0, "authored_rot": 0.0,
		"path": 0.0}
	manager.call("equip_weapon", WeaponSlot.CHAIN)
	await _sleep(3.2)
	var equip: SwordMove = SwordBasicScript.equip()
	row["authored_pos"] = _authored_absolute(equip)
	row["authored_rot"] = _authored_absolute_rot(equip)
	manager.call("equip_weapon", WeaponSlot.SWORD)
	var guard := 0
	while guard < 6000:
		_sample()
		if float(combat.equip_blend) >= 0.999 \
				and combat.state == CombatController.State.IDLE:
			break
		await process_frame
		guard += 1
	_sample()
	row["travel"] = _excursion_pos()
	row["rot"] = _excursion_rot()
	row["jump"] = _max_step()
	row["leap60"] = _peak_speed() / 60.0
	row["path"] = _path_len()
	row["hand"] = _hand_excursion()
	row["gap"] = _max_gap()
	print("   draw the draw    travel %5.1f mm · rot %5.1f deg · leap@60 %4.1f mm · hand %4.1f mm · grip gap %5.1f mm" % [
		float(row["travel"]) * 1000.0, row["rot"], float(row["leap60"]) * 1000.0,
		float(row["hand"]) * 1000.0, float(row["gap"]) * 1000.0])
	return row


## The widest distance between any two positions the draw's own beats visit.
func _authored_absolute(move: SwordMove) -> float:
	var widest := 0.0
	var pts := move.saya_positions
	for a in pts.size():
		for b in range(a + 1, pts.size()):
			widest = maxf(widest, pts[a].distance_to(pts[b]))
	return widest


func _authored_absolute_rot(move: SwordMove) -> float:
	var widest := 0.0
	var rots := move.saya_rotations
	for a in rots.size():
		for b in range(a + 1, rots.size()):
			widest = maxf(widest, SwordPoseSampler.angle_between(
				Basis.from_euler(rots[a]).get_rotation_quaternion(),
				Basis.from_euler(rots[b]).get_rotation_quaternion()))
	return widest


## Plays chain act `index` for real and measures it. The earlier acts are run at
## full speed and cancelled into, exactly as `_take_cut` in the movie does, so the
## reviewed act arrives on a body that has already committed rather than on a
## fresh idle.
func _measure(index: int, expected: String) -> Dictionary:
	await _ensure_idle()
	_samples.clear()
	var row := {"index": index, "id": expected, "got": "", "ok": false,
		"travel": 0.0, "rot": 0.0, "jump": 0.0, "leap60": 0.0, "sword": 0.0,
		"hand": 0.0, "gap": 0.0, "authored_pos": 0.0, "authored_rot": 0.0,
		"path": 0.0}

	var move := combat.moveset.get_move(StringName(expected))
	if move == null:
		_fails.append("act %d: the chain names %s but the moveset has no such move" % [
			index + 1, expected])
		return row
	row["authored_pos"] = _authored_pos(move)
	row["authored_rot"] = _authored_rot(move)

	for i in index:
		if not combat.request(&"light"):
			_fails.append("A%d could not be reached: request refused" % (index + 1))
			return row
		if not await _advance_to_cancel():
			_fails.append("A%d could not be reached: the cancel window was missed" % (
				index + 1))
			return row

	if not combat.request(&"light"):
		_fails.append("A%d refused a light attack (state=%s)" % [
			index + 1, _state_name(combat.state)])
		return row
	await _frames(2)
	row["got"] = String(combat.active_move_id)
	row["ok"] = combat.active_move_id == StringName(expected)
	if not row["ok"]:
		# THE WHOLE POINT OF THIS FILE. Say which move actually started.
		_fails.append("A%d: asked for %s and got %s" % [
			index + 1, expected, row["got"]])
		return row

	await _capture_until_idle()

	row["travel"] = _excursion_pos()
	row["rot"] = _excursion_rot()
	row["jump"] = _max_step()
	row["leap60"] = _peak_speed() / 60.0
	row["path"] = _path_len()
	row["sword"] = _sword_excursion()
	row["hand"] = _hand_excursion()
	row["gap"] = _max_gap()
	print("   A%d %-8s travel %5.1f mm · rot %5.1f deg · leap@60 %4.1f mm · hand %4.1f mm · grip gap %5.1f mm" % [
		index + 1, row["got"], float(row["travel"]) * 1000.0, row["rot"],
		float(row["leap60"]) * 1000.0, float(row["hand"]) * 1000.0,
		float(row["gap"]) * 1000.0])
	return row


## Samples until the sentence is over. One sample per combat tick, because
## `combat_time` is accumulated in the controller's `_process` -- so a sample per
## process frame is a sample per unit of the clock the moves are timed on.
func _capture_until_idle() -> void:
	var guard := 0
	while guard < 4000:
		_sample()
		if combat.state == CombatController.State.IDLE and combat.state_time > 0.10:
			break
		await process_frame
		guard += 1
	_sample()


## The player's own way of continuing a sentence: wait until the controller says
## the current cut may be cancelled into the next one. Reusing `_can_cancel`
## rather than re-deriving the window means the probe cannot disagree with the
## game about when a chain may continue.
func _advance_to_cancel() -> bool:
	var guard := 0
	while guard < 600:
		if combat.state == CombatController.State.IDLE:
			return false
		if combat.active_move != null and bool(combat.call("_can_cancel", &"light")):
			return true
		await process_frame
		guard += 1
	return false


func _ensure_idle() -> void:
	if combat.state != CombatController.State.IDLE:
		var guard := 0
		while guard < 4000 and combat.state != CombatController.State.IDLE:
			await process_frame
			guard += 1
	# Longer than the combo window with nothing asked, so the next request starts
	# the sentence at A1 rather than resuming whatever the last act left behind.
	await _sleep(combat.moveset.combo_window + 0.25)


# ===========================================================================
# Sampling and metrics
# ===========================================================================

func _sample() -> void:
	_samples.append({
		"saya": combat.saya_rig.mouth_point(),
		"saya_q": combat.saya_rig.transform.basis.get_rotation_quaternion(),
		"sword": sword.position,
		"hand": _hand_pos(),
		"t": combat.combat_time,
	})


## Where the LEFT HAND's control point is, in the same space as the mouth. This
## exists because of the project's own rule for hard constraints: a probe that
## measures one object cannot see a wrong RELATIONSHIP between two. "The scabbard
## is held by the hand" is a relationship, and it is the one §1/§3/§27/§30 are
## entirely about -- so it gets its own number rather than being implied by the
## scabbard's own motion being plausible.
func _hand_pos() -> Vector3:
	if combat.saya_hand != null and is_instance_valid(combat.saya_hand):
		return combat.saya_hand.position
	return Vector3.ZERO


func _excursion_pos() -> float:
	var widest := 0.0
	for a in _samples.size():
		for b in range(a + 1, _samples.size()):
			widest = maxf(widest, _samples[a]["saya"].distance_to(_samples[b]["saya"]))
	return widest


func _excursion_rot() -> float:
	var widest := 0.0
	for a in _samples.size():
		for b in range(a + 1, _samples.size()):
			widest = maxf(widest, SwordPoseSampler.angle_between(
				_samples[a]["saya_q"], _samples[b]["saya_q"]))
	return widest


func _sword_excursion() -> float:
	var widest := 0.0
	for a in _samples.size():
		for b in range(a + 1, _samples.size()):
			widest = maxf(widest, _samples[a]["sword"].distance_to(_samples[b]["sword"]))
	return widest


## How far the HAND itself travels. If this is near zero while the mouth travels
## 76 mm, then the scabbard is being displaced relative to the hand that is
## supposedly gripping it -- which is a statement about the grip, not about the
## scabbard's silhouette, and nothing that measures the scabbard alone can see it.
func _hand_excursion() -> float:
	var widest := 0.0
	for a in _samples.size():
		for b in range(a + 1, _samples.size()):
			widest = maxf(widest, _samples[a]["hand"].distance_to(_samples[b]["hand"]))
	return widest


## The furthest the mouth ever gets from the hand over the act -- the grip's own
## separation. §27 lists "Saya vs Left Hand" as a P0 interpenetration class, and
## a scabbard that slides through a stationary grip is that class arrived at from
## the other side: not a mesh crossing a mesh, but a held object letting go.
func _max_gap() -> float:
	var widest := 0.0
	for s in _samples:
		widest = maxf(widest, s["saya"].distance_to(s["hand"]))
	return widest


func _max_step() -> float:
	var worst := 0.0
	for i in range(1, _samples.size()):
		worst = maxf(worst, _samples[i - 1]["saya"].distance_to(_samples[i]["saya"]))
	return worst


func _path_len() -> float:
	var total := 0.0
	for i in range(1, _samples.size()):
		total += _samples[i - 1]["saya"].distance_to(_samples[i]["saya"])
	return total


## The fastest the mouth travels over any `SPEED_WINDOW` of the act, in m/s. A
## window rather than a single frame because one frame's displacement is a
## function of the frame rate, and the number this file has to produce is a
## property of the rig. `leap@60` is this divided by 60.
func _peak_speed() -> float:
	var peak := 0.0
	for i in _samples.size():
		var j := i + 1
		while j < _samples.size() and _samples[j]["t"] - _samples[i]["t"] < SPEED_WINDOW:
			j += 1
		if j >= _samples.size():
			break
		var span: float = _samples[j]["t"] - _samples[i]["t"]
		if span <= 0.0:
			continue
		peak = maxf(peak, _samples[i]["saya"].distance_to(_samples[j]["saya"]) / span)
	return peak


## What the act's own `saya_ctrl_*` track asks for, so the delivered number has
## something to be wrong AGAINST. A move that authors 76 mm and delivers 49 mm is
## a different fault from a move that authors 49 mm, and only having both numbers
## tells them apart.
func _authored_pos(move: SwordMove) -> float:
	var peak := 0.0
	for p in move.saya_ctrl_positions:
		peak = maxf(peak, p.length())
	return peak


func _authored_rot(move: SwordMove) -> float:
	var peak := 0.0
	for r in move.saya_ctrl_rotations:
		peak = maxf(peak, SwordPoseSampler.angle_between(
			Quaternion.IDENTITY, Basis.from_euler(r).get_rotation_quaternion()))
	return peak


# ===========================================================================
# Verdict
# ===========================================================================

func _report(rows: Array[Dictionary]) -> void:
	print("")
	print("=".repeat(78))
	print("§34 · MOTION METRICS, PER ACT")
	print("=".repeat(78))
	print("   %-4s %-8s %9s %9s %7s %9s %8s %8s %7s %8s %8s" % [
		"act", "move", "authored", "travel", "deg", "leap@60", "raw", "hand",
		"grip", "sword", "say/bl"])
	for row in rows:
		var travel := float(row["travel"])
		var coupling := 0.0
		if float(row["sword"]) > 0.0001:
			coupling = travel / float(row["sword"])
		print("   %-5s %-8s %7.1f mm %7.1f mm %5.1f° %7.1f mm %6.1f mm %6.1f mm %5.1f mm %6.0f mm %7.2f" % [
			_label(row), row["got"], float(row["authored_pos"]) * 1000.0,
			travel * 1000.0, row["rot"], float(row["leap60"]) * 1000.0,
			float(row["jump"]) * 1000.0, float(row["hand"]) * 1000.0,
			float(row["gap"]) * 1000.0, float(row["sword"]) * 1000.0, coupling])
	print("   (`raw` is one frame's step on THIS machine and is frame-rate dependent;"
		+ " `leap@60` is the same motion expressed as a 60 Hz frame, and is the gate)")
	print("   (`grip` is how far the scabbard's mouth gets from the hand holding it;"
		+ " `hand` is how far the hand itself travels. If `hand` is ~0 while `grip`"
		+ " is large, the act moves the SCABBARD and not the HAND)")
	print("")

	# 1 · identity. Everything below is void if the acts are not the acts.
	var identified := true
	for row in rows:
		if not bool(row["ok"]):
			identified = false
	_judge(identified,
		"each of the four acts played the move it was asked for (this is the check the "
		+ "old probe lacked, and without it a2/a3/a4 measure A1)")

	if not identified:
		print("   the metrics below are reported but NOT gated: they are not the "
			+ "acts they are labelled as")
		print("P_SAYA_PER_MOVE DONE")
		return

	for row in rows:
		var who := _label(row)
		var travel := float(row["travel"])
		var is_cut := int(row["index"]) >= 0

		# THE GRIP GATE APPLIES TO EVERY ACT, INCLUDING THE DRAW. "Is the scabbard
		# in the hand" is not a property of ordinary combat; it is a property of
		# being a held object, and the draw is where the two are furthest apart.
		_judge(float(row["gap"]) <= GRIP_GAP_MAX,
			"%s keeps the scabbard IN THE HAND'S GRIP: the mouth never gets more than %.0f mm from the hand (got %.1f)"
				% [who, GRIP_GAP_MAX * 1000.0, float(row["gap"]) * 1000.0])
		_judge(float(row["leap60"]) <= JUMP_LIMIT,
			"%s never shows more than %.0f mm of mouth travel in a 60 Hz frame (got %.1f)"
				% [who, JUMP_LIMIT * 1000.0, float(row["leap60"]) * 1000.0])

		# The §2 band is the four cuts'. The draw is exempt on purpose and the
		# reason is a distance: it moves the scabbard from the waist to the combat
		# rest, and §2's 2-8 cm is a band for a cut.
		if not is_cut:
			continue
		var band: Dictionary = BANDS[StringName(row["got"])]
		_judge(travel >= float(band["pos_lo"]),
			"%s moves the saya at least %.0f mm (P0-1: a still saya is a world-space prop; got %.1f)"
				% [who, float(band["pos_lo"]) * 1000.0, travel * 1000.0])
		_judge(travel <= float(band["pos_hi"]),
			"%s keeps the saya inside its %.0f mm ceiling (got %.1f)"
				% [who, float(band["pos_hi"]) * 1000.0, travel * 1000.0])
		_judge(float(row["rot"]) >= float(band["rot_lo"])
				and float(row["rot"]) <= float(band["rot_hi"]),
			"%s turns the saya within %.0f-%.0f° for this act (got %.1f)"
				% [who, float(band["rot_lo"]), float(band["rot_hi"]), row["rot"]])
		var coupling := 0.0
		if float(row["sword"]) > 0.0001:
			coupling = travel / float(row["sword"])
		_judge(coupling <= COUPLING_MAX,
			"%s does not follow the sword: saya travel is %.0f%% of the blade's (limit %.0f%%)"
				% [who, coupling * 100.0, COUPLING_MAX * 100.0])

	print("")
	print("── authored vs delivered")
	for row in rows:
		var authored := float(row["authored_pos"])
		var delivered := float(row["travel"])
		# The authored value is a PEAK OFFSET for a cut and an EXCURSION for the
		# draw, and the delivered value is always an excursion. They are the same
		# quantity for a cut only when its offset starts and ends at zero, which
		# every act's track does. A delivered value well under the authored one
		# means the track is not being reached.
		print("   %-5s authored %6.1f mm · delivered %6.1f mm · ratio %.2f" % [
			_label(row), authored * 1000.0, delivered * 1000.0,
			delivered / maxf(authored, 0.0001)])
	print("")
	print("P_SAYA_PER_MOVE DONE")


# ===========================================================================
# Plumbing
# ===========================================================================

func _blade_is_out() -> bool:
	return combat.state != CombatController.State.IDLE or float(combat.equip_blend) >= 0.999


func _sleep(seconds: float) -> void:
	var deadline := combat.combat_time + seconds
	while combat.combat_time < deadline:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## The act's name as it is printed and gated. The draw carries `index` -1 so that
## the four cuts are the only rows §2's band applies to; this is the one place that
## turns the sentinel back into a word.
func _label(row: Dictionary) -> String:
	if int(row["index"]) < 0:
		return String(row["id"])
	return "A%d" % (int(row["index"]) + 1)


func _state_name(state: int) -> String:
	var names := ["IDLE", "ATTACK", "RIPOSTE", "SKILL", "CHARGE", "BLOCK", "PARRY",
		"CAST", "DODGE"]
	return names[state] if state >= 0 and state < names.size() else str(state)


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)
