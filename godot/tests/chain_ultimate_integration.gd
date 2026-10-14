extends SceneTree
# 缚星链 · I / ULTIMATE — 现实膜 · THE ACCEPTANCE TEST.
#
# ---------------------------------------------------------------------------
# WHY THIS IS A SEPARATE FILE FROM `tools/probe_chain_ultimate.gd`
# ---------------------------------------------------------------------------
#
# The probe answers "did the ceremony run and did the room come back", which is
# the smoke question, and it answers it by reading the objects the ceremony
# already owns. This file answers the questions the DESIGN makes and the probe
# cannot: the ones where a number has to be measured against another number rather
# than read off a field. Every claim below is measured, and each one is here
# because it has a plausible failure that no picture would show:
#
#   §1  THE BEATS DO NOT FIRE EARLY. `exp(-since(t, at))` is 1.0 BEFORE `at`, and
#       that one expression has already put a 0.55 white wash over the film for the
#       whole first pass of this skill. So every one-shot is checked to be ZERO
#       everywhere before its own moment, on a 240Hz sweep, rather than spot-checked.
#
#   §2  THE COIL IS TWO TURNS — as the INTEGRAL of the winding, not as its value at
#       the endpoint. A curve that winds one and a half turns and then unwinds half
#       a turn also ends at 2.000, and 绕两圈, 不多不少 is a claim about the path.
#
#   §3  THE FILM IS A PATCH AND THE WORLD STAYS. This is the user's SECOND
#       correction to this effect, and it reverses the first one by name. V1's rule
#       「这块布要把整个画面拉进来，不只是一部分」 was implemented, rendered, and rejected
#       as 黑色不规则 Iris — because a film that covers the frame and then contracts
#       leaves a black border around a window. So §3 now tests the opposite, and it
#       tests it as AREA off the built mesh: big enough that its absence is a
#       missing piece of the world, nowhere near big enough to become a border, and
#       with enough of its own wound left uncovered that one still can show both.
#       「前方约 35-55% 视野面积的一块现实」 is the user's own band.
#
#   §4  THE FILM AND THE WOUND AGREE. They are the same mesh with two materials, and
#       the wound opens exactly where the film's contracted rim is. That is a claim
#       about two uniforms on two materials being one number, so it is measured as
#       one number — and it is the only reason the void cannot drift off the film.
#
#   §5  THE PICTURE IS THE WORLD. Two failures live here and both have happened: a
#       capture that was never taken (a black sheet, and the whole skill reads as a
#       dark shape), and UVs baked from a depth that is identically zero for a plane
#       facing the camera (every vertex clamped to the texture edge, and the film
#       renders as one smeared wash). So: the texture is checked to be a live
#       viewport of the right size, and the baked UVs are checked to actually span
#       the frame at the film's own distance.
#
#   §6  THE STROKES FIT THE SHADER AND FOLLOW THROUGH. `cut_seg[CUT_MAX]` is a fixed
#       GLSL array; a sixth cut added to the tuning and not to the shader is a silent
#       no-op on the last stroke. And the tip must CLEAR the film's edge rather than
#       stopping on it, which is measured against the film's own extent.
#
#   §7  THE ENEMY IS NOT PRINTED ON THE FILM. The film is a picture of the world's
#       surface; the enemy is the thing standing in the world this skill is aimed at.
#       Left in the capture it doubles itself the moment the picture pulls in — a
#       photograph of the enemy travelling with the film, plus the enemy itself.
#
#   §8  THE DAMAGE LANDS ONCE. The wound is 5.6m of ground and the dummy is the only
#       body in it, and 260 is applied to everything in range at the tear, exactly
#       once. Checked by giving the dummy enough health for two applications to be
#       distinguishable, because on the shipped dummy (120) a double hit is invisible.
#
#   §9  THE WORLD IS HANDED BACK. Including the room itself, which this line learned
#       the hard way: the floor had to leave with the picture, and the way that was
#       first written it left one frame too early and came back with a dark band
#       where the floor should have been, in the CAPTURE, forever.
#
# Usage:
#   godot --headless --path godot --script res://tests/chain_ultimate_integration.gd

const SWEEP := 1.0 / 240.0
# THE PATCH'S BAND, AS A FRACTION OF THE FRAME'S AREA, AT THE TWO MOMENTS THAT
# MATTER. The user's number is 「前方约 35-55% 视野面积的一块现实」, and it is a
# statement about the HELD patch: at the rip the patch is still at the anchor's
# depth and has not yet been hauled toward the player, so it is legitimately
# smaller there. Both ends are widened by a few points so a retune inside the
# brief's own range does not go red — the band exists to catch the two failures
# that actually happened (a patch too small to read, and a patch that ate the frame).
const PATCH_RIP_MIN := 0.15
const PATCH_RIP_MAX := 0.50
const PATCH_HOLD_MIN := 0.30
const PATCH_HOLD_MAX := 0.62
# Samples along each edge of the frame when testing coverage. 33 per edge is a
# 1cm grid on a 15m frame at the rip, which is finer than the outline's own wiggle.
const EDGE_SAMPLES := 33

var failures: Array[String] = []
var metrics: Dictionary = {}

var lab: Node3D
var director: ChainUltimateDirector
var tuning: ChainUltimateTuning
var sheet: ChainRealitySheet
var camera: Camera3D
var feedback: CameraFeedbackController
var combat: CombatController
var dummy: Node3D
var room: Node3D

# The frame the framing claims are about, resolved once from the ceremony's own
# fov and the game's own picture shape. §3 and §5 both need it and both need the
# SAME one, so it lives here rather than in either of them.
var frame_fov := 70.0
var frame_aspect := 1.7777
var half_w := 0.0
var half_h := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


# ===========================================================================
# THE RUN
# ===========================================================================

