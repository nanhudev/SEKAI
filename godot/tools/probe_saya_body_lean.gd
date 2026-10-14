extends SceneTree
## PROBE · §30, ASKED OF THE BODY ITSELF
##
## ===========================================================================
## WHY THIS EXISTS
## ===========================================================================
## §30 asks for three things about the LEFT ARM, and gives the reason they matter:
##
##   "Saya 向 下 Tuck：左肘 要 变化"
##   "Saya 向 前 Present：左肩 要 有 一点 Protraction"
##   "Saya Counter Pull：左肘 自然 后 走"
##   "否则：Saya：即使：轨迹：正确，仍：像：漂浮。"
##
## and §39 asks a reviewer to decide, from the picture, whether the saya "looks
## like it is being held by the left hand". Both are properties of the BODY, and
## the body was the one thing in this line with no instrument at all:
## `probe_saya_per_move.gd` measures the scabbard, and the review body had only
## ever been looked at, in a clip.
##
## So this drives the body directly -- no scene, no weapon, no movie -- by handing
## `SayaReviewBody` a series of left-hand points and reading back what the body did
## about them.
##
## WHAT IT CAN AND CANNOT SETTLE
##   CAN   that the shoulder is no longer a constant; that it moves both ways; that
##         it is EXACTLY zero at rest, so idle and draw carry none of this; and
##         that the arm root and the torso top cannot disagree about the lean.
##   CANNOT settle whether the result looks like a person. That is the clip.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_saya_body_lean.gd

const ReviewBody := preload("res://tools/saya_review_body.gd")

## The hand's forward offsets from the shoulder plane, in metres: a counter-pull
## (behind it), rest (on it), and two presentations.
const OFFSETS := [-0.090, -0.050, 0.0, 0.050, 0.120, 0.220]
## The hand's height and side, held fixed so the only variable is `z`. A probe
## that moves the hand in two axes cannot say which one the lean answered.
const HAND_Y := -0.360
const HAND_X := -0.190
## Two points derived from ONE angle must agree this closely. Not zero, because
## they are floats compared at millimetre scale.
const AGREE_TOL := 0.0005

var _fails: Array[String] = []
var _body: Node3D
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_body = ReviewBody.new()
	root.add_child(_body)
	await process_frame
	await process_frame

	var rest_fwd := float(_body.call("shoulder_rest_fwd"))
	print("")
	print("── §30 · the body, asked directly")
	print("   shoulder plane at z = %+.3f m (body space; +Z is forward)" % rest_fwd)
	print("   the lean's own ceiling is %.1f°" % float(_body.call("protract_lean_max_deg")))
	print("")
	print("   %9s %9s %11s %10s %13s %10s" % [
		"hand fwd", "lean", "shoulder", "sh->hand", "torso top", "shortfall"])

	for off in OFFSETS:
		_body.set("left_target", Vector3(HAND_X, HAND_Y, rest_fwd + off))
		await process_frame
		await process_frame
		var reach: Dictionary = _body.call("reach")
		var torso_top: Vector3 = _body.call("torso_top_world")
		var row := {
			"off": off,
			"lean": float(reach.get("lean_deg", 0.0)),
			"shoulder_fwd": float(reach.get("shoulder_fwd", 0.0)),
			"span": float(reach.get("left_span", 0.0)),
			"torso_top_fwd": torso_top.z - rest_fwd,
			"shortfall": float(reach.get("left_shortfall", 0.0)),
		}
		_rows.append(row)
		print("   %8.0fmm %8.2f° %9.1fmm %9.3fm %11.1fmm %9.1fmm" % [
			off * 1000.0, row["lean"], row["shoulder_fwd"] * 1000.0,
			row["span"], row["torso_top_fwd"] * 1000.0, row["shortfall"] * 1000.0])

	_verdict()
	_release()
	quit(1 if not _fails.is_empty() else 0)


func _verdict() -> void:
	print("")
	var rest_row := {}
	for r in _rows:
		if absf(float(r["off"])) < 0.0001:
			rest_row = r

	# 1 · THE ZERO CASE. This is what keeps §30 out of every frame that is not a
	#     presentation: idle, the draw, the sheathe and the iaido ceremony all hand
	#     the body a hand point at the shoulder plane.
	_judge(not rest_row.is_empty() and absf(float(rest_row["lean"])) < 0.0001,
		"a hand at the shoulder plane produces EXACTLY zero lean (got %.4f°)"
			% float(rest_row.get("lean", -1.0)))

	# 2 · it moves, monotonically, and BOTH WAYS. A shoulder that only protracts is
	#     the original fault written the other way round -- §30 asks for the tuck
	#     and the counter-pull as well as the presentation.
	var prev := -INF
	var monotone := true
	var lo := 0.0
	var hi := 0.0
	for r in _rows:
		var lean := float(r["lean"])
		if lean < prev - 0.0001:
			monotone = false
		prev = lean
		lo = minf(lo, lean)
		hi = maxf(hi, lean)
	_judge(monotone, "the lean rises monotonically as the hand presents")
	_judge(lo < -0.01 and hi > 0.01,
		"and it works BOTH ways: behind the shoulder it retracts (%.2f°), in front it "
			% lo + "protracts (%.2f°)" % hi)
	_judge(hi <= float(_body.call("protract_lean_max_deg")) + 0.001,
		"and it stays inside its own %.1f° ceiling (peak %.2f°)"
			% [float(_body.call("protract_lean_max_deg")), hi])

	# 3 · THE DERIVATION. The shoulder's forward shift and the torso top's are the
	#     same angle at two lever arms, and at this body's proportions those two
	#     lever arms are the SAME length -- both points sit at shoulder height. So
	#     the two numbers have to agree, and this is the check that catches the one
	#     failure this design can have: computing the shift twice, differently.
	var worst := 0.0
	for r in _rows:
		worst = maxf(worst,
			absf(float(r["shoulder_fwd"]) - float(r["torso_top_fwd"])))
	_judge(worst <= AGREE_TOL,
		"the shoulder's shift and the torso's top agree to %.1f mm (limit %.1f): they "
			% [worst * 1000.0, AGREE_TOL * 1000.0] + "are one angle, not two offsets")

	# 4 · the solve still reaches. A lean that pulled the shoulder away from the hand
	#     would be a body leaning out of what it is holding.
	var worst_short := 0.0
	for r in _rows:
		worst_short = maxf(worst_short, float(r["shortfall"]))
	_judge(worst_short <= 0.001,
		"leaning costs no reach: worst shortfall %.1f mm, and a lean only means "
			% (worst_short * 1000.0) + "anything if the arm still gets there")

	print("")
	print("P_SAYA_BODY_LEAN DONE")


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)


func _release() -> void:
	if _body != null and is_instance_valid(_body):
		root.remove_child(_body)
		_body.free()
	_body = null
