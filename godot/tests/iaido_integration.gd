extends SceneTree

# Iaido / 聚合斩 signature skill integration check.
#
# Verifies the V7 ceremony: the world actually stops (three dead windows now),
# the silences are long enough to be silences, CUT FIRST / FRACTURE SECOND /
# COLLAPSE LAST holds in the timeline, the opening stays derived from the
# displacement instead of growing into a beam, the panes stay attached until the
# final click, the delayed hit lands, the debug scrub can jump to any stage, and
# every global (FOV, time scale, tree pause, screen grade, void, glass, HUD) is
# restored afterwards.


var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var iaido: IaidoDirector
var failures: Array[String] = []

# Every shader this ceremony draws with. They are checked for GDScript syntax
# before anything else runs — see `_verify_shaders_are_glsl()`.
const SHADER_SOURCES := [
	"res://vfx/iaido_cleave.gdshader",
	"res://vfx/iaido_world_split.gdshader",
	"res://vfx/iaido_glass_shard.gdshader",
	"res://vfx/iaido_fracture_field.gdshaderinc",
]
# Tokens that are legal GDScript and illegal GLSL. Kept to the unambiguous ones:
# GDScript's `and` / `or` / `not` are left out on purpose, because a shader may
# legitimately contain the word "not" inside an identifier.
const GDSCRIPT_ONLY := [":=", "@export", "@onready", "class_name ", "func ", "extends ", "match ", "elif ", "var ", "await "]


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


# A tuning value by name, read through the LIVE resource so what the assertions
# see is the schedule that will actually run rather than a number typed twice.
func _t(key: String) -> float:
	return float(iaido.tuning.get(key))


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	dummy = world.get_node("TechnicalDummy")
	combat = player.get_node("CombatController")
	iaido = world.get_node("IaidoDirector")
	player.global_position = Vector3(0, 1.15, 0.0)
	await physics_frame
	await physics_frame

	_verify_shaders_are_glsl()
	_verify_tuning_is_not_stale()
	_verify_timeline()
	_verify_the_sheathe_is_one_linear_motion()
	_verify_glass_carries_the_split()
	_verify_the_glass_grows_out_of_the_wound()
	_verify_no_second_sword_in_the_glass()
	_verify_shared_fracture_field()
	await _verify_full_run()
	await _verify_camera_is_dead_in_stops()
	await _verify_scrub()
	await _verify_failsafe()

	if failures.is_empty():
		print("PASS: Iaido ceremony · 3 dead windows, cut → split → hero hold → fracture → collapse, opening stays derived, panes hold until the click")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


# ---------------------------------------------------------------------------
# A SHADER IS NOT GDScript, AND NOTHING WAS CHECKING.
#
# `--check-only` parses GDScript and never opens a `.gdshader`. So a stray `:=`
# in one compiles clean, loads without complaint, and fails only when the
# material is first used — at which point the engine prints SHADER ERROR to the
# log, hands back a null shader, and everything that material was supposed to
# draw silently does nothing at all. That is exactly what shipped: an execution
# cross-section material containing `float w := max(band, 0.0005);`, which took
# out the cut surface, the interior and the entire fall, and was found only by a
# probe written to answer an unrelated question about player death.
#
# The failure mode is nasty precisely because it is quiet: the code is valid
# GDScript, so nothing in the toolchain objects, and the visible symptom is an
# effect that never appears rather than an error anyone can read. So the
# boundary gets asserted here. Comments are stripped first, because this
# repository discusses GDScript inside shader comments on purpose.
# ---------------------------------------------------------------------------
func _verify_shaders_are_glsl() -> void:
	for path in SHADER_SOURCES:
		_check(FileAccess.file_exists(path), "Shader %s is missing" % path)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			_check(false, "%s could not be read" % path)
			continue
		var line_number := 0
		for raw in text.split("\n"):
			line_number += 1
			var line: String = raw
			var comment := line.find("//")
			if comment >= 0:
				line = line.substr(0, comment)
			line = line.strip_edges()
			if line.is_empty():
				continue
			for token in GDSCRIPT_ONLY:
				if line.contains(token):
					_check(
						false,
						"%s:%d is GDScript, not GLSL (found `%s`): %s"
							% [path, line_number, token, line]
					)


# ---------------------------------------------------------------------------
# THE SHEATHE IS ONE LINEAR MOTION AND IT COVERS THE CHARGE.
#
# 不要单独出现收刀了，蓄力过程中慢慢收刀，蓄力完成之后就收完全，线性.
#
# Three separate claims, and they used to all be false at once: the blade got a
# beat of its own in front of the charge, it parked with the last 5cm proud of
# the mouth while the whole charge happened around a sword that was visibly not
# in its scabbard, and a second, eased seat closed the gap much later. So each
# claim is asserted on its own, because each is a different way for the note to
# come back.
# ---------------------------------------------------------------------------
func _verify_the_sheathe_is_one_linear_motion() -> void:
	var tuning: IaidoTuning = iaido.tuning
	var a := _t("sheath_start")
	var b := _t("sheath_end")
	# 1 · IT IS THE CHARGE. The walk home ends where the world stops, so there is
	# no instant at which the sword has finished moving but the charge has not.
	_check(
		absf(b - _t("time_stop_start")) < 0.001,
		"the sheathe ends at %.2fs but the charge runs to %.2fs — the two are supposed to be one motion"
			% [b, _t("time_stop_start")]
	)
	_check(
		b - a >= 2.0,
		"the blade is walked home in %.2fs, which is not 'during the charge' (%.2fs)" % [b - a, _t("wave_end") - _t("wave_start")]
	)
	# 2 · IT ARRIVES. Fully home, with no second act left to close a gap.
	_check(
		absf(float(tuning.get("sheath_depth")) - 1.0) < 0.0001,
		"the blade stops at %.2f of the bore when the charge ends — 蓄力完成之后就收完全"
			% float(tuning.get("sheath_depth"))
	)
	# 3 · IT IS LINEAR. Sampled WITHIN each leg of the path, never across the
	# mouth: a straight line between two poses that straddle the mouth is shorter
	# than the distance the tip actually walked between them, so comparing the
	# two halves of the walk directly reports a correct constant speed as an ease
	# — and did, 1.202m against 0.793m, for two halves that are equal by
	# construction. The legs are measured separately and each quarter of each leg
	# has to cover the same distance.
	var split := float(iaido.call("sheath_leg_split"))
	_check(
		split > 0.05 and split < 0.95,
		"the sheathe path has no real alignment leg (split %.3f) — the blade is not travelling to the mouth first" % split
	)
	var whole := 0.0
	for leg in [[0.0, split], [split, 1.0]]:
		var lo := float(leg[0])
		var hi := float(leg[1])
		var width := hi - lo
		var q0: Vector3 = iaido.call("_sheath_at", lo)["position"]
		var q1: Vector3 = iaido.call("_sheath_at", lo + width * 0.25)["position"]
		var q2: Vector3 = iaido.call("_sheath_at", lo + width * 0.50)["position"]
		var q3: Vector3 = iaido.call("_sheath_at", lo + width * 0.75)["position"]
		var q4: Vector3 = iaido.call("_sheath_at", hi)["position"]
		var leg_total := (
			q0.distance_to(q1) + q1.distance_to(q2)
			+ q2.distance_to(q3) + q3.distance_to(q4))
		whole += leg_total
		_check(leg_total > 0.05, "a leg of the walk home travels %.3fm — the blade is not going anywhere" % leg_total)
		var quarter := leg_total * 0.25
		for pair in [[q0, q1], [q1, q2], [q2, q3], [q3, q4]]:
			var here: float = (pair[0] as Vector3).distance_to(pair[1] as Vector3)
			_check(
				absf(here - quarter) / maxf(leg_total, 0.0001) < 0.02,
				"the sheathe is eased, not linear: a quarter of one leg covers %.3fm of that leg's %.3fm"
					% [here, leg_total]
			)
	_check(whole > 0.20, "the sheathe travels only %.3fm — the blade cannot be going home" % whole)
	# 4 · AND IT IS STILL MOVING WHILE THE CHARGE IS. The failure this catches is
	# a blade that reached its resting pose early and then stood still for two
	# seconds, which is what the old park did.
	var during_early: Vector3 = iaido.call(
		"_sheath_at", IaidoTuning.span(_t("wave_start") + 0.30, a, b))["position"]
	var during_late: Vector3 = iaido.call(
		"_sheath_at", IaidoTuning.span(_t("wave_end"), a, b))["position"]
	_check(
		during_early.distance_to(during_late) > 0.08,
		"the blade moves %.3fm between %.2fs and %.2fs — most of the charge happens around a sword that has already stopped"
			% [during_early.distance_to(during_late), _t("wave_start") + 0.30, _t("wave_end")]
	)
	# 5 · AND IT IS HOME BEFORE THE DRAW. The last thing the sheathe may not do
	# is still be running when the blade is supposed to come back out.
	_check(
		iaido.call("_sheath_at", 1.0)["position"].distance_to(
			iaido.call("_bore_pose", 1.0)["position"]) < 0.0005,
		"the end of the sheathe is not the fully seated pose"
	)