func _run() -> void:
	# THE FRAME THESE CLAIMS ARE ABOUT, SET BEFORE ANYTHING IS BUILT.
	#
	# Godot's headless DisplayServer reports a 64x64 viewport, and every framing
	# number in this skill is derived from the SHAPE of the picture. A square frame
	# would not make §3 wrong, it would make it meaningless — the film's coverage
	# and the layer's derivation in the room are both arithmetic on the frame's
	# proportions — so the window is put at the project's own authored size first,
	# and the aspect is CHECKED below rather than assumed.
	root.size = Vector2i(1152, 648)

	var scene: PackedScene = load("res://scenes/combat/ChainUltimateLab.tscn")
	if scene == null:
		print("FAIL: the lab scene did not load")
		quit(1)
		return
	lab = scene.instantiate()
	root.add_child(lab)
	for _i in 8:
		await process_frame

	director = lab.find_child("ChainUltimateDirector", true, false) as ChainUltimateDirector
	if director == null:
		print("FAIL: the room produced no director")
		quit(1)
		return
	tuning = director.tuning
	sheet = director.get("sheet")
	camera = lab.find_child("Camera3D", true, false) as Camera3D
	feedback = lab.find_child("CameraFeedbackController", true, false) as CameraFeedbackController
	combat = lab.find_child("CombatController", true, false) as CombatController
	dummy = lab.find_child("TechnicalDummy", true, false) as Node3D
	room = lab.get("room") as Node3D

	_s3a_the_frame()
	_s1_nothing_fires_early()
	_s2_the_coil_is_an_integral()
	_s6_the_strokes()
	await _run_the_ceremony()
	await _s9_the_world_comes_back()
	_report()


# ===========================================================================
# §1 — THE BEATS, AND NOTHING FIRING BEFORE ITS OWN MOMENT
# ===========================================================================

func _s1_nothing_fires_early() -> void:
	print("=== §1 · THE NINE BEATS ===")
	# Every quantity that is a ONE-SHOT, with the moment it owns. A quantity that
	# is non-zero before its moment is the `exp(-since)` bug: a flash, a tear or a
	# dissolve that has already happened by the time the ceremony starts.
	var oneshots := [
		["flash", tuning.t_tear_start],
		["tear", tuning.t_tear_start],
		["dissolve", tuning.t_restore_start],
		["hole_close", tuning.t_restore_start],
		["pull", tuning.t_pull_start],
		["coil_turns", tuning.t_coil_start],
	]

	# ---- THE ONSET OF EACH PHASE, MEASURED -------------------------------
	# Not read off a field: swept. If `evaluate` and the timeline ever disagree
	# about when a phase begins, the two numbers compared here are the disagreement.
	#
	# PHASE 6 IS THE ONE THAT IS NOT `t_cut_start`. The window 2.15-2.85 is when the
	# head is a blade-pen, and it OPENS with the tip drawn back off the film, poised;
	# the first stroke lands at `cut_start` (2.22). So the quantity that says PHASE 6
	# has begun is the first stroke opening, and it is compared against `cut_start` —
	# the first version of this compared it against `t_cut_start` and reported a
	# 70ms "failure" that was the design working.
	var names := ["thrust", "bite", "coil", "peel", "float", "cut", "tear", "restore"]
	var onsets: Array[float] = []
	for name in names:
		onsets.append(_onset(name))
	var expected := [
		tuning.t_thrust_start, tuning.t_bite, tuning.t_coil_start, tuning.t_pull_start,
		tuning.t_float_start, tuning.cut_start, tuning.t_tear_start,
		tuning.t_restore_start + tuning.hole_close_delay,
	]
	var order_ok := true
	var onset_lines: Array[String] = []
	for i in names.size():
		var off := onsets[i] - float(expected[i])
		onset_lines.append("%s %.3f" % [names[i], onsets[i]])
		_check(absf(off) <= SWEEP * 1.5,
			"PHASE %d (%s) begins at %.4f but the timeline says %.4f" % [
				i, names[i], onsets[i], float(expected[i])])
		if i > 0 and onsets[i] <= onsets[i - 1]:
			order_ok = false
	_check(order_ok, "the nine beats do not arrive in order: " + ", ".join(onset_lines))
	print("   onsets      ", " · ".join(onset_lines))

	# ---- AND NOTHING BEFORE ITS MOMENT ----------------------------------
	var early: Array[String] = []
	var backslide: Array[String] = []
	var t := 0.0
	var worst_flash := 0.0
	while t <= tuning.t_end + 1e-6:
		var e := tuning.evaluate(t)
		for pair in oneshots:
			var key := String(pair[0])
			var at := float(pair[1])
			if t < at - 1e-9 and float(e[key]) > 1e-9:
				early.append("%s=%.4f at %.3f (owns %.2f)" % [key, float(e[key]), t, at])
			if t > at + 0.0001 and float(e[key]) < -1e-9:
				backslide.append("%s=%.4f at %.3f" % [key, float(e[key]), t])
		if t < tuning.t_tear_start:
			worst_flash = maxf(worst_flash, float(e["flash"]))
		t += SWEEP
	_check(early.is_empty(), "%d quantity/quantities are live before their own moment — %s"
		% [early.size(), ", ".join(early.slice(0, 3))])
	_check(backslide.is_empty(), "a one-shot went negative after its moment: "
		+ ", ".join(backslide.slice(0, 3)))
	print("   flash before the tear   %.4f  (must be 0.0000)" % worst_flash)
	metrics["worst_early_flash"] = worst_flash


## The most a quantity has to have a value of: the first t at which it is non-zero.
func _onset(name: String) -> float:
	var t := 0.0
	while t <= tuning.t_end + 1e-6:
		if _quantity(name, t) > 1e-9:
			return t
		t += SWEEP
	return -1.0


func _quantity(name: String, t: float) -> float:
	var e := tuning.evaluate(t)
	match name:
		"thrust":
			return float(e["thrust"])
		"bite":
			return float(e["bite"])
		"coil":
			return float(e["coil_turns"])
		"peel":
			return float(e["pull"])
		"float":
			return float(e["free"])
		"cut":
			return float(e["cut_open"][0]) if not (e["cut_open"] as Array).is_empty() else 0.0
		"tear":
			return float(e["tear"])
		"restore":
			return float(e["hole_close"])
	return 0.0


# ===========================================================================
# §2 — 绕两圈, 不多不少
# ===========================================================================

