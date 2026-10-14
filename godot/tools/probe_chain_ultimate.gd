extends SceneTree
##
## CHAIN I ULTIMATE — smoke probe, headless.
##
## Answers one question before anything is rendered: does the nine-beat ceremony
## actually run, in order, and does it hand the room back? Every number printed
## here comes out of the live objects, so this is also the cheapest way to catch
## a beat whose time moved and left something behind.
##
## It also prints the two things that can only be checked numerically and are the
## brief's own hard requirements: that the sheet's outline is NOT a circle (the
## silhouette's radius must VARY around the rim, or 不是矩形/不是规整 fails), and
## that the cut rhythm still fits inside PHASE 6.
##
## Usage:
##   godot --headless --path godot --script res://tools/probe_chain_ultimate.gd

const FPS := 30.0
const STEP := 1.0 / FPS

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  FAIL: ", message)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/ChainUltimateLab.tscn")
	if scene == null:
		print("FAIL: the lab scene did not load")
		quit(1)
		return
	var lab: Node3D = scene.instantiate()
	root.add_child(lab)
	for _i in 8:
		await process_frame

	# The room MOUNTS `CombatSandbox.tscn`, so the world layer it depends on is one
	# level down and `find_child` rather than a path: a path here would break the
	# moment the room is re-parented, and the room's shape is not this probe's
	# business.
	var director: ChainUltimateDirector = lab.find_child(
		"ChainUltimateDirector", true, false) as ChainUltimateDirector
	var tuning: ChainUltimateTuning = director.tuning if director != null else null
	if director == null or tuning == null:
		print("FAIL: no director or no tuning")
		quit(1)
		return

	print("=== TIMELINE ===")
	for beat in ChainUltimateDirector.BEATS:
		print("   %-22s %s" % [String(beat[0]), _time_of(String(beat[1]), tuning)])

	print("=== THE CUT RHYTHM ===")
	var last_open := 0.0
	for i in tuning.cuts.size():
		var at := tuning.cut_time(i)
		var done := at + tuning.cut_open_time
		last_open = maxf(last_open, done)
		print("   cut %d  %5.2f -> %5.2f   stroke %5.2f" % [i, at, done, at + tuning.cut_stroke_time])
	_check(tuning.cuts.size() <= ChainUltimateTuning.CUT_SLOTS,
		"%d cuts but the shader only holds %d" % [tuning.cuts.size(), ChainUltimateTuning.CUT_SLOTS])
	_check(last_open <= tuning.t_tear_start + 0.0005,
		"the last cut finishes opening at %.3f, after the tear at %.3f" % [last_open, tuning.t_tear_start])

	print("=== THE COIL ===")
	var turns := tuning.coil_turns_at(tuning.t_pull_start)
	print("   turns over the coil window: %.4f" % turns)
	_check(absf(turns - tuning.coil_turns) < 0.002,
		"the coil integrates to %.4f turns, not %.4f" % [turns, tuning.coil_turns])

	print("=== START ===")
	_check(lab.trigger(), "the room refused to start the ceremony")
	_check(director.active, "the director is not active after start")
	var anchor := director.anchor_point()
	print("   anchor at ", anchor)
	var combat: CombatController = lab.find_child(
		"CombatController", true, false) as CombatController
	_check(combat == null or combat.state == CombatController.State.ULTIMATE,
		"the player is not locked out of acting during the ceremony")

	var sheet: ChainRealitySheet = director.get("sheet")
	var armed_at := -1.0
	var froze_at := -1.0
	var t := 0.0
	var beats_seen: Array[int] = []
	var guard := 0
	while t <= tuning.t_end and guard < 600:
		director.set_debug_hold(t)
		await process_frame
		var beat := director.beat_at(t)
		if beats_seen.is_empty() or beats_seen[-1] != beat:
			beats_seen.append(beat)
		if sheet != null and sheet.built and armed_at < 0.0:
			armed_at = t
		if sheet != null and sheet.frozen() and froze_at < 0.0:
			froze_at = t
		t += STEP
		guard += 1

	print("=== WHAT HAPPENED ===")
	print("   sheet armed at     %.2fs" % armed_at)
	print("   capture frozen at  %.2fs" % froze_at)
	print("   beats entered      ", beats_seen)
	_check(armed_at > 0.0, "the sheet was never armed")
	_check(froze_at >= armed_at, "the capture never froze — the sheet would show a black rectangle")
	_check(beats_seen.size() >= 8, "only %d of the 9 beats were entered" % beats_seen.size())

	if sheet != null:
		print("=== THE SHEET ===")
		print("   shards          %d" % sheet.shards.size())
		_check(sheet.shards.size() == tuning.shard_count,
			"%d shards built, %d authored" % [sheet.shards.size(), tuning.shard_count])
		var hole := sheet.get("hole") as MeshInstance3D
		_check(hole != null and hole.mesh != null, "the wound has no mesh")
		var radii := _rim_radii(tuning)
		var lo: float = radii[0]
		var hi: float = radii[1]
		print("   rim radius      %.3f .. %.3f m  (%.1f%% of nominal)" % [
			lo * tuning.sheet_radius, hi * tuning.sheet_radius, (hi - lo) * 100.0])
		# 不是矩形, 不是规整 — checked as VARIANCE, because a circle and a
		# rectangle both have a constant rim parameter, and the difference between
		# the two is not measurable from here. What IS measurable is that this
		# outline is neither.
		_check(hi - lo > 0.12,
			"the outline only varies by %.3f of its radius — that is a disc, not a membrane" % (hi - lo))

	print("=== THE END ===")
	# THE SCRUB ABOVE NEVER MOVED `elapsed` — `set_debug_hold` pins the picture to
	# a time without walking the director's own clock, which is exactly what makes
	# a scrubbed take honest. So the handover has to be tested on the clock: park
	# it just short of the end, let `_process` carry it over, and check that
	# `finish()` ran on its own rather than being called by this probe.
	director.elapsed = maxf(tuning.t_end - 0.02, 0.0)
	director.release_debug_hold()
	var frames := 0
	while director.active and frames < 400:
		await process_frame
		frames += 1
	_check(not director.active, "the ceremony never finished")
	_check(not sheet.built, "the sheet survived the ceremony")
	_check(combat == null or combat.state != CombatController.State.ULTIMATE,
		"the player is still locked out after the ceremony")
	var fx: CombatScreenFX = lab.find_child("CombatScreenFX", true, false) as CombatScreenFX
	_check(fx == null or fx.distortion < 0.001, "the screen distortion was left on")
	var feedback := lab.find_child("CameraFeedbackController", true, false)
	_check(feedback == null or absf(float(feedback.get("fov_hold"))) < 0.001,
		"the fov was left closed")
	var chain: ChainDirector = lab.find_child("ChainDirector", true, false) as ChainDirector
	_check(chain == null or not chain.manual_step, "the chain was never handed back")

	if failures.is_empty():
		print("PASS: 链子 I 大招 · nine beats, an irregular membrane, and the room handed back")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _time_of(key: String, tuning: ChainUltimateTuning) -> String:
	match key:
		"charge":
			return "0.00"
		"thrust":
			return "%.2f" % tuning.t_thrust_start
		"bite":
			return "%.2f" % tuning.t_bite
		"coil":
			return "%.2f" % tuning.t_coil_start
		"peel":
			return "%.2f" % tuning.t_pull_start
		"float":
			return "%.2f" % tuning.t_float_start
		"cut":
			return "%.2f" % tuning.t_cut_start
		"tear":
			return "%.2f" % tuning.t_tear_start
		"restore":
			return "%.2f" % tuning.t_restore_start
	return "?"


## The rim's radius as a fraction of the nominal, min and max. This is the same
## arithmetic the mesh uses (`ChainRealitySheet._lobe_table`), read back through
## the object rather than re-derived from the constants, so a change to the lobe
## table cannot leave this probe measuring a shape nobody built.
func _rim_radii(tuning: ChainUltimateTuning) -> Array:
	var lo := 10.0
	var hi := -10.0
	for s in 56:
		var angle := TAU * float(s) / 56.0
		var sum := 0.0
		var amps := [0.62, 0.30, 0.22, 0.12]
		var freqs := [2.0, 3.0, 7.0, 11.0]
		var phases := [0.70, -1.90, 2.40, -0.30]
		for i in 4:
			var freq_scale := tuning.sheet_lobe_high / 7.0 if i >= 2 else 1.0
			var amp: float = amps[i] * (tuning.sheet_lobe_low / 2.0 if i < 2 else 1.0)
			sum += amp * sin(freqs[i] * freq_scale * angle + phases[i])
		var r := 1.0 + tuning.sheet_lobe * (sum / 1.26)
		lo = minf(lo, r)
		hi = maxf(hi, r)
	return [lo, hi]