# The tuning resource is the runtime authority, and it is a plain .tres that a
# running Godot editor will happily re-save from its own stale in-memory copy.
# That silently reverted a whole pass once, so it is checked before anything
# else: every number below is asserted against the script's own defaults.
func _verify_tuning_is_not_stale() -> void:
	var tuning: IaidoTuning = iaido.tuning
	var fresh := IaidoTuning.new()
	var pairs := [
		["restore_end", tuning.restore_end, fresh.restore_end],
		["hold_end - hold_start", tuning.hold_end - tuning.hold_start, fresh.hold_end - fresh.hold_start],
		["draw_start", tuning.draw_start, fresh.draw_start],
		["cut_start", tuning.cut_start, fresh.cut_start],
		["hero_hold_end", tuning.hero_hold_end, fresh.hero_hold_end],
		["gap_ratio", tuning.gap_ratio, fresh.gap_ratio],
		["separation_px", tuning.separation_px, fresh.separation_px],
		["edge_refract_px", tuning.edge_refract_px, fresh.edge_refract_px],
		["collapse_start", tuning.collapse_start, fresh.collapse_start],
		["shard_loose_count", float(tuning.shard_loose_count), float(fresh.shard_loose_count)],
		["glass_stream_end", tuning.glass_stream_end, fresh.glass_stream_end],
		["capture_time", tuning.capture_time, fresh.capture_time],
		["devour_start", tuning.devour_start, fresh.devour_start],
		["wait_end", tuning.wait_end, fresh.wait_end],
		["damage_time", tuning.damage_time, fresh.damage_time],
	]
	for pair in pairs:
		_check(
			absf(float(pair[1]) - float(pair[2])) < 0.001,
			"IaidoTuning.tres is stale: %s is %s but the script default is %s (a running editor probably re-saved the resource)" % [pair[0], pair[1], pair[2]]
		)