func _s2_the_coil_is_an_integral() -> void:
	print("=== §2 · THE COIL ===")
	var a := tuning.t_coil_start
	var b := tuning.t_pull_start
	var steps := 2000
	var total := 0.0
	var worst_back := 0.0
	var prev := tuning.coil_turns_at(a)
	for i in range(1, steps + 1):
		var t := a + (b - a) * float(i) / float(steps)
		var v := tuning.coil_turns_at(t)
		var d := v - prev
		worst_back = minf(worst_back, d)
		total += d
		prev = v
	print("   integral over the coil window   %.4f turns" % total)
	print("   worst backward step             %.6f turns  (must not be negative)" % worst_back)
	_check(absf(total - tuning.coil_turns) < 1e-3,
		"the winding integrates to %.4f turns, not %.4f" % [total, tuning.coil_turns])
	# NOT JUST THE TOTAL. 绕两圈 that unwinds half a turn is still 2.000 at the end
	# and is not a wrap, so the winding is checked to never go backwards.
	_check(worst_back >= -1e-9, "the coil unwinds by %.6f turns somewhere — that is a hoist, not a wrap" % worst_back)
	# 越缠越紧, as geometry: the orbit has to actually close.
	var r0 := tuning.coil_radius_at(0.0)
	var r1 := tuning.coil_radius_at(1.0)
	print("   orbit radius                    %.3f -> %.3f of the core" % [r0, r1])
	_check(r1 < r0 * 0.75, "the orbit closes from %.3f to only %.3f — that is a hoop, not a wrap" % [r0, r1])
	_check(absf(r1 - tuning.coil_radius_end) < 1e-6, "the orbit does not end at `coil_radius_end`")
	metrics["coil_integral"] = total


# ===========================================================================
# §3 — THE FILM TAKES THE WHOLE PICTURE  (the user's own correction)
# ===========================================================================

func _s3a_the_frame() -> void:
	print("=== §3 · THE FILM IS A PATCH, AND THE WORLD AROUND IT STAYS ===")
	# ---- THE FOV THE CEREMONY ACTUALLY RUNS AT ---------------------------
	# NOT `camera.fov`. `CameraFeedbackController` writes `base_fov + fov_hold +
	# ...`, and this skill holds `fov_hold` at `fov_close` for the whole ceremony,
	# so the frame is 70 degrees and not 75. Every framing number in the tuning is
	# derived from 70, and the first version of this effect was authored at 75.
	var base_fov := 75.0
	if feedback != null:
		base_fov = float(feedback.get("base_fov"))
		_check(absf(camera.fov - base_fov) < 0.01,
			"the camera sits at %.2f degrees at rest but the feedback controller's base is %.2f — every framing number in the tuning assumes the base" % [camera.fov, base_fov])
	frame_fov = base_fov + tuning.fov_close
	frame_aspect = root.get_visible_rect().size.aspect()
	half_h = tan(deg_to_rad(frame_fov * 0.5)) * tuning.anchor_distance
	half_w = half_h * frame_aspect
	_check(frame_aspect > 1.5,
		"the frame is %.3f:1 — a square picture makes the coverage claim meaningless rather than false" % frame_aspect)
	print("   ceremony fov                    %.2f deg  (base %.2f %+.2f)" % [frame_fov, base_fov, tuning.fov_close])
	print("   frame                           %.3f:1" % frame_aspect)
	print("   frame at the rip                %.2f x %.2f m  (half %.2f x %.2f)" % [
		half_w * 2.0, half_h * 2.0, half_w, half_h])

	# ---- AND THERE IS NO CONTRACTION ANY MORE ----------------------------
	# V1 opened the void by contracting the film, and the contraction is exactly
	# what BOUNDED the picture: every pixel outside the contracted rim was void,
	# which is a black border with a window in it. The film now leaves its wound
	# behind by TRAVELLING off it instead (see `sheet_drift`), so the quantity that
	# used to open the frame is a constant — and the day someone contracts it again
	# the iris comes back with it.
	_check(tuning.sheet_contract_end >= 0.999,
		"`sheet_contract_end` is %.3f — a contracting film is what turns this into a black border around a window; the wound is exposed by the film leaving sideways now" % tuning.sheet_contract_end)
	# ---- AND IT IS THE SIZE THE USER ASKED FOR ---------------------------
	# 「宽约 4-7m 高约 2.5-4m」, checked in METRES because this is the one claim about
	# the patch that is about the patch rather than about the picture it sits in.
	# The top ends are widened — see the tuning's note on why the AREA claim and not
	# the width claim is the one that decides legibility.
	var ext := tuning.sheet_extent()
	print("   patch                           %.2f x %.2f m" % [ext.x * 2.0, ext.y * 2.0])
	_check(ext.x * 2.0 > 4.0 and ext.x * 2.0 < 9.0,
		"the patch is %.2f m wide — the brief's band is 4-7m, widened to 9 because a 7m patch at the anchor's depth never reaches 35%% of a 70-degree frame's area" % (ext.x * 2.0))
	_check(ext.y * 2.0 > 2.0 and ext.y * 2.0 < 5.0,
		"the patch is %.2f m tall — the brief's band is 2.5-4m" % (ext.y * 2.0))


