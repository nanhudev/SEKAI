extends SceneTree
## PROBE · THE FIVE-BEAT DRAW CONTRACT (§2 / §3 of SWORD PRESENTATION V3)
##
## ===========================================================================
## WHAT THIS ASSERT, AND WHY EACH ONE IS A REAL QUESTION
## ===========================================================================
## A draw is easy to ship broken, because every way it can be wrong still looks
## like a draw at a glance. Each check below exists because it can FAIL while the
## picture still reads as fine:
##
##   1  THE PAUSE IS A PAUSE. §3 Beat 2 asks for 120-250 ms of the blade NOT
##      MOVING. A movement that merely slows to a crawl for 200 ms looks
##      identical in a screenshot and is a different thing to play; a straight
##      lerp can only ever produce the second. So this asks how far the blade
##      moves across the window, and requires it to be zero.
##
##   2  THE SAYA DOES NOT GO WITH THE BLADE (§2). This is the whole of "one
##      weapon system, two actors". If the sheath follows the blade out of itself
##      the picture is a single rigid object sliding, which is exactly the thing
##      the brief forbids — and it also looks plausible. So: while the blade
##      travels its full 0.76 m, the mouth must not move.
##
##   3  THERE IS BOW WHERE THERE IS CURVATURE, AND NONE WHERE THERE IS NOT. The
##      registry's measured bore curve is 16.4 mm over 0.79 m; a bow on a segment
##      whose endpoints are equal is invented motion, so the hold and the glint
##      must have none. Checking the shape of a rule is how the rule stops being a
##      slogan.
##
##   4  THE TWO OWNERS OF ONE NUMBER AGREE. `WeaponManager.DRAW_SECONDS` is a
##      `const` and `SwordBasic.equip()` is a function, so they can drift, and if
##      they drift the switch draws a different-length sword than R does.
##
##   5  THE CARRY IS NEAR-HORIZONTAL AND NOT FLAT, AND POINTS LEFT. §3 allows
##      15-30° and forbids 90°. The direction is authored as a vector and the
##      euler is solved from it, so this checks the solver actually produced the
##      elevation the constant claims rather than trusting `aim_euler`.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_draw_beats.gd

const SENTENCE_LOW := 1.2
const SENTENCE_HIGH := 2.0
const HOLD_LOW := 0.120
const HOLD_HIGH := 0.250
const GLINT_LOW := 0.080
const GLINT_HIGH := 0.160
const TILT_LOW := 15.0
const TILT_HIGH := 30.0