func _verify_timeline() -> void:
	var tuning := iaido.tuning
	# The signature skill must not be quietly compressed back into a flourish.
	_check(tuning.restore_end >= 9.0, "Iaido total runtime collapsed below 9s (%.2f)" % tuning.restore_end)
	_check(tuning.restore_end <= 10.6, "Iaido total runtime exceeds 10.6s (%.2f)" % tuning.restore_end)
	# The two silences are the design: a shaft of nothing while the world is grey
	# and the blade goes home, and a full second with the blade already home.
	_check(tuning.hold_end - tuning.hold_start >= 0.45, "Grey-to-stop window shorter than 0.45s")
	_check(tuning.wait_end - tuning.first_click >= 0.90, "The second after the sheath click is shorter than 0.9s")
	# The draw has to stay violent against two seconds of charging plus a second
	# of standing still.
	_check(tuning.draw_end - tuning.draw_start <= 0.13, "Instant draw is not instant (%.3fs)" % (tuning.draw_end - tuning.draw_start))
	_check(tuning.draw_start >= 3.0, "The draw arrives after only %.2fs of anticipation" % tuning.draw_start)
	_check(tuning.sheath_end - tuning.sheath_start >= 0.7, "Return to sheath rushed (<0.7s)")
	_check(tuning.slow_sheathe_end - tuning.slow_sheathe_start >= 0.9, "The final return is rushed (<0.9s)")

	# ---- THE OPENING IS DERIVED, NOT AUTHORED -----------------------------
	#
	# V1 shipped a 50px opening against a small displacement and the user read it
	# as a blue beam. `gap_px` is the TOTAL opening while `separation_px` is how
	# far EACH half slid, so the world misregisters by 2 x separation across the
	# wound.
	#
	# 切开世界的裂缝可以大一点 authorised the crack to grow, so a fixed pixel
	# budget is the wrong guard — it would fail a correct change and pass a beam.
	# What separates a wound from a beam is the RATIO, and in V7 there is only
	# one number to get wrong instead of two tracks kept in step by hand.
	_check(
		tuning.gap_ratio > 0.0 and tuning.gap_ratio <= 0.75,
		"The opening is %.0f%% of the displacement that reveals it — at three quarters or past it this is the V1 beam"
			% [tuning.gap_ratio * 100.0]
	)
	# 26 per half after 裂缝大一点 (it was 20). The ceiling is not a budget — it
	# exists because past it the two halves stop reading as two pieces of a world
	# and start reading as a slide transition. 26 gives a 52px step at 1080p,
	# 4.8% of the frame height: a bigger break, and nowhere near a wipe.
	_check(tuning.separation_px <= 28.0, "World separation is a UI transition again (%.1fpx)" % tuning.separation_px)
	# ...and the two halves must not be a mirror. A break that moves both sides by
	# exactly the same amount along exactly the same axis is a slide transition,
	# and the bias is the only thing standing between those two reads.
	_check(
		tuning.split_bias > 0.40 and tuning.split_bias < 0.60,
		"split_bias %.2f is too close to 0.5 — the two halves move as mirror images"
			% tuning.split_bias
	)
	_check(
		absf(tuning.split_rotation_a_deg - tuning.split_rotation_b_deg) > 0.02,
		"The two halves do not rotate relative to each other at all"
	)

	# ---- V7 ORDER OF THE STORY BEATS --------------------------------------
	#
	# The charge pays off as GREY then STOP, and only then does the blade go
	# home. The colour has to have finished leaving before the clock is allowed
	# to stop, or the grey reads as a render hitch rather than as a consequence.
	_check(tuning.grey_end <= tuning.time_stop_start, "The grey must land before the stop begins")
	_check(tuning.time_stop_end <= tuning.seat_start, "The seat must follow the stop, not overlap it")
	_check(tuning.first_click >= tuning.seat_start, "The sheath click precedes the seat")

	# CUT FIRST. FRACTURE SECOND. COLLAPSE LAST.
	#
	# Every assertion below is one of those three words, and V6 broke all three
	# at once: the fracture stream started on the same frame as the cut, so the
	# world was being eaten while it was still trying to separate, and at no
	# instant in the whole ceremony was there a world that was visibly in two
	# pieces. That is precisely 完整画面 + 一条裂纹贴图.
	#
	# 1 · THE CONSEQUENCE DELAY.
	#
	# The blade is out and the world has not reacted yet. Without it the draw and
	# its consequence are the same frame, and the draw stops reading as fast
	# because nothing is late.
	_check(
		tuning.cut_start - tuning.draw_end >= 0.15,
		"The world reacts after only %.0fms — the consequence delay is supposed to be 150-300ms"
			% [(tuning.cut_start - tuning.draw_end) * 1000.0]
	)
	_check(
		tuning.cut_start - tuning.draw_end <= 0.32,
		"The consequence delay is %.0fms, long enough to read as a dropped input"
			% [(tuning.cut_start - tuning.draw_end) * 1000.0]
	)
	_check(tuning.cut_start >= tuning.draw_end, "World cut must not start before the draw finishes")
	_check(tuning.cut_end > tuning.cut_start, "The split has no duration")
	# 2 · THE HERO HOLD. The world is in two pieces and nothing else has happened.
	_check(
		tuning.hero_hold_end - tuning.cut_end >= 0.25,
		"The world is visibly broken for only %.0fms — the design asks for at least 250ms"
			% [(tuning.hero_hold_end - tuning.cut_end) * 1000.0]
	)
	_check(
		tuning.hero_hold_end - tuning.cut_end <= 0.50,
		"The hero hold outstays its welcome (%.0fms)" % [(tuning.hero_hold_end - tuning.cut_end) * 1000.0]
	)
	# 3 · FRACTURE SECOND. The stream happens to a surface that can no longer hold
	#     its shape. It is not what breaks it, and if it runs during the split it
	#     is the thing that stops the split being seen at all.
	_check(
		tuning.glass_start >= tuning.hero_hold_end - 0.001,
		"The fracture stream starts before the split has been seen — the world is eaten while it is still trying to separate"
	)
	_check(tuning.glass_stream_end > tuning.glass_start, "The fracture stream has no duration")
	# 4 · THE CAPTURE IS TAKEN ON A BROKEN WORLD.
	#
	# Inside the hold — after the halves have moved, before anything starts
	# eating — so the panes carry the split, the hole and the edge band rather
	# than a picture of a surface that has not been cut yet.
	_check(tuning.capture_time >= tuning.cut_end - 0.001, "The capture is taken before the world has split")
	_check(
		tuning.capture_time <= tuning.hero_hold_end + 0.001,
		"The capture is taken at or after the end of the hero hold, by which point the stream is running"
	)
	# 5 · THE PIECES DO NOT MOVE UNTIL THE FINAL CLICK.
	_check(
		tuning.loosen_start >= tuning.glass_stream_end - 0.001,
		"Panes come loose before the surface has finished vitrifying"
	)
	_check(tuning.loosen_start >= tuning.spin_start, "Panes come loose before the blade has been brought under control")
	_check(tuning.loosen_start <= tuning.collapse_start, "The loose panes come free after the collapse has already begun")
	_check(tuning.spin_end <= tuning.slow_sheathe_start, "The float phase must finish before the blade goes home")
	_check(tuning.slow_sheathe_start >= tuning.glass_stream_end, "The blade goes home before the surface has finished vitrifying")
	# 6 · COLLAPSE LAST.
	_check(tuning.devour_start >= tuning.final_click, "The devour starts before the blade is home")
	_check(tuning.devour_end >= tuning.devour_start + 0.30, "The devour is too short to read (%.2fs)" % (tuning.devour_end - tuning.devour_start))
	_check(tuning.collapse_start >= tuning.devour_start, "The collapse precedes the devour")
	_check(tuning.collapse_end <= tuning.restore_start + 0.001, "The collapse must finish before reality is restored")
	_check(tuning.glass_stream_end < tuning.collapse_start, "The surface must not fail before the blade is home")
	_check(tuning.devour_start >= tuning.slow_sheathe_end, "The devour starts before the blade has finished going home")
	# The hit lands with the split, not with the draw.
	_check(
		tuning.damage_time >= tuning.cut_start - 0.001,
		"The hit lands at %.2fs, inside the consequence delay it is supposed to pay off" % tuning.damage_time
	)
	# A dead window with nothing in it is not a stop; every window has to have a
	# length that reads as deliberate.
	for window in tuning.time_stops():
		var span: float = float(window[1]) - float(window[0])
		_check(span >= 0.12, "A dead window is too short to register (%.2fs)" % span)
	# NOTHING MAY BE MID-RAMP ACROSS A DEAD WINDOW. This is checked directly
	# rather than trusted, because the last three passes each declared a stop and
	# then left three curves interpolating straight through it.
	for window in tuning.time_stops():
		var w0: float = float(window[0])
		var w1: float = float(window[1])
		var middle := (w0 + w1) * 0.5
		_check(
			absf(tuning.stopped_clock(w0) - tuning.stopped_clock(middle)) < 0.000001,
			"The void clock keeps running inside the window at %.2fs" % w0
		)
		_check(
			absf(tuning.stream_at(w0) - tuning.stream_at(middle)) < 0.000001,
			"The glassification front keeps moving inside the window at %.2fs" % w0
		)

	# ---- THE WARP MUST NOT BREAK ------------------------------------------
	#
	# 蓄力的扭曲空间不要断了 / 收刀前没有扭曲.
	#
	# Both reports are the same fault seen twice: a shell's ring only MOVES while
	# its progress sits strictly between 0 and 1, so windows laid end to end
	# leave instants where every shell and the vacuum are parked at the sheath
	# mouth and nothing is travelling. The user saw one such lull in the middle
	# of the charge, and saw no warp at all before the blade went home.
	#
	# Checked STRUCTURALLY against the real windows, not by sampling the curve:
	# if the union of the windows leaves no hole, no instant can be dead at any
	# resolution or frame rate, and the assertion cannot drift out of step with
	# the arithmetic it is describing.
	var spans := [
		[
			"charge",
			tuning.compression_windows(tuning.wave_start, 1.0),
			tuning.wave_start,
			tuning.time_stop_start,
		],
		[
			"return",
			tuning.compression_windows(tuning.return_wave_start, tuning.return_wave_scale),
			tuning.return_wave_start,
			tuning.final_insert_start,
		],
	]
	for entry in spans:
		var label: String = String(entry[0])
		var windows: Array = entry[1]
		var lowest: float = float(entry[2])
		var highest: float = float(entry[3])
		var covered: float = float(windows[0][0])
		var worst: float = 0.0
		for window in windows:
			worst = maxf(worst, float(window[0]) - covered)
			covered = maxf(covered, float(window[1]))
		_check(worst <= 0.0005, "The %s compression goes dead for %.0fms between shells" % [label, worst * 1000.0])
		_check(
			covered >= highest - 0.0005,
			"The %s compression has already stopped by %.2fs, %.2fs before it should" % [label, covered, highest - covered]
		)
		_check(
			absf(float(windows[0][0]) - lowest) < 0.0005,
			"The %s compression does not start on %.2fs" % [label, lowest]
		)
	# And the return's envelope has to still be pulling while the blade is being
	# walked home — that is what 收刀前没有扭曲 means — and to be spent by the
	# click, because the next beat is the devour and the two must not overlap.
	for moment in [
		["the blade starts going home", tuning.slow_sheathe_start, true],
		["the last centimetres begin", tuning.final_insert_start, true],
		["the click", tuning.final_click, false],
	]:
		var strength := float(tuning.compression_at(
			float(moment[1]),
			tuning.return_wave_start,
			tuning.return_wave_scale,
			1.0)["strength"])
		if bool(moment[2]):
			_check(
				strength > 0.5,
				"The return compression is already spent at %s (strength %.2f)" % [moment[0], strength]
			)
		else:
			_check(
				strength < 0.02,
				"The return compression is still running at %s (strength %.2f)" % [moment[0], strength]
			)

	var stages := [
		tuning.silence_end - tuning.silence_start,
		tuning.sheath_end - tuning.sheath_start,
		tuning.wave_end - tuning.wave_start,
		tuning.hold_end - tuning.hold_start,
		tuning.wait_end - tuning.first_click,
		tuning.cut_end - tuning.cut_start,
		tuning.hero_hold_end - tuning.cut_end,
		tuning.glass_stream_end - tuning.glass_start,
		tuning.spin_end - tuning.spin_start,
		tuning.devour_end - tuning.devour_start,
		tuning.slow_sheathe_end - tuning.slow_sheathe_start,
	]
	for i in stages.size():
		_check(stages[i] >= 0.25, "Stage %d is too short to read (%.2fs)" % [i, stages[i]])
	# HUD has to actually get out of the way.
	_check(tuning.hud_presence <= 0.30, "HUD is not faded during the ceremony (%.2f)" % tuning.hud_presence)