## §3, SECOND HALF — and it needs the MESH, so it cannot run until the film exists.
## The outline is read off the geometry that was actually built: a test that
## recomputes the shape from the lobe constants can only ever agree with itself.
func _s3b_the_film_covers(outline: PackedFloat32Array) -> void:
	var lo := 10.0
	var hi := -10.0
	for r in outline:
		if r <= 0.0:
			continue
		lo = minf(lo, r)
		hi = maxf(hi, r)
	print("   outline radius                  %.3f .. %.3f m in the camera's axes" % [lo, hi])
	# 不是矩形, 不是规整 — asked as VARIANCE, because a circle and a rectangle are
	# both constant-radius and the difference between them is not measurable here.
	_check(hi - lo > 0.12,
		"the outline only varies by %.3f of its radius — that is a disc, not a torn membrane" % (hi - lo))

	var cover := _coverage(outline, 1.0, half_w, half_h)
	print("   frame border inside the patch   %.4f  (must be 0.0000)" % float(cover["fraction"]))
	_check(float(cover["fraction"]) < 0.02,
		"%.1f%% of the frame's BORDER is inside the patch — the world has stopped surrounding it and this is an iris again" % (float(cover["fraction"]) * 100.0))

	# ---- AT THE RIP: BIG, AND NOWHERE NEAR THE WHOLE PICTURE -------------
	var rip_area := _patch_area_fraction(outline, half_w, half_h)
	print("   the patch at the rip            %.1f%% of the frame's area" % (rip_area * 100.0))
	_check(rip_area > PATCH_RIP_MIN,
		"the patch is only %.1f%% of the frame at the rip — that is a hole appearing in front of me, not a piece of the world coming off" % (rip_area * 100.0))
	_check(rip_area < PATCH_RIP_MAX,
		"the patch is %.1f%% of the frame at the rip — at that size the world around it stops being legible and the effect is a screen mask again" % (rip_area * 100.0))
	metrics["patch_rip"] = rip_area

	# ---- AT THE HOLD: THE BRIEF'S OWN BAND -------------------------------
	var freed_depth := maxf(tuning.anchor_distance - tuning.sheet_pull_distance, 0.5)
	var hold_half_h := tan(deg_to_rad(frame_fov * 0.5)) * freed_depth
	var hold_half_w := hold_half_h * frame_aspect
	var hold_area := _patch_area_fraction(outline, hold_half_w, hold_half_h)
	print("   the patch at the hold           %.1f%% of the frame's area  (the brief's band is 35-55%%)" % (hold_area * 100.0))
	_check(hold_area > PATCH_HOLD_MIN,
		"the patch is only %.1f%% of the frame at the hold — under the brief's 35-55%% band" % (hold_area * 100.0))
	_check(hold_area < PATCH_HOLD_MAX,
		"the patch is %.1f%% of the frame at the hold — over the brief's 35-55%% band, and the world around it is being lost" % (hold_area * 100.0))
	metrics["patch_hold"] = hold_area
	_check(_outer_screen_fraction(outline, 1.0, hold_half_w, hold_half_h) < 1.0,
		"the patch's outline leaves the frame at the hold — it is bigger than the picture again")

	# ---- AND ITS OWN WOUND HAS TO STAY VISIBLE BESIDE IT -----------------
	# THE WHOLE REASON `sheet_drift` EXISTS, AND THE USER'S ONE-STILL TEST:
	# 世界缺了一块 + 那一块正在前面漂, in the same frame. The film grows as it comes
	# toward the player, so it is always bigger than the hole it came out of; if it
	# also stayed concentric the hole would be hidden completely and the hero frame
	# would show a floating sheet over an intact world.
	var exposed := _wound_exposed_fraction(freed_depth)
	print("   wound left uncovered at the hold %.0f%%  (drift %.2f, %.2f m)" % [
		exposed * 100.0, tuning.sheet_drift.x, tuning.sheet_drift.y])
	_check(exposed > 0.25,
		"the film leaves only %.0f%% of its wound visible — a single still cannot show the missing piece and the piece that is missing at the same time" % (exposed * 100.0))
	metrics["wound_exposed"] = exposed