# Both of these are read as TABLES rather than used as types, and neither carries
# a `class_name` — the registry because it is a table (see its own header) and the
# manager because it is a Node. Preloading them here is what lets this probe check
# that the manager's typed-in duration and the move's authored one agree, which is
# the only way that pair can be caught drifting.
const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")
const WeaponManagerScript := preload("res://scripts/combat/weapon_manager.gd")

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	var move := SwordBasic.equip()

	_title("1 · the sentence is the length §3 asks for")
	_ok(move.total_time() >= SENTENCE_LOW and move.total_time() <= SENTENCE_HIGH,
		"total %.3fs is inside §3's %.1f-%.1f s" % [
			move.total_time(), SENTENCE_LOW, SENTENCE_HIGH])
	_ok(move.damage == 0.0, "a draw opens no hitbox (damage %.1f)" % move.damage)

	_title("2 · the pause is a pause")
	var hold := SwordBasic.NE_HOLD_END - SwordBasic.NE_DRAW_PARTIAL
	_ok(hold >= HOLD_LOW and hold <= HOLD_HIGH,
		"the hold is %.0f ms, inside §3's %.0f-%.0f" % [
			hold * 1000.0, HOLD_LOW * 1000.0, HOLD_HIGH * 1000.0])
	var moved := _travel(move, SwordBasic.NE_DRAW_PARTIAL, SwordBasic.NE_HOLD_END)
	_ok(moved < 0.0005,
		"the blade moved %.4f m across the hold (must be ~0 — a hold is not a slow move)" % moved)

	_title("3 · the glint window is a still frame")
	var glint := SwordBasic.NE_GLINT_END - SwordBasic.NE_HOLD_END
	_ok(glint >= GLINT_LOW and glint <= GLINT_HIGH,
		"the glint is %.0f ms, inside §3's %.0f-%.0f" % [
			glint * 1000.0, GLINT_LOW * 1000.0, GLINT_HIGH * 1000.0])
	var glint_moved := _travel(move, SwordBasic.NE_HOLD_END, SwordBasic.NE_GLINT_END)
	_ok(glint_moved < 0.0005,
		"the blade moved %.4f m during the glint (it must be still — the glint runs, the sword does not)" % glint_moved)

	_title("4 · §2 — the saya does not follow the blade out of itself")
	_ok(move.has_saya_beats(), "the draw choreographs the sheath at all")
	var blade_travel := _travel(move, SwordBasic.EQUIP_E0, SwordBasic.NE_DRAW_FULL)
	var mouth_travel := _saya_travel(move, SwordBasic.NE_BRING, SwordBasic.NE_GLINT_END)
	_ok(blade_travel > 0.55,
		"the blade travels %.3f m out of the sheath over the draw" % blade_travel)
	_ok(mouth_travel < 0.0005,
		"the mouth moved %.4f m while the blade travelled %.3f m — the sheath is HELD" % [
			mouth_travel, blade_travel])
	# ...and it does move where §3 says it does, or "held" would just be "ignored".
	var push := _saya_travel(move, SwordBasic.NE_GLINT_END, SwordBasic.NE_DRAW_FULL)
	_ok(push > 0.02,
		"the off hand pushes the saya %.3f m the other way during Beat 4 (§3 asks for it)" % push)

	_title("5 · bow exists only where curvature does")
	_ok(move.beat_bows.size() == move.beat_positions.size() - 1,
		"one bow per segment (%d bows, %d beats)" % [
			move.beat_bows.size(), move.beat_positions.size()])
	var seg_first := move.bow_of(1).length()
	var seg_hold := move.bow_of(2).length()
	var seg_glint := move.bow_of(3).length()
	var seg_rest := move.bow_of(4).length()
	_ok(seg_first > 0.0 and seg_rest > 0.0,
		"the two extraction segments are bowed (%.5f m / %.5f m)" % [seg_first, seg_rest])
	_ok(seg_hold < 1e-6 and seg_glint < 1e-6,
		"the hold and glint segments are straight (%.6f / %.6f) — nothing moves in them" % [
			seg_hold, seg_glint])
	_ok(seg_first < SwordClasses.BORE_SORI,
		"the partial-extraction bow (%.5f) is under the full bore sori (%.5f)" % [
			seg_first, SwordClasses.BORE_SORI])

	_title("6 · the two owners of one duration agree")
	_ok(is_equal_approx(float(WeaponManagerScript.DRAW_SECONDS), move.total_time()),
		"WeaponManager.DRAW_SECONDS %.3f == the sentence %.3f" % [
			float(WeaponManagerScript.DRAW_SECONDS), move.total_time()])
	_ok(is_equal_approx(float(WeaponManagerScript.SHEATHE_SECONDS), move.total_time()),
		"WeaponManager.SHEATHE_SECONDS %.3f == the sentence %.3f" % [
			float(WeaponManagerScript.SHEATHE_SECONDS), move.total_time()])

	_title("7 · the carry is near-horizontal, tilted, and pointing left")
	var carry_basis := Basis.from_euler(SwordBasic.aim_euler(SwordBasic.NE_CARRY_DIR))
	var blade_dir: Vector3 = carry_basis * Vector3.UP
	var tilt := rad_to_deg(asin(clampf(blade_dir.y, -1.0, 1.0)))
	_ok(tilt >= TILT_LOW and tilt <= TILT_HIGH,
		"the carry sits %.1f° above horizontal, inside §3's %.0f-%.0f" % [
			tilt, TILT_LOW, TILT_HIGH])
	_ok(blade_dir.x < -0.5,
		"the blade points left (x %.3f) — the grip is on the right, which is where a draw starts" % blade_dir.x)

	_title("8 · the seating anchor is unchanged")
	# A1's opening and A3's three returns are SEATING events, and they read
	# `SAYA_MOUTH`. A draw that quietly re-anchored the mouth would move three
	# other beats with it.
	var seated: Vector3 = move.beat_positions[0]
	_ok(seated.is_equal_approx(SwordBasic.SAYA_MOUTH),
		"the draw starts at SAYA_MOUTH %s (got %s)" % [SwordBasic.SAYA_MOUTH, seated])

	print("")
	if _fails.is_empty():
		print("PASS: the five-beat draw contract — %d checks" % _checks)
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: %s" % f)
		print("FAIL: %d problem(s) of %d checks" % [_fails.size(), _checks])
		quit(1)


func _title(t: String) -> void:
	print("")
	print("── %s" % t)


func _ok(condition: bool, reason: String) -> void:
	_checks += 1
	print("  %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)


## How far the blade's origin moves between two instants of the sentence.
func _travel(move: SwordMove, from_t: float, to_t: float) -> float:
	var a := _at(move, from_t)
	var b := _at(move, to_t)
	var worst := 0.0
	# Sampled rather than endpoint-to-endpoint: a path that leaves and comes back
	# has the same two endpoints, and this question is about the journey.
	for i in 21:
		var t := lerpf(from_t, to_t, float(i) / 20.0)
		worst = maxf(worst, (_at(move, t) as Vector3).distance_to(a))
	return worst


func _at(move: SwordMove, t: float) -> Vector3:
	return SwordPoseSampler.sample(move, t)["position"]


func _saya_travel(move: SwordMove, from_t: float, to_t: float) -> float:
	var worst := 0.0
	var a: Vector3 = SwordPoseSampler.sample_arrays(move.beat_times, move.saya_positions,
		move.saya_rotations, move.saya_bows, from_t)["position"]
	for i in 21:
		var t := lerpf(from_t, to_t, float(i) / 20.0)
		var shot := SwordPoseSampler.sample_arrays(move.beat_times, move.saya_positions,
			move.saya_rotations, move.saya_bows, t)
		worst = maxf(worst, (shot["position"] as Vector3).distance_to(a))
	return worst