# ---------------------------------------------------------------------------
# THE FRACTURE FIELD IS ONE DEFINITION, AND THIS PROVES IT STILL IS.
#
# `iaido_world_split.gdshader` and `iaido_glass_shard.gdshader` both draw the
# crack network over the same picture, and where a pane is still lying over live
# world the two have to land on the same pixel. The numbers live in
# `iaido_fracture_field.gdshaderinc`, which the panes' own layer also mirrors in
# GDScript (`IaidoTuning.stream_arrived`).
#
# A cross-language equality cannot be asserted by re-implementing the other side
# — that only proves the test agrees with itself, which is the failure mode this
# project has already paid for twice (a hand-copied `.tres` timeline and a
# hand-copied audio cue table). So the numbers are READ OUT OF THE SHADER SOURCE
# and compared against the constants the engine actually runs on.
# ---------------------------------------------------------------------------
const FRACTURE_FIELD := "res://vfx/iaido_fracture_field.gdshaderinc"
const WORLD_SHADER := "res://vfx/iaido_world_split.gdshader"
const PANE_SHADER := "res://vfx/iaido_glass_shard.gdshader"
const GLASS_SCRIPT := "res://scripts/combat/iaido_glass_layer.gd"
const DIRECTOR_SCRIPT := "res://scripts/combat/iaido_director.gd"


# Reads a `const float NAME = <literal>;` out of the shader source. Returns -1.0
# when the constant is missing, so a caller can never read absence as zero and
# pass a "must be small" rule by accident.
func _const_value(source: String, name: String) -> float:
	var at := source.find("const float %s = " % name)
	if at < 0:
		return -1.0
	var line := source.substr(at, 80)
	var literal := line.split("=")[1].strip_edges().split(";")[0].strip_edges()
	return literal.to_float()