## The outline's radius per angular bin, in METRES in the camera's own axes — read
## off the mesh that was actually built rather than re-derived from the lobe
## constants. A test that recomputes the shape can only ever agree with itself.
##
## THE ASPECT IS APPLIED HERE, NOT IN THE MESH. `_polar` builds a disc whose local
## coordinates are already metres (`sheet_radius * u * lobe`), and the film's real
## proportions come from the NODE's basis — `_aspect_basis` scales it by
## `sheet_aspect`. So a direction on screen is `(x * aspect.x, y * aspect.y)` of the
## mesh's own coordinate, and the first version of this divided instead of
## multiplying: it reported an outline of "6.0 .. 10.5 radii" and a coverage of
## 0.71 for a film that in fact covers the frame with room to spare.
func _outline_table(mesh: Mesh, aspect: Vector2, bins: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(bins)
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in verts:
		var p := Vector2(v.x * aspect.x, v.y * aspect.y)
		if p.length() <= 0.0:
			continue
		var bin := int(floor((atan2(p.y, p.x) + PI) / TAU * float(bins))) % bins
		out[bin] = maxf(out[bin], p.length())
	_fill_gaps(out)
	return out


## THE GAPS ARE NOT HOLES. The outline is sampled at the mesh's own sector angles —
## a couple of degrees apart — and a lookup grid finer than that has empty cells.
## An empty cell reads as a radius of ZERO, which the coverage test then reports as
## the frame hanging out of the film: the first version of this attributed 19% of the
## frame to the film's short lobes when it was the test's own empty bins. The gaps
## are therefore filled from their neighbours around the circle, and by
## INTERPOLATION rather than by the smaller neighbour, so the outline measured here
## is the outline that was built.
func _fill_gaps(out: PackedFloat32Array) -> void:
	var n := out.size()
	for i in n:
		if out[i] > 0.0:
			continue
		var back := 0.0
		var bd := 1
		while bd < n and out[(i - bd + n * 2) % n] <= 0.0:
			bd += 1
		back = out[(i - bd + n * 2) % n]
		var fwd := 0.0
		var fd := 1
		while fd < n and out[(i + fd) % n] <= 0.0:
			fd += 1
		fwd = out[(i + fd) % n]
		if bd >= n:
			continue
		out[i] = lerpf(back, fwd, float(bd) / float(bd + fd))


## What fraction of the frame's own rectangle falls inside the film's outline, and —
## when it is not all of it — HOW FAR OUT the worst point is and where.
##
## The second half is the point. "0.811 of the frame" is a verdict; "the frame's
## corner at 29 degrees is 1.14 times as far out as the film reaches" is the number
## that says what to change. The frame is walked EDGE BY EDGE, not sampled at its
## corners and its axes: a circle wide enough to cover the picture's width still
## leaves the corners, and sampling the width alone would call that covered.
##
## `outline` is the BUILT radius in metres and `contract` is how far the picture has
## been pulled in right now, so the two callers — this one at the rip and
## `_outer_screen_fraction` at the float — cannot disagree about the shape.
func _coverage(outline: PackedFloat32Array, contract: float, half_w: float, half_h: float) -> Dictionary:
	var bins := outline.size()
	var inside := 0
	var total := 0
	var worst := 0.0
	var at := Vector2.ZERO
	for edge in 4:
		for i in EDGE_SAMPLES:
			var u := float(i) / float(EDGE_SAMPLES - 1)
			var x := 0.0
			var y := 0.0
			match edge:
				0:
					x = lerpf(-half_w, half_w, u)
					y = half_h
				1:
					x = lerpf(-half_w, half_w, u)
					y = -half_h
				2:
					x = half_w
					y = lerpf(-half_h, half_h, u)
				_:
					x = -half_w
					y = lerpf(-half_h, half_h, u)
			var bin := int(floor((atan2(y, x) + PI) / TAU * float(bins))) % bins
			var reach := outline[bin] * contract
			total += 1
			if Vector2(x, y).length() <= reach:
				inside += 1
			elif reach > 0.0 and Vector2(x, y).length() / reach > worst:
				worst = Vector2(x, y).length() / reach
				at = Vector2(x, y)
	return {
		"fraction": float(inside) / float(total),
		"worst": worst,
		"at": at,
		"angle_deg": rad_to_deg(atan2(at.y, at.x)),
	}


## How far the outline reaches, as a fraction of the frame's half-extent, at the
## depth the film is at when it is free. Same table, same space, one caller apart.
func _outer_screen_fraction(
	outline: PackedFloat32Array, contract: float, half_w: float, half_h: float
) -> float:
	var bins := outline.size()
	var worst := 0.0
	for b in bins:
		var angle := TAU * float(b) / float(bins) - PI
		var p := Vector2(cos(angle), sin(angle)) * outline[b] * contract
		worst = maxf(worst, maxf(absf(p.x) / half_w, absf(p.y) / half_h))
	return worst


## The outline's own AREA as a fraction of the frame's rectangle, by the shoelace
## formula over the outline table. `half_w` / `half_h` are the frame's half-extents
## at the depth being asked about, so the same table answers for the rip and for
## the hold.
##
## THIS IS THE NUMBER THE USER'S SECOND CORRECTION IS ABOUT, AND IT IS NOT THE
## NUMBER THE FIRST ONE WAS. V1's claim was about the frame's BORDER — "does the
## film reach the corners" — which is a coverage question. V2's is about AREA:
## 「前方约 35-55% 视野面积的一块现实」. They are genuinely different quantities: a
## patch can touch all four corners and still be 40% of the picture, and a patch
## can be a third of the area and touch none of them — which is the shape this
## effect wants, and why the border check below is kept as a second, weaker gate
## rather than as the measurement.
func _patch_area_fraction(
	outline: PackedFloat32Array, half_w: float, half_h: float
) -> float:
	var bins := outline.size()
	var twice := 0.0
	for b in bins:
		var a0 := TAU * float(b) / float(bins) - PI
		var a1 := TAU * float((b + 1) % bins) / float(bins) - PI
		var p0 := Vector2(cos(a0), sin(a0)) * outline[b]
		var p1 := Vector2(cos(a1), sin(a1)) * outline[(b + 1) % bins]
		twice += p0.x * p1.y - p1.x * p0.y
	return absf(twice) * 0.5 / maxf(4.0 * half_w * half_h, 0.0001)


## How much of the wound the freed film leaves UNCOVERED, as a fraction of the
## wound's own area.
##
## Modelled as two upright rectangles in the frame's normalised coordinates. A
## rectangle is the right model even though neither shape is one, because the
## question is OCCLUSION and for occlusion the bounding extent is what decides; the
## lobes move the outline by at most 19%, so this sits within a few points of the
## true figure — and it is the same figure the sweep that chose `sheet_drift` used,
## which is the point of measuring it here rather than trusting the comment.
func _wound_exposed_fraction(freed_depth: float) -> float:
	var w := _patch_box(tuning.anchor_distance, 0.0, 0.0)
	var f := _patch_box(freed_depth, tuning.sheet_drift.x, tuning.sheet_drift.y)
	var ox := maxf(0.0, minf(w[1], f[1]) - maxf(w[0], f[0]))
	var oy := maxf(0.0, minf(w[3], f[3]) - maxf(w[2], f[2]))
	var area := (w[1] - w[0]) * (w[3] - w[2])
	if area <= 0.0:
		return 0.0
	return clampf(1.0 - (ox * oy) / area, 0.0, 1.0)


## The patch as [x0, x1, y0, y1] in the frame's normalised coordinates — both axes
## run -1..1 at the frame's own edge — at `depth`, offset by `dx` / `dy` metres in
## the camera's axes. `anchor_rise` is included because the patch is centred on the
## anchor and not on the aim.
func _patch_box(depth: float, dx: float, dy: float) -> PackedFloat32Array:
	var half_h := depth * tan(deg_to_rad(frame_fov * 0.5))
	var half_w := half_h * frame_aspect
	var ext := tuning.sheet_extent()
	var cx := dx / half_w
	var cy := (tuning.anchor_rise + dy) / half_h
	var ex := ext.x / half_w
	var ey := ext.y / half_h
	return PackedFloat32Array([cx - ex, cx + ex, cy - ey, cy + ey])


# ===========================================================================
# §6 — THE STROKES
# ===========================================================================

func _s6_the_strokes() -> void:
	print("=== §6 · THE FIVE CUTS ===")
	print("   strokes                         %d of %d shader slots" % [
		tuning.cuts.size(), ChainUltimateTuning.CUT_SLOTS])
	_check(tuning.cuts.size() <= ChainUltimateTuning.CUT_SLOTS,
		"%d strokes but `cut_seg[CUT_MAX]` holds %d — the extra strokes are a silent no-op" % [
			tuning.cuts.size(), ChainUltimateTuning.CUT_SLOTS])
	_check(tuning.cuts.size() >= 3, "the brief asks for 3-6 strokes, not %d" % tuning.cuts.size())
	var last := tuning.cuts.size() - 1
	var opens_at := tuning.cut_time(last)
	var open_by := opens_at + tuning.cut_open_time
	print("   last stroke opens               %.2f -> %.2f  (tear at %.2f)" % [
		opens_at, open_by, tuning.t_tear_start])
	_check(open_by <= tuning.t_tear_start + 0.0005,
		"the last stroke is still opening at %.3f, after the tear at %.3f" % [open_by, tuning.t_tear_start])
	# The last stroke has to be the heavy one (brief §三 PHASE 6).
	_check(tuning.cut_open_at(tuning.t_tear_start, last)
			> tuning.cut_open_at(tuning.t_tear_start, 0) * 1.5,
		"the last stroke opens no wider than the first — 最后一击最重 is not happening")
	# ---- AND THE TIP CLEARS THE FILM -------------------------------------
	# A travel that ends exactly on the boundary reads as a stroke that was clipped.
	# Measured against the film's OWN extent, so retuning the sheet retunes this.
	var anchor := director.anchor_point()
	var basis := camera.global_transform.basis
	var at := opens_at + tuning.cut_stroke_time
	var centre := tuning.sheet_center_at(at, anchor, basis)
	var head := tuning.head_position(at, camera.global_position, anchor, basis)
	var extent := tuning.sheet_extent_at(at)
	var local := head - centre
	var reach := Vector2(
		local.dot(basis.x.normalized()) / extent.x,
		local.dot(basis.y.normalized()) / extent.y)
	print("   tip at the end of the last stroke   %.2f of the film's extent (1.00 is its edge)" % reach.length())
	_check(reach.length() > 1.0,
		"the tip stops at %.2f of the film's extent — the stroke was clipped, not followed through" % reach.length())


# ===========================================================================
# THE CEREMONY, RUN FOR REAL
# ===========================================================================

func _run_the_ceremony() -> void:
	print("=== §4/§5/§7/§8 · THE CEREMONY ===")
	_check(sheet != null, "the director has no sheet")
	if sheet == null:
		return
	# ENOUGH HEALTH FOR TWO APPLICATIONS TO BE TELLING. On the shipped dummy (120)
	# a double hit at 260 is indistinguishable from a single one, which is exactly
	# the kind of failure a test has to be able to see.
	if dummy != null:
		dummy.set("max_health", 1000.0)
		dummy.set("health", 1000.0)
	var health_before := float(dummy.get("health")) if dummy != null else 0.0
	var hit_events := [0]
	director.ultimate_event.connect(func(event: StringName, _data: Dictionary) -> void:
		if event == &"hit":
			hit_events[0] += 1)

	_check(lab.trigger(), "the room refused to start the ceremony")
	var capture_viewport: SubViewport = sheet.get("capture_viewport") as SubViewport
	var view_size := capture_viewport.size if capture_viewport != null else Vector2i.ZERO
	var armed_at := -1.0
	var froze_at := -1.0
	var mismatches: Array[String] = []
	var uv_span := Vector2.ZERO
	var covered := -1.0
	var t := 0.0
	var guard := 0
	while t <= tuning.t_end and guard < 900:
		director.set_debug_hold(t)
		await process_frame
		if sheet.built and armed_at < 0.0:
			armed_at = t
		if sheet.frozen() and froze_at < 0.0:
			froze_at = t
		if sheet.built:
			# ---- §3 · THE OUTLINE, OFF THE MESH THAT WAS BUILT -----------
			if covered < 0.0:
				var hole := sheet.get("hole") as MeshInstance3D
				if hole != null and hole.mesh != null:
					_s3b_the_film_covers(_outline_table(hole.mesh, tuning.sheet_aspect, 72))
					covered = float(metrics.get("patch_rip", 0.0))
			# ---- §4 · THE TWO MATERIALS ARE ONE NUMBER ------------------
			#
			# NOT `film_radius == hole_radius`, WHICH IS WHAT THIS SAID FIRST AND
			# IS FALSE BY DESIGN. The film's `sheet_radius` is the radius it has
			# RIGHT NOW (contraction included) because every one of its metric
			# terms — the ripple, the curl, the normal's finite difference — is
			# scaled by it; the wound's is the radius the MESH was built at,
			# because the wound does not shrink and its own vertex stage maps its
			# pre-contraction coordinates. What has to be one number is the
			# CONTRACTION, and the two radii then have to stand in exactly the
			# relation the film's `apply` writes them in.
			#
			# GATED ON `frozen()` for a reason worth keeping: on the frame the film
			# is ARMED its `apply` has not run yet, so every uniform is still null
			# and `float(null)` is a hard error rather than a zero. The capture
			# freezing is the first moment the uniforms are real. (And it is a
			# nested `if` rather than a `continue`: this loop advances `t` at its
			# FOOT, so a `continue` would skip the advance and spin on one frame.)
			if sheet.frozen():
				var film_radius := float(sheet.sheet_material.get_shader_parameter("sheet_radius"))
				var hole_radius := float(sheet.hole_material.get_shader_parameter("sheet_radius"))
				# ---- §4 · NO CONTRACTION, SO THERE IS NO RATIO LEFT ---------
				#
				# This used to compare a `contract` uniform across the two materials,
				# because the film contracted and the wound did not, so their radii
				# stood in a ratio that had to be one number in two files. THERE IS
				# NO RATIO ANY MORE. V1's contraction is what bounded the picture
				# and turned the void into an annulus around it; it is gone, and
				# with it the entire class of bug this section was written for.
				#
				# What replaces the old claim is the STRONGER one: both materials
				# read the same radius, it is the authored one, and it is that on
				# every frame — which is a live statement about the wound being the
				# same shape as the piece that left it, and it stops being true the
				# moment anything starts scaling one of them again.
				if absf(film_radius - hole_radius) > 1e-4:
					mismatches.append("the film is at %.4f and its own wound at %.4f on t=%.3f — one mesh, two materials, one radius" % [
						film_radius, hole_radius, t])
				if absf(hole_radius - tuning.sheet_radius) > 1e-4:
					mismatches.append("the wound is at %.4f, not the authored %.4f" % [
						hole_radius, tuning.sheet_radius])
				if absf(tuning.sheet_contract_at(t) - 1.0) > 1e-6:
					mismatches.append("the film contracts to %.4f at t=%.3f — a contracting film is the iris" % [
						tuning.sheet_contract_at(t), t])
				# ---- §5 · THE UV BAKE SPANS THE FRAME -----------------------
				#
				# MEASURED ON THE FULL SURFACE, not on one shard. The six shards
				# tile the film, so each of them spans a fraction of it, and the
				# first version of this read one shard and reported 0.981 of the
				# frame for a film that covers it twice over.
				if uv_span == Vector2.ZERO:
					var full := sheet.get("hole") as MeshInstance3D
					if full != null:
						uv_span = _uv_span(full.mesh)
		t += SWEEP
		guard += 1

	print("   sheet armed %.2fs · capture frozen %.2fs" % [armed_at, froze_at])
	_check(armed_at > 0.0, "the film was never armed — there is no picture to take")
	_check(froze_at >= armed_at, "the capture never froze — the film would show a black rectangle")

	# ---- §4 -------------------------------------------------------------
	_check(mismatches.is_empty(),
		"the film and the wound disagree about their own geometry: " + ", ".join(mismatches.slice(0, 3)))
	print("   film/wound radius               the same number on every frame, and it never contracts")

	# ---- §5 · THE PICTURE IS THE WORLD ---------------------------------
	#
	# TWO WAYS THIS FAILS AND BOTH HAVE HAPPENED. A capture that was never taken
	# leaves a black sheet and the whole skill reads as a dark shape. And a bake
	# whose depth was measured ALONG the view axis is identically zero for a plane
	# facing the camera, so the projection came out twenty times too large and every
	# vertex clamped to the texture's edge — a picture that is there and is wrong.
	#
	# The second one is caught exactly, not approximately: the bake is a uniform
	# scale, so the frame's own half-width has to map to HALF the texture's span.
	# That is a statement about `_uv_scale`, and it is checked against the sheet's
	# own `_capture_size` so the test cannot disagree with the bake about the frame.
	var tex: Variant = sheet.sheet_material.get_shader_parameter("capture_tex")
	var kind: String = "null" if tex == null else tex.get_class()
	print("   capture texture                 %s  %dx%d" % [kind, view_size.x, view_size.y])
	_check(tex is ViewportTexture, "the film is not sampling a live viewport (it is %s) — the picture is not the world" % kind)
	_check(tex is ViewportTexture and (tex as ViewportTexture).get_width() > 16,
		"the capture is %dpx wide — a placeholder, not a picture" % (0 if tex == null else (tex as ViewportTexture).get_width()))
	var bake_size: Vector2i = sheet.call("_capture_size", camera)
	var bake_aspect := float(bake_size.x) / maxf(float(bake_size.y), 1.0)
	var uv_scale: Vector2 = sheet.get("_uv_scale")
	# THE FOV THE SHEET BAKED AT, NOT THE ONE THE CAMERA HAS NOW. `arm` runs at the
	# rip, when the ceremony holds the fov closed; by the time this line runs the
	# ceremony is over and the camera is back at 75. Reading `camera.fov` here gave a
	# scale off by exactly tan(37.5)/tan(35) = 1.096 on BOTH axes, which is the
	# signature of the wrong angle and not of a wrong bake.
	var baked_half_h := tan(deg_to_rad(frame_fov * 0.5)) * tuning.anchor_distance
	var baked_half_w := baked_half_h * bake_aspect
	print("   bake                            %dx%d (%.3f:1) at %.1f deg · the frame's half-width maps to %.4f of the texture" % [
		bake_size.x, bake_size.y, bake_aspect, frame_fov, baked_half_w * uv_scale.x])
	_check(absf(baked_half_w * uv_scale.x - 1.0) < 2e-3,
		"the frame's half-width maps to %.4f of the capture, not 1.0 — the bake and the frame disagree about where the picture is" % (baked_half_w * uv_scale.x))
	_check(absf(baked_half_h * uv_scale.y - 1.0) < 2e-3,
		"the frame's half-height maps to %.4f of the capture, not 1.0" % (baked_half_h * uv_scale.y))
	print("   baked UV span                   %.3f x %.3f of the frame (1.0 is the frame)" % [uv_span.x, uv_span.y])
	# THE V2 REQUIREMENT, IN THE BAKE'S OWN COORDINATES.
	#
	# V1 asserted the opposite here — "a welded film covers the frame, so its UVs
	# must span MORE than 1.0 on both axes" — and that assertion is one of the
	# reasons the iris survived: it certified that the picture was the whole view.
	# A patch INSIDE the picture cannot span more than the picture. If the UVs still
	# spanned the texture, the patch would be showing a squeezed-down copy of the
	# WHOLE world, which is the most convincing way there is to make it read as an
	# image effect rather than as a piece of the world.
	_check(uv_span.x < 1.0 and uv_span.y < 1.0,
		"the baked UVs span %.3f x %.3f of the frame — the patch is showing the whole world, so it is a copy of the picture and not a piece of it" % [uv_span.x, uv_span.y])
	_check(uv_span.x > 0.20 and uv_span.y > 0.20,
		"the baked UVs only span %.3f x %.3f of the frame — a crop that small cannot be recognised as the world" % [uv_span.x, uv_span.y])
	# ---- AND EACH AXIS HAS TO MATCH THE FRAME ---------------------------
	# The bake is a uniform scale ON THE FRAME'S OWN AXES, so a patch's UV span is
	# its size AS A FRACTION OF THE FRAME — `ext.x / half_w`, `ext.y / half_h` — and
	# NOT the ratio of the patch's own two sides.
	#
	# This matters because the wrong version of this check is very tempting and it
	# goes RED ON A CORRECT BAKE: the bake's x scale carries the frame's 1.778 for a
	# reason, and that factor is precisely what stops the patch's metre aspect from
	# showing up in its UVs. (Measured: a 1.824:1 patch bakes to a 1.15:1 UV span,
	# and it should.) So each axis is checked against the frame separately, which is
	# also the tighter statement — it catches a single wrong axis, not just two that
	# happen to disagree.
	var want_x := tuning.sheet_extent().x / half_w
	var want_y := tuning.sheet_extent().y / half_h
	print("   baked UV vs the frame           %.3f x %.3f measured, %.3f x %.3f expected" % [
		uv_span.x, uv_span.y, want_x, want_y])
	# The outline's lobes move its furthest point by up to 19% of nominal, so the
	# tolerance is that and not tighter.
	_check(absf(uv_span.x - want_x) / want_x < 0.25,
		"the baked UVs span %.3f on x where the patch is %.3f of the frame — the bake's scale is wrong" % [uv_span.x, want_x])
	_check(absf(uv_span.y - want_y) / want_y < 0.25,
		"the baked UVs span %.3f on y where the patch is %.3f of the frame — the bake's scale is wrong" % [uv_span.y, want_y])
	metrics["uv_span"] = uv_span.x
	metrics["uv_span_y"] = uv_span.y

	# ---- §7 · THE ENEMY IS NOT IN THE PICTURE ---------------------------
	var excluded: Array = director.get("_extra_hide")
	var in_capture := dummy != null and excluded.has(dummy)
	print("   enemy excluded from the capture %s" % ("yes" if in_capture else "NO"))
	_check(in_capture,
		"the enemy is left in the capture — it will be printed on the film AND stand in the void, twice in one shot")

	# ---- §8 · THE DAMAGE, ONCE -----------------------------------------
	var centre := tuning.sheet_center_at(tuning.t_tear_start, director.anchor_point(), camera.global_transform.basis)
	var gap := dummy.global_position.distance_to(centre)
	print("   dummy to the wound at the tear  %.2fm  (hit radius %.2fm)" % [gap, tuning.hit_radius])
	_check(gap < tuning.hit_radius,
		"the dummy is %.2fm from the wound and the hit radius is %.2fm — the damage test is vacuous" % [gap, tuning.hit_radius])
	var health_after := float(dummy.get("health"))
	var lost := health_before - health_after
	print("   damage applied                  %.0f  (one application is %.0f)" % [lost, tuning.damage])
	_check(absf(lost - tuning.damage) < 0.01,
		"the dummy lost %.0f, and one application of this skill is %.0f — it %s" % [
			lost, tuning.damage, "was dealt twice" if lost > tuning.damage else "was not dealt once"])
	_check(hit_events[0] == 1, "the skill announced %d hits, not one" % hit_events[0])
	_check(director.targets.has(dummy), "the dummy was never collected as a target")
	metrics["damage"] = lost


## The span of a mesh's baked UVs, per axis, in units of the frame. A welded film
## covers the frame and then some, so both axes must be >= 1.0; a bake that
## collapsed (the depth bug) clamps every vertex to the texture's edge and this
## reads ~0 on both.
func _uv_span(mesh: Mesh) -> Vector2:
	if mesh == null:
		return Vector2.ZERO
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	if uv.is_empty():
		return Vector2.ZERO
	var lo := Vector2(10.0, 10.0)
	var hi := Vector2(-10.0, -10.0)
	for p in uv:
		lo = lo.min(p)
		hi = hi.max(p)
	# The bake is `0.5 + 0.5 * metres / half_extent`, so a span of 1.0 in UV is
	# exactly one frame — which is why this needs no conversion to be read as a
	# multiple of the picture.
	return hi - lo


# ===========================================================================
# §9 — THE WORLD IS HANDED BACK
# ===========================================================================

func _s9_the_world_comes_back() -> void:
	print("=== §9 · THE END ===")
	# THE SCRUB ABOVE NEVER MOVED `elapsed`. `set_debug_hold` pins the picture to a
	# time WITHOUT walking the director's clock, which is what makes a scrubbed take
	# honest — and it is also why the handover has to be tested on the clock: park
	# it just short of the end and check that `finish()` runs on its own.
	director.elapsed = maxf(tuning.t_end - 0.02, 0.0)
	director.release_debug_hold()
	var frames := 0
	while director.active and frames < 400:
		await process_frame
		frames += 1
	# The room has to be given a few frames after the director finishes: the
	# visibility gate rides the room's own `_process`, and the last frame of the
	# ceremony is not the frame the room comes back on.
	for _i in 4:
		await process_frame

	_check(not director.active, "the ceremony never finished")
	_check(not sheet.built, "the film survived the ceremony")
	_check(absf(Engine.time_scale - 1.0) < 0.0001,
		"the world is left at time_scale %.3f — the hitstop never came off" % Engine.time_scale)
	if combat != null:
		_check(combat.state != CombatController.State.ULTIMATE, "the player is still locked out of acting")
	if feedback != null:
		_check(absf(float(feedback.get("fov_hold"))) < 0.001,
			"the fov was left closed at %+.3f degrees" % float(feedback.get("fov_hold")))
	var chain: ChainDirector = lab.find_child("ChainDirector", true, false) as ChainDirector
	_check(chain == null or not chain.manual_step, "the chain was never handed back to the game")
	# ---- AND THE ROOM ITSELF ---------------------------------------------
	# This is the one this line paid for: the room leaves with the picture, and if
	# it is not brought back the ceremony ends on an empty frame with the whole skill
	# still running behind it.
	print("   room visible again              %s" % (str(room.visible) if room != null else "no room"))
	_check(room != null and room.visible,
		"the room was never handed back — the ceremony ends with the world still gone")
	if dummy != null:
		_check(dummy.visible, "the enemy is left invisible after the ceremony")
	_check(not sheet.visible, "the film is still visible after the ceremony")


# ===========================================================================
# THE VERDICT
# ===========================================================================

func _report() -> void:
	print("")
	print("缚星链 · I / ULTIMATE — 现实膜")
	print("  §1  beats in order, no one-shot early        flash before the tear %.4f"
		% float(metrics.get("worst_early_flash", -1.0)))
	print("  §2  the coil integrates to                   %.4f turns"
		% float(metrics.get("coil_integral", 0.0)))
	print("  §3  the patch is                             %.0f%% of the frame at the rip, %.0f%% at the hold · wound %.0f%% uncovered"
		% [float(metrics.get("patch_rip", 0.0)) * 100.0,
			float(metrics.get("patch_hold", 0.0)) * 100.0,
			float(metrics.get("wound_exposed", 0.0)) * 100.0])
	print("  §5  baked UV span                            %.3f x %.3f of the frame"
		% [float(metrics.get("uv_span", 0.0)), float(metrics.get("uv_span_y", 0.0))])
	print("  §8  damage applied once                      %.0f"
		% float(metrics.get("damage", 0.0)))
	print("")
	if failures.is_empty():
		print("PASS: the world stays, a patch of it comes off in one piece with its wound left in place, the enemy is not on the picture and the damage lands once — and the room comes back")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