# 玻璃必须继续分离.
#
# The bug that shipped: the panes reassembled one continuous frozen picture, so
# the moment the glass took over the frame the wound healed — the read went back
# to "a complete picture with a line drawn on it". Three things carry the cut
# now, and each is checked where it lives:
#
#   1. the director hands the panes the SAME separation it pushes at the world
#      pass (one authority, not a recomputed track);
#   2. the glass layer moves each pane by its side's displacement, with a
#      side sign in the SHADER's frame, plus an ablation switch so the claim
#      can be tested by subtraction;
#   3. the world is not allowed to stop existing under a pane that is still
#      translucent — the eat wedge lags the pane's opacity, or every pixel the
#      front crosses blinks dark before the glass arrives ("the world appears
#      twice").
func _verify_glass_carries_the_split() -> void:
	var tuning: IaidoTuning = iaido.tuning
	var director_source := FileAccess.get_file_as_string("res://scripts/combat/iaido_director.gd")
	var glass_source := FileAccess.get_file_as_string("res://scripts/combat/iaido_glass_layer.gd")
	_check(
		director_source.contains("glass_layer.stage(elapsed, tuning, last_separation_px"),
		"The director does not hand the panes the world's separation — the glass would heal the wound"
	)
	_check(
		glass_source.contains("SEKAI_NO_PANE_SPLIT"),
		"The pane-split ablation is gone; TEST 'no pane split' can no longer be run"
	)
	# 玻璃要按照切口裂开，而不是随便裂开.
	#
	# The side sign used to be recomputed in `stage()` from the pane's centroid
	# and a hard-coded normal constant. Both of those are gone, and the claim
	# that has to survive is stronger than "the sign is taken somewhere": the
	# cut comes off the tuning, the panes are CUT IN TWO by it, and a piece's
	# side is stamped by the clip that produced it rather than guessed again
	# later. Three separate lines, because each of them is a different way for
	# the glass to end up breaking along something that is not the wound.
	_check(
		glass_source.contains("plane_cut_normal = across"),
		"The pane's cut normal no longer comes from the tuning — a remembered angle splits the glass along the MIRROR of the wound"
	)
	_check(
		glass_source.contains("_clip_half_plane(cell, Vector2.ZERO, -cut_normal_plane)"),
		"The glass is not split BY the cut; panes straddling the wound are pushed across it and cover it up"
	)
	_check(
		glass_source.contains('"side": side,'),
		"A pane's side is guessed after the fact instead of stamped by the clip that made it"
	)
	_check(
		glass_source.contains("tuning.split_bias if side_s >= 0.0"),
		"The pane offset no longer carries the 45/55 bias; the two glass halves would misregister symmetrically again"
	)
	_check(
		glass_source.contains('set_shader_parameter("split_sample", move_uv)'),
		"The pane's capture sample is not compensated by its own displacement (+delta); either the mosaic slides whole or the content snaps a full separation at the handover"
	)
	# The world may stop existing only where the pane is already fully opaque:
	# the eat boundary (lead + EAT_BEGIN) must equal the pane's opaque boundary
	# (lead − ARRIVED_BACK), and the eat ramp must be no wider than the pane's
	# own, or a dark band sweeps the frame ahead of the glass ("the world
	# appears twice" — measured as a 155 → 117 luma dip).
	var field := FileAccess.get_file_as_string(FRACTURE_FIELD)
	var arrived_back := _const_value(field, "IAIDO_ARRIVED_BACK")
	var eat_begin := _const_value(field, "IAIDO_EAT_BEGIN")
	var eat_tail := _const_value(field, "IAIDO_EAT_TAIL")
	_check(
		absf(eat_begin + arrived_back) < 0.001,
		"The world's eaten boundary (%.2f) is not the pane's opaque boundary (−%.2f); the front will blink dark before the glass covers it" % [eat_begin, arrived_back]
	)
	_check(
		eat_tail <= arrived_back,
		"The eat ramp (tail %.2f) is wider than the pane's own arrival ramp (%.2f); a dark band leads the glass down the slash" % [eat_tail, arrived_back]
	)
	var world_source := FileAccess.get_file_as_string(WORLD_SHADER)
	_check(
		world_source.contains("lead + IAIDO_EAT_BEGIN"),
		"The world's stream wedge no longer rides the pane's opaque boundary; the dark blink is back"
	)
	# ...AND IT HAS TO STOP WHERE THE GLASS STOPS. The stream wedge runs on
	# `travel`, which every point on the frame satisfies eventually; the panes no
	# longer do. If the eat is left ungated the frame is consumed corner to
	# corner while the glass only covers a band of it, and the glass phase is
	# spent looking through a hole at nothing.
	# THE GATE IS THE COLLAR, NOT THE STRESS REACH — and that distinction is
	# the whole of FINAL LOCK PART A/B. `grown_reach` spreads as far as the
	# crack NETWORK does (thin seams, secondary detail, nothing removed);
	# `claim` is how much of the surface the panes have TAKEN OVER, and it is
	# what the world may be deleted for. The eat was driven off `grown_reach`
	# until this pass, which put a ±45-authored-px near-black band along the
	# cut — the reviewer's 世界裂口像 Overlay, arrived at through the EAT.
	_check(
		world_source.contains("eaten = max(eaten, wedge * claim);"),
		"The world's stream eat is not gated by the glass collar, so it removes world the panes do not claim and the wound reads as a drawn dark band"
	)
	_check(
		world_source.contains("float grown_reach = iaido_grown(front, ad);"),
		"The world pass no longer reads the stress reach at all; the fracture network has nothing to be drawn from"
	)
	_check(
		world_source.contains("float claim = max(iaido_claimed(front, ad), iaido_unleashed(shatter));"),
		"The world pass does not open the collar at the collapse, so the shatter leaves four intact corners in the frame"
	)
	# THE COLLAR HAS TO BE INSIDE THE NETWORK. If the glass claims further than
	# the stress has reached, the picture is eaten where nothing is even broken
	# yet, and the wound is a hole cut ahead of its own cause.
	_check(
		IaidoTuning.CLAIM_TAIL < IaidoTuning.FRONT_CORE,
		"CLAIM_TAIL (%s) is not inside FRONT_CORE (%s): the glass reaches past the fracture network, so the frame is eaten where nothing has broken"
			% [IaidoTuning.CLAIM_TAIL, IaidoTuning.FRONT_CORE]
	)
	_check(
		IaidoTuning.CLAIM_CORE < IaidoTuning.CLAIM_TAIL,
		"CLAIM_CORE (%s) is not below CLAIM_TAIL (%s), so the collar has no falloff and is a hard-edged slot"
			% [IaidoTuning.CLAIM_CORE, IaidoTuning.CLAIM_TAIL]
	)
	# AND IT HAS TO BE SMALL. The number that matters is the collar's real width
	# at 720p, in the window where it is widest — fracture has reached 1, so the
	# front IS `FRONT_PER_FRACTURE` and the collar is `front * CLAIM_TAIL`
	# authored px either side of the cut. Both sides of this are constants, so
	# the assertion cannot drift with the timeline.
	var collar_px := (
		IaidoTuning.FRONT_PER_FRACTURE * IaidoTuning.CLAIM_TAIL * 720.0 / 1080.0)
	_check(
		collar_px < 26.0,
		"The glass collar is %.1f real px either side of the cut at 720p — a band, not a slot" % collar_px
	)

	# AND IT HAS TO BE SIZED AGAINST THE SLIT, NOT AGAINST THE FRONT.
	#
	# This is the relationship the whole of PART A/B lives in, and it is the one
	# that was wrong for a round: the collar was ±148 authored px around a
	# 17.7 authored px hole, which is a BAND AROUND A SLIT. The band is what the
	# eye reads, and the eye then reports 世界裂口像 Overlay — correctly, because
	# it is one, and it arrived through the EAT rather than through the slot.
	#
	# Both ends matter. The collar may not be SMALLER than the slit, because the
	# panes are what replaces the world that was eaten and a hole wider than the
	# panes leaves a strip of live world showing inside the wound. And it may
	# not be much LARGER, because everything past the slit plus PART D's broken
	# edge band is a band. Asserted in authored px so it is resolution free.
	var collar_half: float = IaidoTuning.FRONT_PER_FRACTURE * IaidoTuning.CLAIM_TAIL
	var slit_half: float = tuning.separation_px * tuning.gap_ratio * 0.5
	_check(
		collar_half >= slit_half,
		"The collar (%.1f authored px) is narrower than the slit it has to cover (%.1f): live world shows through inside the wound"
			% [collar_half, slit_half]
	)
	_check(
		collar_half <= slit_half + 14.0,
		"The collar (%.1f authored px) is more than a 14px band around a %.1f px slit — the band is what the eye will read"
			% [collar_half, slit_half]
	)

	# ---- and the PANE is gated by the same collar ----------------------------
	#
	# THE OTHER HALF OF THE BAND, AND THE ONE THAT WOULD SURVIVE EVERY FIX
	# ABOVE. The pane's alpha was `body_alpha * opacity`, where `opacity` comes
	# from `cover_at()` on the pane's CENTRE — a single scalar for a whole piece
	# of surface — while the world's eat is per PIXEL. Whatever the collar is
	# tuned to, a per-pane opacity can only ever approximate it, and the mismatch
	# is a strip of eaten world showing through between the hole and the glass
	# that is meant to be filling it. Reading the collar in the pane's own
	# fragment makes the pane and the hole ONE SHAPE by construction.
	var pane_source := FileAccess.get_file_as_string(PANE_SHADER)
	_check(
		pane_source.contains("float claim = max(iaido_claimed(front, ad), iaido_unleashed(shatter));"),
		"The pane pass never reads the glass collar; its opacity is decided by its centre where the world's eat is decided per pixel, and the difference is a band"
	)
	_check(
		pane_source.contains("0.0, 1.0) * opacity * claim;"),
		"The pane's alpha is not multiplied by the collar, so a pane is opaque over world that was never taken and the mosaic reads as cards laid on the picture"
	)


# THE GLASS IS A BAND OUT OF THE WOUND, NOT A SHEET OVER THE FRAME.
#
# 玻璃从裂痕蔓延. Two independent things have to be true for that, and they fail
# silently in opposite directions:
#
#   spatial   a pane may only exist where the fracture front has GROWN TO. Gating
#             it on `stream_arrived` alone tiles the whole picture, because every
#             point on the frame satisfies that eventually — which is what put a
#             full-screen mosaic of pastel cards over the arena.
#   agreement the reach the layer tests a pane against has to be the reach the
#             world pass eats on, or the two fronts drift and the ceremony shows
#             either live world under a pane or a hole under live world.
func _verify_the_glass_grows_out_of_the_wound() -> void:
	var tuning: IaidoTuning = iaido.tuning
	var glass_source := FileAccess.get_file_as_string(GLASS_SCRIPT)
	var field := FileAccess.get_file_as_string(FRACTURE_FIELD)
	var world_source := FileAccess.get_file_as_string(WORLD_SHADER)

	# ---- the layer reads the radial front, not just the along-slash sweep ----
	_check(
		glass_source.contains("var arrived := tuning.cover_at(time, float(data[\"travel\"]), ad)"),
		"The pane's existence is still decided by the along-slash sweep alone; the glass tiles the whole frame"
	)
	_check(
		glass_source.contains("tuning.cover_at("),
		"The glass layer does not ask the tuning how far out of the wound the front has grown"
	)
	# `ad` has to be the radius FROM THE CUT, in the shard shader's own frame.
	# The plane is y-up and `rel` is y-down, so the y of the normal flips — the
	# same conversion the clip does, and getting it wrong measures the distance
	# from the MIRROR of the wound.
	_check(
		glass_source.contains("Vector2(centre.x, -centre.y).dot(plane_cut_normal)"),
		"The pane's distance from the cut is not measured in the shader's own frame; the band would grow out of the mirror of the wound"
	)
	_check(
		glass_source.contains("/ maxf(two_h, 0.0001) * AUTHORED_PX"),
		"The pane's distance from the cut is not converted to authored pixels, so it is compared against a front measured in them"
	)

	# ---- and the two sides must be reading the SAME front -------------------
	var pairs := [
		["IAIDO_FRONT_PER_FRACTURE", IaidoTuning.FRONT_PER_FRACTURE],
		["IAIDO_FRONT_PER_SHATTER", IaidoTuning.FRONT_PER_SHATTER],
		["IAIDO_FRONT_CORE", IaidoTuning.FRONT_CORE],
		["IAIDO_FRONT_TAIL", IaidoTuning.FRONT_TAIL],
		["IAIDO_CLAIM_CORE", IaidoTuning.CLAIM_CORE],
		["IAIDO_CLAIM_TAIL", IaidoTuning.CLAIM_TAIL],
	]
	for pair in pairs:
		var declared := _const_value(field, String(pair[0]))
		_check(
			absf(declared - float(pair[1])) < 0.0001,
			"%s is %s in the shared field and %s in IaidoTuning — the glass and the world are growing on different fronts"
				% [pair[0], declared, pair[1]]
		)

	# ---- and the band really is a band ---------------------------------------

	# One authored pixel from the wound is glass the instant the front exists;
	# the far corner of a 16:9 frame is NEVER glass, at full fracture OR at full
	# shatter. If either inverts, the glass is a sheet again and 蔓延 is a word
	# in a comment. `glass_start` is 0.001 px wide by construction, so the wound
	# is the only thing inside it — that is what "starts at the crack" means.
	var corner_px := (absf(cos(deg_to_rad(_t("cut_angle_degrees")))) * 1.7777 * 0.5
		+ absf(sin(deg_to_rad(_t("cut_angle_degrees")))) * 0.5) * 1080.0
	_check(
		tuning.grown_at(_t("glass_stream_end"), 0.0) > 0.99,
		"At the end of the stream the glass has not even reached the wound itself"
	)
	_check(
		tuning.grown_at(_t("glass_start"), 200.0) < 0.001,
		"The glass is already %s px wide at glass_start — it does not start at the wound"
			% tuning.front_at(_t("glass_start"))
	)
	for probe in [_t("slow_sheathe_start"), _t("collapse_start")]:
		_check(
			tuning.grown_at(probe, corner_px) < 0.001,
			"The frame's far corner (%.0f px from the cut) is inside the glass front at t=%.2f — the glass is a sheet over the frame again, not a band out of the wound" % [corner_px, probe]
		)

	# Monotonic outward, and never backwards. A front that recedes would put the
	# world back on top of panes that have already been claimed by it.
	var previous := -1.0
	for step in 24:
		var t := lerpf(_t("glass_start"), _t("glass_stream_end"), float(step) / 23.0)
		var reach := tuning.front_at(t)
		_check(
			reach >= previous - 0.0001,
			"The glass front recedes at t=%.2f (%.1f px after %.1f px)" % [t, reach, previous]
		)
		previous = reach
	_check(
		tuning.front_at(_t("glass_start")) < 4.0,
		"The front is already %.1f px wide at glass_start — the glass does not start at the wound" % tuning.front_at(_t("glass_start"))
	)

	# The world pass has to be eating on the term the panes are gated by, not on
	# the raw wedge.
	_check(
		not world_source.contains("eaten = max(eaten, wedge);"),
		"The world is back to eating on the ungated wedge"
	)
	var pane_source := FileAccess.get_file_as_string(PANE_SHADER)
	_check(
		pane_source.contains("iaido_grown(front, ad) * arrived * ready"),
		"The pane shader's internal network no longer grows out of the wound, so a pane lit by the layer would still be a blank card"
	)


func _verify_no_second_sword_in_the_glass() -> void:
	# 两层刀. The panes carry a picture of the world, and that picture used to be
	# taken from the ROOT viewport — the finished composite, which includes
	# `ForegroundWeaponLayer` on canvas layer 8. Welding the player's own sword
	# into the glass put a second, complete sword in the frame at the pose the
	# blade held at `capture_time`, and it stayed there for the rest of the
	# ceremony, because the panes do.
	#
	# Three separate ways back into that bug, three assertions.
	var glass_source := FileAccess.get_file_as_string(GLASS_SCRIPT)
	var director_source := FileAccess.get_file_as_string(DIRECTOR_SCRIPT)
	_check(
		not director_source.contains("capture_world(get_viewport())"),
		"The glass capture is back on the root viewport; the foreground weapon layer is being welded into the panes again"
	)
	_check(
		director_source.contains("glass_layer.begin_capture(iaido_fx.focus_material)"),
		"The director does not arm the capture rig with the split material, so the panes would carry an uncut, un-greyed, un-voided picture"
	)
	_check(
		glass_source.contains("capture_viewport.world_3d = get_viewport().world_3d"),
		"The capture rig is not sharing the world it is photographing"
	)
	_check(
		glass_source.contains("capture_camera.cull_mask = camera.cull_mask"),
		"The capture rig's cull mask is not taken from the main camera, so it may draw layers the player never sees"
	)
	# ONE MATERIAL IN TWO VIEWPORTS IS NOT SAFE. The split shader reads its input
	# through `hint_screen_texture`, and a material drawn into two viewports in
	# the same frame resolves that binding once: arming the rig flattened the
	# MAIN frame into a pale sheet with no wound in it. A second material with
	# mirrored uniforms is one authority with two readers.
	_check(
		glass_source.contains("capture_material.shader = capture_split_material.shader"),
		"The capture rig is back to sharing the split material instance; arming it will flatten the main frame"
	)
	_check(
		glass_source.contains("capture_material.set_shader_parameter(")
			and glass_source.contains("get_shader_uniform_list()"),
		"The capture rig does not mirror the split uniforms, so the frozen picture is built from unset values"
	)
	# BEHAVIOURAL, not a source match: after arming, the rig's camera must not be
	# able to draw the foreground weapon layer at all.
	var glass: IaidoGlassLayer = iaido.glass_layer
	var fx: IaidoScreenFX = iaido.iaido_fx
	glass.begin_capture(fx.focus_material)
	_check(
		glass.capture_viewport != null and glass.capture_camera != null,
		"Arming the capture did not build a rig"
	)
	if glass.capture_camera != null:
		_check(
			(glass.capture_camera.cull_mask & ForegroundWeaponLayer.WEAPON_LAYER) == 0,
			"The capture rig can draw WEAPON_LAYER — the sword will be frozen into the glass again"
		)
		_check(
			glass.capture_viewport is SubViewport,
			"The capture rig is not a camera in its own viewport"
		)
		_check(
			glass.capture_material != null and glass.capture_material != fx.focus_material
				and glass.capture_material.shader == fx.focus_material.shader,
			"The rig's material is either missing or is the same instance the main frame draws with"
		)
	# The rig is a full-resolution 3D pass. It must not be left running.
	glass.reset()
	_check(
		not glass.capture_armed,
		"`reset()` left the capture rig armed; a full extra 3D pass runs for the rest of the session"
	)


func _verify_shared_fracture_field() -> void:
	var tuning: IaidoTuning = iaido.tuning
	_check(
		FileAccess.file_exists(FRACTURE_FIELD),
		"The shared fracture field is missing: %s" % FRACTURE_FIELD
	)
	if not FileAccess.file_exists(FRACTURE_FIELD):
		return
	var field := FileAccess.get_file_as_string(FRACTURE_FIELD)

	# Whoever draws the network has to include the one definition. A second copy
	# is the whole bug this file exists to prevent.
	for path in [WORLD_SHADER, PANE_SHADER]:
		var source := FileAccess.get_file_as_string(path)
		_check(
			source.contains("iaido_fracture_field.gdshaderinc"),
			"%s draws the fracture network without including the shared field" % path
		)
		_check(
			not source.contains("float iaido_fbm("),
			"%s defines its own copy of the field's noise" % path
		)

	# The pane pass must not be back on its own clock. `crack_front` /
	# `crack_reveal` were exactly that: a second, independently eased front over
	# a thing the world pass already had one of.
	var pane := FileAccess.get_file_as_string(PANE_SHADER)
	for stale in ["crack_front", "crack_reveal"]:
		_check(
			not pane.contains("uniform float %s" % stale),
			"The pane pass is back on its own `%s` clock instead of the shared fracture" % stale
		)
	for shared in ["fracture", "shatter", "stream", "dissolve"]:
		_check(
			pane.contains("uniform float %s" % shared),
			"The pane pass does not read the shared `%s`" % shared
		)

	# THE SPATIAL FIELD ITSELF. Same seeds and same frequencies on both sides of
	# the include boundary, or the panes and the world crack in different places.
	for pair in [
		["IAIDO_ORDER_ORIGIN", "vec2(31.7, 12.3)"],
		["IAIDO_ORDER_FREQ", "1.05"],
		["IAIDO_READY_SLOPE", "0.66"],
		["IAIDO_READY_SOFT", "0.16"],
		["IAIDO_WEIGHT_ORIGIN", "vec2(5.1, 9.3)"],
		["IAIDO_WEIGHT_FREQ", "3.4"],
		["IAIDO_WEIGHT_MIN", "0.05"],
		["IAIDO_STRESS_PER_FRACTURE", "1.20"],
		# SOURCED FROM THE TUNING, NOT COPIED. This list used to spell the front
		# out as the literal "360.0", which made it a second source of truth: the
		# moment the front was retuned the test failed for a reason that had
		# nothing to do with the shader. The constants that have a GDScript
		# mirror are stringified from that mirror, so this only ever asks "does
		# the field declare it".
		["IAIDO_FRONT_PER_FRACTURE", str(IaidoTuning.FRONT_PER_FRACTURE)],
		["IAIDO_FRONT_PER_SHATTER", "480.0"],
		["IAIDO_LIT_PER_FRACTURE", "1.15"],
		["IAIDO_LIT_PER_SHATTER", "0.85"],
	]:
		_check(
			field.contains("const float %s = %s;" % pair)
				or field.contains("const vec2 %s = %s;" % pair),
			"The shared field has no `%s = %s`" % pair
		)

	# ---- THE NET MUST NOT COME BACK ---------------------------------------
	#
	# The fracture stage rendered as a bright, even, frame-wide net — the
	# phone-screen spiderweb §1 forbids — and it got there arithmetically, not
	# by anyone drawing a net. Three numbers did it, and each of them is a
	# ratio rather than a taste, so each can be asserted:
	#
	#   front   if the front reaches the frame's own half-height at full
	#           fracture, `iaido_grown()` returns 1 across the whole picture and
	#           the network is complete from the first frame it lights. It has
	#           to still be travelling when the shatter takes over, or the
	#           branches cannot grow outward from the cut.
	#   weight  if the floor is high enough to be visible everywhere, every
	#           branch opens; §14 asks for some places to be left alone.
	#   slope   if it is near 1, every threshold is passed in the first third of
	#           the ramp and the stagger is real but invisible.
	var frame_half := 540.0
	for rule in [
		["IAIDO_FRONT_PER_FRACTURE", frame_half, "the front passes the frame's half-height before the shatter, so the net is complete rather than growing"],
	]:
		var declared := _const_value(field, String(rule[0]))
		_check(
			declared > 0.0 and declared < float(rule[1]),
			"%s is %s — %s" % [rule[0], declared, rule[2]]
		)
	_check(
		_const_value(field, "IAIDO_WEIGHT_MIN") < 0.10,
		"IAIDO_WEIGHT_MIN is %s — every branch opens and §14's 4-8 main branches are not expressible" % _const_value(field, "IAIDO_WEIGHT_MIN")
	)
	_check(
		_const_value(field, "IAIDO_READY_SLOPE") < 0.75,
		"IAIDO_READY_SLOPE is %s — the stagger is passed by every region at once and is invisible" % _const_value(field, "IAIDO_READY_SLOPE")
	)

	# ---- AND THE GDScript MIRROR OF THE FRONT ------------------------------
	#
	# `stream_arrived` is used to decide when a pane exists at all, so if it
	# disagrees with the shader the glass and the world stop agreeing about where
	# the front is — which is exactly the "floating screenshot" fault the shared
	# front exists to delete.
	for pair in [
		["IAIDO_LEAD_OVERSHOOT", tuning.STREAM_LEAD_OVERSHOOT],
		["IAIDO_ARRIVED_BACK", tuning.STREAM_ARRIVED_BACK],
		["IAIDO_ARRIVED_FRONT", tuning.STREAM_ARRIVED_FRONT],
	]:
		var pattern := "const float %s = " % pair[0]
		var at := field.find(pattern)
		_check(at >= 0, "The shared field has no `%s`" % pair[0])
		if at < 0:
			continue
		var line := field.substr(at, 60)
		var literal := line.split("=")[1].strip_edges().split(";")[0].strip_edges()
		_check(
			absf(literal.to_float() - float(pair[1])) < 0.000001,
			"%s is %s in the shader and %.4f in GDScript" % [pair[0], literal, float(pair[1])]
		)

	# ---- THE FRONT HAS TO FINISH, OR THE SLASH'S FAR END IS NEVER CLAIMED ---
	#
	# The regression this catches: the shader ran its head 14% past the end of
	# the line so `travel = 1.0` was finally covered, and the GDScript mirror did
	# not, so the panes at the far end of the slash topped out at 32% opacity
	# over world the screen pass had already fully eaten.
	_check(
		tuning.stream_arrived(tuning.glass_stream_end, 1.0) >= 0.99,
		"The front never reaches the end of the slash (arrived = %.3f at stream end)"
			% tuning.stream_arrived(tuning.glass_stream_end, 1.0)
	)
	_check(
		tuning.stream_arrived(tuning.glass_start, 1.0) <= 0.01,
		"The far end of the slash is already claimed before the stream starts"
	)
	# Monotonic in travel, so "further along the slash" is never less arrived.
	var previous := -1.0
	for step in 21:
		var t := float(step) / 20.0
		var at := tuning.stream_arrived(tuning.glass_stream_end, t)
		_check(
			at >= previous - 0.000001,
			"Arrival goes backwards along the slash at travel %.2f" % t
		)
		previous = at


func _arm_iaido() -> void:
	combat.iaido_ready_at = 0.0
	player.set("stamina", 100.0)


func _verify_full_run() -> void:
	var start: Vector3 = player.global_position
	_arm_iaido()
	if not combat.request(&"iaido"):
		_check(false, "Iaido request was rejected")
		return
	await physics_frame
	_check(iaido.active, "Iaido director did not activate")
	_check(root.get_tree().paused, "World was not paused for the ceremony")

	var guard := 0
	while iaido.active and guard < 2400:
		await physics_frame
		guard += 1
	_check(guard < 2400, "Iaido never reached restore_end")
	_check(iaido.elapsed >= iaido.tuning.restore_end - 0.05, "Iaido stopped early at %.2fs" % iaido.elapsed)

	# The redesign is a stationary world-stop slash, not a lunging step.
	_check(player.global_position.distance_to(start) < 0.6, "Player drifted during the stationary ceremony")
	_check(dummy.health < dummy.max_health, "Delayed active-frame hit never landed (health %.1f)" % dummy.health)
	_verify_panes_hold_until_the_click()
	_verify_restored("after full run")


# ---- 玻璃已经坏了，只是还没有掉 ---------------------------------------------
#
# §23: before the final click only a handful of panes are allowed to have moved
# at all — the design asks for two to five — and the final click is where
# structural failure happens. The difference either side of that instant is
# supposed to be enormous.
#
# That is a claim about the DATA, not about an animation. "The glass came apart
# too early" is impossible to see in any one frame and unmistakable the moment
# you read the panes' own release clocks, which is why it is checked here rather
# than watched for.
#
# V6 ran the material handover and the physical release off ONE clock, so every
# pane was handed a release time inside the fracture stream: the whole sheet had
# come apart and flown before the blade was half way home, and by the final click
# — the beat the design reserves for the collapse — there was nothing left to
# fail. Nothing about that was visible as a per-frame error.
func _verify_panes_hold_until_the_click() -> void:
	var tuning := iaido.tuning
	var panes: Array = iaido.glass_layer.shard_data
	_check(not panes.is_empty(), "The glass layer built no panes at all")
	if panes.is_empty():
		return
	var loose := 0
	var early := 0
	var drifting := 0
	for pane in panes:
		var at := float(pane["loose"])
		if at < tuning.collapse_start - 0.001:
			loose += 1
			if at < tuning.glass_stream_end - 0.001:
				early += 1
		else:
			_check(
				absf(at - tuning.collapse_start) < 0.001,
				"A pane is released at %.2fs, which is neither the loose window nor the final click" % at
			)
		var scale := float(pane["loose_scale"])
		if not is_zero_approx(scale):
			drifting += 1
			_check(
				scale > 0.0 and scale <= 0.25,
				"A loose pane drifts at %.2f of its collapse velocity — that is falling, not holding" % scale
			)
	_check(
		loose == tuning.shard_loose_count,
		"%d panes come loose before the final click, expected %d" % [loose, tuning.shard_loose_count]
	)
	_check(
		loose >= 2 and loose <= 5,
		"The pre-collapse loose count must be 2-5, is %d" % loose
	)
	_check(drifting == loose, "%d panes can drift but %d are marked loose" % [drifting, loose])
	_check(early == 0, "%d panes come loose before the fracture stream has finished" % early)


# NOTHING ON THE CAMERA MAY MOVE INSIDE A DEAD WINDOW.
#
# This is the general form of a bug that shipped twice, and the second time it
# was invisible to reading: the half-degree breath was measured on WALL time
# from `time_stop_end`, so it ran 3.58 -> 4.78 and carried straight on through
# the second dead window. Moving its start past the FIRST stop had looked like a
# fix, and it was — for that window.
#
# A pixel diff caught it. The grey+stop window measured 0.00% of pixels moving
# while the one second measured 0.78%, and every changed pixel sat on a
# silhouette edge with flat sky and flat ground untouched, which is a sub-pixel
# camera shift and cannot be anything else.
#
# Sampling the director's own outputs at three instants inside each window is the
# version of that check which runs on every pass instead of on every render, and
# unlike a pixel diff it says WHICH quantity moved.
func _verify_camera_is_dead_in_stops() -> void:
	_arm_iaido()
	var feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
	for window in iaido.tuning.time_stops():
		var w0: float = float(window[0])
		var w1: float = float(window[1])
		var probes := [
			w0 + (w1 - w0) * 0.10,
			(w0 + w1) * 0.5,
			w1 - (w1 - w0) * 0.10,
		]
		var reference := {}
		for index in probes.size():
			iaido.set_debug_hold(float(probes[index]))
			await physics_frame
			# Only the quantities that are supposed to be HELD. `elapsed` is the
			# ceremony clock and must keep running — that is the whole distinction
			# between a stopped WORLD and a stopped ceremony.
			var sample := {
				"iaido_pitch": feedback.iaido_pitch,
				"iaido_still": feedback.iaido_still,
				"fov_hold": feedback.fov_hold,
				"iaido_frame": feedback.iaido_frame,
				"iaido_frozen": feedback.iaido_frozen,
			}
			if index == 0:
				reference = sample
				_check(bool(sample["iaido_frozen"]), "Camera is not pinned inside the window at %.2fs" % w0)
				continue
			for key in sample:
				var a = reference[key]
				var b = sample[key]
				var same: bool
				if a is Vector2:
					same = (a as Vector2).is_equal_approx(b as Vector2)
				elif a is bool:
					same = a == b
				else:
					same = absf(float(a) - float(b)) < 0.00001
				_check(
					same,
					"camera %s keeps moving inside the dead window at %.2fs (%s -> %s)"
						% [key, w0, a, b]
				)
	iaido.release_debug_hold()
	iaido.finish_iaido()
	await physics_frame
	_verify_restored("after the camera-stop probe")


func _verify_scrub() -> void:
	_arm_iaido()
	for stage_time in [0.25, 1.00, 2.00, 2.85, 3.20, 3.55, 4.20, 4.80, 5.40, 6.40, 7.00]:
		iaido.set_debug_hold(stage_time)
		_check(iaido.active, "Scrub to %.2f did not activate the director" % stage_time)
		_check(absf(iaido.elapsed - stage_time) < 0.01, "Scrub to %.2f reported %.2f" % [stage_time, iaido.elapsed])
		await physics_frame
	iaido.release_debug_hold()
	iaido.finish_iaido()
	await physics_frame
	_verify_restored("after scrub")


func _verify_failsafe() -> void:
	_arm_iaido()
	if not combat.request(&"iaido"):
		_check(false, "Second Iaido request was rejected")
		return
	await physics_frame
	_check(root.get_tree().paused, "Second Iaido did not pause the world")
	# Hard abort: scene torn down mid-ceremony. Nothing may stay frozen.
	world.free()
	await physics_frame
	_check(not root.get_tree().paused, "Scene teardown left the tree paused")
	_check(Engine.time_scale == 1.0, "Scene teardown left time scaled at %.2f" % Engine.time_scale)


func _verify_restored(label: String) -> void:
	var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
	var screen_fx: CombatScreenFX = world.get_node("CombatScreenFX")
	var glass_layer: IaidoGlassLayer = world.get_node("IaidoGlassLayer")
	var hud: CombatHUD = world.get_node("CombatHUD")
	_check(combat.state == CombatController.State.IDLE, "Combat state not restored " + label)
	_check(Engine.time_scale == 1.0, "Time scale stuck at %.2f %s" % [Engine.time_scale, label])
	_check(not root.get_tree().paused, "Tree still paused " + label)
	_check(absf(camera_feedback.fov_hold) < 0.01, "FOV hold not cleared %s" % label)
	_check(camera_feedback.iaido_still < 0.01, "Camera stillness not cleared %s" % label)
	_check(not camera_feedback.iaido_frozen, "Camera freeze not cleared %s" % label)
	_check(screen_fx.desaturation < 0.01, "World grade not restored %s (%.2f)" % [label, screen_fx.desaturation])
	_check(not glass_layer.active, "Glass shards still active " + label)
	_check(hud.iaido_presence >= 0.99, "HUD was left faded %s" % label)
	_check(not iaido.active, "Director still active " + label)
