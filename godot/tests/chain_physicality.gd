extends SceneTree
# 缚星链 · REAL CHAIN PHYSICALITY PASS 02 — how the chain LOOKS while it moves.
#
# THE QUESTION: can a player who cannot see a HUD, a skill name, an effect or a
# final sound read 松 / 甩 / 咬 / 绷 / 拉 / 砸 out of the motion alone?
#
# chain_integration.gd already proves the chain is a WEAPON — it sweeps, carries
# momentum, changes its inputs when taut, and its pull obeys a weight table. All of
# that can be true while the thing on screen is still A STRAIGHT LINE FROM THE
# HAND TO A TARGET, and that is exactly what the last clean tour showed. The
# weapon existed and the physicality did not.
#
# WHY THIS FILE CANNOT BE REPLACED BY THE EXISTING ONE: chain_integration calls
# `visual.update_chain(hand, head, vel, tension, DT)` with a tension IT CHOOSES.
# That is the right way to test the DRAWING and the wrong way to test the WEAPON,
# because the interesting question is what tension the DIRECTOR feeds it while a
# throw is in the air and what it feeds it while something is hooked — and nothing
# in the repository has ever asked either. A rope that is a rod for the entire
# bind is the single biggest reason a hook reads as a raycast, and it is invisible
# to every existing assertion.
#
# CLOCK: `chain.manual_step = true`, one step per physics frame, the same
# discipline the rest of the combat line uses — a 0.09s bite is a design decision
# and a test that has to land inside one must not depend on the frame rate of a
# shared machine.

const DT := 1.0 / 60.0
const PARK := Vector3(60.0, 0.0, 0.0)
# Somewhere a throw reaches the chain's limit with nothing in the way: the pure
# "I threw it into the world" case, which is where the rope is most visible.
const OPEN_STAND := Vector3(0.0, 1.0, -22.0)
# §8's tolerance, in two numbers. A handover is allowed to cost the one frame a
# direction change needs (the head has to pass through zero to come back) and the
# one frame a mass flung overhead needs at the top of its arc. It is not allowed
# to cost a PAUSE — see `_group_combo`, which measures the run rather than the
# minimum for exactly that reason.
const COMBO_LIVE := 6.0
const COMBO_STALL_MAX := 2
# §5/§6 on the terminal head. `HEAD_AIM_OK` is the cosine the blade has to beat
# against its own direction of travel (~56°); the run is how many consecutive
# frames it is allowed to lose that argument to a direction reversal.
const HEAD_AIM_OK := 0.55
const HEAD_AIM_MIN_SPEED := 2.0
const HEAD_AIM_RUN_MAX := 2
# The floor under the worst frame. The run and the share above are the shape of the
# failure and this is its depth, and the rig needs both: reverting `Ease.WHIP` to an
# explosive ease-out leaves the run at 2 frames and the share at 11% — the head still
# recovers quickly, it just recovers FROM a much worse place, and `worst_align` is
# the only reading that notices (0.52 → 0.14). See the mutation sweep.
const HEAD_AIM_WORST_MIN := 0.30
# §6's "no instant 90° reversal", as a number: the most the blade may swing round
# between two frames. A turn that beats this is a teleport, not a turn.
const HEAD_SNAP_MAX_DEG := 60.0
# The part of a throw's flight that still has rope to hang with: below this
# fraction of the chain's own length, its shape is evidence about the throw;
# above it, it is evidence about the limit. See `_group_the_throw`.
const THROW_SPARE_RATIO := 0.67
# Per-frame trace of group C, off by default. "Which frame loses the blade" is the
# question the aggregate readings cannot answer, and it is nearly always one
# specific transition rather than a property of the whole strike.
const TRACE_HEAD := false

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var chain: ChainDirector
var weapon: WeaponSlot
var lab: ChainLab
var moveset: ChainMoveset
var look_pivot: Node3D
var head_node: Node3D
var visual: ChainVisual
var failures: Array[String] = []
var metrics: Dictionary = {}
var events: Array[Dictionary] = []
var _frame := 0
# The player's standing height, held for the groups that measure the CHAIN rather
# than the player. See `_hold_ground`.
var _pin := false
var _pin_at := Vector3.ZERO
# Every technique the weapon actually started, in order. Read from the signal
# rather than from `active_move`, because "which cut came out" is exactly the kind
# of thing a demo silently gets wrong (see the sword line's notes on this).
var played: Array[StringName] = []
# The `speeds` / `heads` index of the LAST SAMPLE BEFORE each technique began, so a
# group can find the exact frames a given cut owned. Index-based rather than
# frame-based on purpose: the sample arrays and the loop are the same length by
# construction, so there is no offset to get wrong.
var starts: Array[int] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	await _wait(12)
	player = world.get_node("Player")
	combat = player.get_node("CombatController")
	weapon = player.get_node("WeaponSlot")
	chain = player.get_node("ChainDirector")
	look_pivot = player.get_node("CameraRig/LookPivot") as Node3D
	lab = world.get("chain_lab") as ChainLab
	if lab == null:
		_fail("the sandbox has no ChainLab, so the chain has no stage to be physical in")
		_finish()
		return
	moveset = chain.moveset
	chain.manual_step = true
	visual = chain.chain_visual
	head_node = visual.get_node_or_null("TerminalHead") as Node3D
	if head_node == null:
		_fail("the visual has no TerminalHead, so nothing below can read the head")
		_finish()
		return
	chain.chain_event.connect(_on_chain_event)
	chain.move_started.connect(func(m: ChainMove) -> void: played.append(m.id))
	weapon.equip(WeaponSlot.CHAIN)
	# The three variables this weapon runs on are read here rather than inferred:
	# a stage that draws them for a developer is not a stage.
	look_pivot.rotation.x = 0.0

	await _group_slack()
	await _group_the_throw()
	await _group_head()
	await _group_hook_beats()
	await _group_combo()
	await _group_orbit()
	await _group_weights()
	await _group_recovery()
	await _group_coils()

	_report()
	_finish()


# ============================================================================
#  A · SLACK — 松.  The chain hangs, and how much it hangs is a function of how
#  much rope is spare. §1: near is droopy, near-the-limit is nearly straight.
# ============================================================================

func _group_slack() -> void:
	var hand := Vector3(0.0, 1.4, 0.0)
	# §1 — THE REACHES ARE DERIVED FROM THE ROPE, NOT TYPED. They used to be the old
	# short chain's five metres, which stopped being the rope the moment V3 made it
	# ten: an assertion that samples 4.7m of a 10m chain is measuring a chain that is
	# still half coiled in the player's fist and calling it "stretched to its own
	# length".
	var reaches: Array[float] = [1.05, 2.0, 3.0, 4.0, 6.0, 8.0, moveset.chain_length]
	var readings: Array[float] = []
	for reach in reaches:
		var head := hand + Vector3(0.0, 0.0, -reach)
		# Tension is zero here on purpose: this is the HELD rope, the state the
		# player sees most of the time and the one that has to say "it is a chain".
		visual.update_chain(hand, head, Vector3.ZERO, 0.0, DT)
		readings.append(visual.drawn_slack())
	metrics["slack_at_home"] = readings[0]
	metrics["slack_at_limit"] = readings[readings.size() - 1]
	_check(
		readings[0] > 0.25,
		"a chain hanging at %.2fm of a %.2fm rope strays only %.3fm from straight — at rest it has to read as a hanging rope or nothing else about it can"
			% [1.05, moveset.chain_length, readings[0]]
	)
	# §1 SATURATION, AND IT IS THE WHOLE POINT OF A LONG WEAPON. Past a few metres of
	# spare the droop STOPS GROWING, because the surplus is coiled in the hand and is
	# not in the air to hang. Without this the drawing would sit pinned at its sag
	# limit for every frame of every technique, and §3's loose → straight beat would
	# have no room left to happen in — the chain would be a curtain, not a rope.
	var flat := true
	for i in range(1, readings.size() - 2):
		if absf(readings[i] - readings[0]) > 0.02:
			flat = false
	_check(
		flat,
		"the rope droops %.3fm at 1m of reach and %.3fm at 6m of a %.2fm rope — spare rope that is still coiled in the hand must not droop"
			% [readings[0], readings[4], moveset.chain_length]
	)
	var monotone := true
	for i in range(1, readings.size()):
		if readings[i] > readings[i - 1] + 0.005:
			monotone = false
	_check(
		monotone,
		"the rope's droop is not a function of how much rope is spare (%s) — a chain that sags the same amount at every distance is a shape, not a weight"
			% [readings]
	)
	_check(
		readings[readings.size() - 1] < 0.10,
		"a chain stretched to its own length still strays %.3fm — there is no such thing as \"no rope left\""
			% readings[readings.size() - 1]
	)
	# AND IT HANGS DOWN. A curve that bulges sideways or upward is a bow, not a sag.
	visual.update_chain(hand, hand + Vector3(0.0, 0.0, -2.4), Vector3.ZERO, 0.0, DT)
	var points := visual.drawn_points()
	var midpoint: Vector3 = points[points.size() / 2]
	var chord := hand.lerp(hand + Vector3(0.0, 0.0, -2.4), 0.5)
	metrics["sag_drop"] = chord.y - midpoint.y
	_check(
		chord.y - midpoint.y > 0.10,
		"the hanging chain's middle sits %.3fm below the straight line between its ends — a slack chain droops"
			% (chord.y - midpoint.y)
	)


# ============================================================================
#  B · THE THROW IS NOT A RAYCAST — 甩.  The single most important reading in
#  this file: what tension the DIRECTOR feeds while a throw is in the air.
# ============================================================================

func _group_the_throw() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	var run := await _record_throw()
	if run.is_empty():
		return
	var slack_min := 999.0
	var slack_loose := 999.0
	var slack_spare := 999.0
	var tension_before := 0.0
	var flight := 0
	for r in run:
		if not r["flying"]:
			continue
		flight += 1
		slack_min = minf(slack_min, r["slack"])
		# WHILE THE ROPE IS NOT AT ITS LIMIT IT MUST NOT BE STRAIGHT. Frames that
		# genuinely are taut are excluded, because a taut rope IS a straight line —
		# that is the one state where it is allowed to be one.
		if not r["taut"]:
			slack_loose = minf(slack_loose, r["slack"])
		# …AND THE MINIMUM OVER THAT SET IS THE WRONG READING, which measuring it
		# proved. "Not taut" includes the frames immediately BEFORE the limit, and
		# those frames have almost no rope spare left, so the rope is legitimately
		# nearly straight there: the reported 0.015m was the throw's own last
		# instant being counted as evidence about its whole flight. The question
		# §3 actually asks is whether the chain hangs while it still has rope to
		# hang WITH, so the reading is restricted to the part of the flight with
		# more than a third of the rope still spare.
		if r["ratio"] < THROW_SPARE_RATIO:
			slack_spare = minf(slack_spare, r["slack"])
		if r["ratio"] < 0.9:
			tension_before = maxf(tension_before, r["tension"])
	metrics["throw_frames"] = flight
	metrics["throw_min_slack"] = slack_min
	metrics["throw_loose_slack"] = slack_loose
	metrics["throw_spare_slack"] = slack_spare
	metrics["throw_tension_before_limit"] = tension_before
	_check(flight > 8, "the throw spent %d frames in the air — nothing about its shape was measured" % flight)
	_check(
		slack_spare > 0.12,
		"while it still has more than a third of the rope spare the thrown chain comes within %.3fm of straight (%.3fm anywhere before its limit) — it flies as a rigid rod, which is why a hook reads as a raycast and not as a thrown mass"
			% [slack_spare, slack_loose]
	)
	_check(
		tension_before < 0.45,
		"the drawing reads %.0f%% taut while the head is still well short of the limit — §3: a chain that gets progressively straighter has no beat in it"
			% (tension_before * 100.0)
	)
	# THE BEAT ITSELF (§3): loose → rapid tightening → straight. Measured, not
	# asserted from the code that is supposed to produce it.
	var start := -1.0
	var full := -1.0
	var peak_step := 0.0
	var prev := 0.0
	for r in run:
		var t: float = r["t"]
		var tension: float = r["tension"]
		if start < 0.0 and tension >= 0.40:
			start = t
		if start >= 0.0 and full < 0.0 and tension >= 0.95:
			full = t
		if start >= 0.0 and full < 0.0:
			peak_step = maxf(peak_step, tension - prev)
		prev = tension
	var beat := (full - start) if (start >= 0.0 and full >= 0.0) else -1.0
	metrics["tension_beat"] = beat
	metrics["tension_peak_step"] = peak_step
	_check(
		beat > 0.035 and beat < 0.20,
		"the chain goes from loose to straight in %.3fs — §3 wants a BEAT: quick enough to be a snap, slow enough to be seen. Instant is a model swap; gradual is the bug this pass exists to remove."
			% beat
	)
	# And once it IS at its limit it has to stay there: the snap is a state, not a
	# wobble the drawing happens to pass through.
	var taut_slack := 999.0
	for r in run:
		if r["taut"] and r["tension"] > 0.9:
			taut_slack = minf(taut_slack, r["slack"])
	metrics["taut_slack"] = taut_slack
	_check(
		taut_slack < 0.08,
		"a chain at its limit still strays %.3fm — §33 forbids the rubber band at exactly the moment it matters most"
			% taut_slack
	)


# ============================================================================
#  C · THE HEAD — 甩出去的那一坨.  It must point where it is going, and it must
#  not stop dead when the strike does (§5/§6).
# ============================================================================

func _group_head() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"light")
	var aligns: Array[float] = []
	var turns: Array[float] = []
	var speeds: Array[float] = []
	var prev_fwd := Vector3.ZERO
	var strike_end_at := -1
	var guard := 0
	var f := 0
	var was_swinging := false
	while guard < 400:
		guard += 1
		await _tick(1)
		f += 1
		var swinging := chain.state == ChainDirector.State.SWINGING
		if was_swinging and not swinging:
			strike_end_at = f
			break
		was_swinging = swinging
		if not swinging:
			continue
		var vel: Vector3 = chain.get("_head_velocity")
		var fwd := -head_node.global_basis.z
		if prev_fwd != Vector3.ZERO:
			turns.append(rad_to_deg(fwd.angle_to(prev_fwd)))
		prev_fwd = fwd
		if vel.length() > HEAD_AIM_MIN_SPEED:
			aligns.append(fwd.dot(vel.normalized()))
		speeds.append(vel.length())
		if TRACE_HEAD:
			print(
				"      head f=%2d st=%.3f r=%.2f v=%6.1f align=%+.2f turn=%3.0f" %
				[f, chain.state_time, chain.radius, vel.length(), fwd.dot(vel.normalized()) if vel.length() > 0.001 else 0.0, turns[turns.size() - 1] if turns.size() > 0 else 0.0]
			)
	# §5 — THE HEAD POINTS WHERE IT IS GOING.
	#
	# Measured as a RUN, not as a minimum, and the difference is the whole point.
	# A minimum is unreachable: a chain that reverses its arc has to rotate its
	# direction of travel through a large angle at the handover, and a head that is
	# INERTIAL (§6) cannot possibly have its blade already round when that happens.
	# So a reversal legitimately costs a frame or two, and what is forbidden is the
	# head spending a tenth of a second pointing at nothing.
	var worst_align := 1.0
	var bad_run := 0
	var run := 0
	var bad := 0
	for a in aligns:
		worst_align = minf(worst_align, a)
		run = run + 1 if a < HEAD_AIM_OK else 0
		bad_run = maxi(bad_run, run)
		bad += 1 if a < HEAD_AIM_OK else 0
	var bad_share := float(bad) / maxf(1.0, float(aligns.size()))
	metrics["head_align_worst"] = worst_align
	metrics["head_aim_bad_run"] = bad_run
	metrics["head_aim_bad_share"] = bad_share
	metrics["head_aim_frames"] = aligns.size()
	_check(
		bad_run <= HEAD_AIM_RUN_MAX,
		"the head's blade is more than %.0f° off its own direction of travel for %d frames in a row — §5: a head that does not face its own motion is a ball on a string, and a reversal may cost a frame or two, not a sixth of a second"
			% [rad_to_deg(acos(HEAD_AIM_OK)), bad_run]
	)
	_check(
		bad_share <= 0.20,
		"the head is misaligned on %.0f%% of the frames it is travelling (worst %.2f) — §5 wants the blade pointing where the head is going for a strike, not for four fifths of one"
			% [bad_share * 100.0, worst_align]
	)
	# §6 — INERTIAL TURNING. Two readings, because either one alone is trivially
	# satisfied by a head that is frozen or by one that is welded to its velocity.
	var biggest_turn := 0.0
	for t in turns:
		biggest_turn = maxf(biggest_turn, t)
	metrics["head_turn_worst_deg"] = biggest_turn
	_check(
		worst_align > HEAD_AIM_WORST_MIN,
		"at its worst the head's blade is %.2f off its own direction of travel (%.0f°) — even the frame a reversal costs is not allowed to leave the head pointing at nothing (§5)"
			% [worst_align, rad_to_deg(acos(clampf(worst_align, -1.0, 1.0)))]
	)
	_check(
		biggest_turn < HEAD_SNAP_MAX_DEG,
		"the head's blade turned %.0f° in a single frame — §6 asks for inertial turning: it may swing round fast, it may not teleport"
			% biggest_turn
	)
	_check(
		biggest_turn > 12.0,
		"the head's blade never turns more than %.0f° in a frame, so it is not tracking its own motion at all — orientation that never changes is a prop, not a thrown mass (§5)"
			% biggest_turn
	)
	# The strike stops feeding the mass; it does not remove it (§6).
	var peak := 0.0
	var peak_at := 0
	for i in speeds.size():
		if speeds[i] > peak:
			peak = speeds[i]
			peak_at = i
	metrics["head_peak_speed"] = peak
	metrics["head_frames"] = speeds.size()
	var coast_frames := 0
	var above := false
	for i in range(peak_at, speeds.size()):
		if speeds[i] > peak * 0.45:
			coast_frames += 1
			above = true
		elif above:
			break
	metrics["head_coast_frames"] = coast_frames
	metrics["head_strike_end"] = strike_end_at
	_check(
		coast_frames >= 2,
		"after the peak the head is above 45%% of its own top speed for %d frame(s) — the strike stops feeding the mass, it does not remove it (§6)"
			% coast_frames
	)


# ============================================================================
#  D · HOOK IS FOUR BEATS — 咬.  THROW → CONTACT → BITE → TENSION (§13). The
#  third one is the difference between a chain and a grappling hook.
# ============================================================================

func _group_hook_beats() -> void:
	await _park_everything()
	# Far enough out that backing away actually reaches the end of the rope: a
	# hooked chain only goes taut when the distance to what it caught reaches the
	# chain's own length, and a target at arm's length never will.
	var target := _place_target(&"medium", Vector3(0.0, 0.0, -25.6))
	if target == null:
		return
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	events.clear()
	chain.request(&"chain_hook")
	var guard := 0
	while guard < 240 and not chain.is_hooked():
		guard += 1
		await _tick(1)
	if not chain.is_hooked():
		_fail("the hook never caught a body standing 3.6m in front of it")
		return
	metrics["hook_frames_to_catch"] = guard
	metrics["hook_radius_at_catch"] = chain.radius
	metrics["hook_tension_at_contact"] = chain.tension
	_check(
		chain.tension < 0.55,
		"the rope is already %.0f%% straight on the frame it catches something — there is no bite to see, only a hit"
			% (chain.tension * 100.0)
	)
	# §17: standing still with something caught must leave the rope hanging. What
	# is hooked is ATTACHED, not necessarily at the end of the rope.
	await _wait(24)
	metrics["hooked_idle_tension"] = chain.tension
	metrics["hooked_idle_slack"] = visual.drawn_slack()
	_check(
		chain.tension < 0.92,
		"standing still with something hooked leaves the rope at %.0f%% straight — §17: a connection that never moves is a bar, not a rope"
			% (chain.tension * 100.0)
	)
	_check(
		visual.drawn_slack() > 0.10,
		"a hooked chain with %.2fm of itself still spare is only %.3fm off straight — the bind is the state the player looks at most and it is a rod"
			% [moveset.chain_length - chain.radius, visual.drawn_slack()]
	)
	var order := _event_order()
	metrics["hook_order"] = ",".join(order)
	metrics["hook_state"] = chain.state
	metrics["hook_radius_idle"] = chain.radius
	metrics["hook_events"] = events.size()
	var has_throw := order.has("CHAIN_THROW")
	var has_contact := order.has("CHAIN_CONTACT")
	var has_bite := order.has("CHAIN_BITE")
	var has_start := order.has("CHAIN_TENSION_START")
	_check(
		has_throw and has_contact and has_bite and has_start,
		"a hook announced %s — §13 says it is four beats (THROW · CONTACT · BITE · TENSION) and a weapon only has the beats it says out loud"
			% [order]
	)
	if has_contact and has_bite and has_start:
		var ci := order.find("CHAIN_CONTACT")
		var bi := order.find("CHAIN_BITE")
		var ti := order.find("CHAIN_TENSION_START")
		_check(
			ci < bi and bi <= ti,
			"the hook's beats arrive out of order: %s — the bite is what makes the chain look attached before it looks loaded"
				% [order]
		)
		var bite_frames := _event_frame("CHAIN_BITE") - _event_frame("CHAIN_CONTACT")
		metrics["bite_seconds"] = float(bite_frames) * DT
		_check(
			bite_frames > 2 and metrics["bite_seconds"] < 0.16,
			"the bite lasts %.3fs — §13 asks for 50–120ms: long enough to read as \"it has hold of something\", short enough that the rope still snaps"
				% metrics["bite_seconds"]
		)
	# ------------------------------- and then it snaps ------------------------
	# Walking away from what you caught is the 绷 event for a hooked chain: the
	# rope comes up against its own length and goes from hanging to dead straight.
	var walk := player.global_position
	var before_snap := visual.drawn_slack()
	# §1 — HOW FAR TO WALK IS DERIVED FROM THE ROPE. It used to be a flat 3m, which
	# was more than the old 4.6m chain had to give and is less than a third of what a
	# 10m one needs: the reading stopped at 5.74m of 9.70 and reported a broken hook
	# when the hook was fine. Walk until the head is actually AT the limit — and note
	# that the condition is the RADIUS and not `is_taut()`, because `is_taut()` is
	# true for the whole of a hook by rule (§17: what is caught is attached), so a
	# loop waiting on it would never take a step.
	var want_radius := moveset.max_radius * moveset.tension_ratio
	var walk_guard := int(ceil((moveset.max_radius + 1.0) * 20.0))
	var walked := 0
	while walked < walk_guard and chain.radius < want_radius:
		walked += 1
		walk += Vector3(0.0, 0.0, 0.05)
		# The walk IS the measurement, so it moves the player AND the height the
		# hold keeps: the body never falls off the deck.
		player.global_position = walk
		_pin_at = walk
		await _tick(1)
	metrics["hooked_walk_m"] = float(walked) * 0.05
	metrics["hooked_taut_slack"] = visual.drawn_slack()
	metrics["hooked_taut_tension"] = chain.tension
	_check(
		chain.radius >= moveset.max_radius * moveset.tension_ratio - 0.05,
		"backing %.1fm away from what the chain caught only stretched it to %.2fm of %.2f — the head is not following the thing it is attached to"
			% [float(metrics.get("hooked_walk_m", 0.0)), chain.radius, moveset.max_radius]
	)
	_check(
		visual.drawn_slack() < 0.08,
		"with the rope at its limit the chain is still %.3fm off straight — §33: a loaded chain IS a straight line, and that is the one state where it is allowed to be one"
			% visual.drawn_slack()
	)
	_check(
		before_snap > visual.drawn_slack() + 0.10,
		"the rope was %.3fm off straight while hanging and %.3fm once loaded — the two states have to be different pictures or the snap is not an event (§3)"
			% [before_snap, visual.drawn_slack()]
	)


func _group_combo() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	played.clear()
	starts.clear()
	var speeds: Array[float] = []
	var heads: Array[Vector3] = []
	chain.request(&"light")
	var guard := 0
	# MASHED, not choreographed. The next cut is asked for the instant the last one
	# lets go of the head, which is what a three-hit chain IS — and it is the only
	# way the handover can be measured at all.
	while guard < 900 and played.size() < 3:
		guard += 1
		# Captured BEFORE the tick: the index the sample about to be appended will
		# take, minus one is the last frame that belonged to the PREVIOUS technique —
		# which is what a coast's first step has to be measured against. Recording it
		# after the append is a one-frame lie in the direction that hides the coast.
		var mark := heads.size()
		await _tick(1)
		speeds.append((chain.get("_head_velocity") as Vector3).length())
		heads.append(chain.head_position())
		while starts.size() < played.size():
			starts.append(maxi(0, mark - 1))
		if played.size() < 3 and chain._can_act() and chain.state in [
			ChainDirector.State.SWINGING, ChainDirector.State.EXTENDING,
			ChainDirector.State.SLAMMING,
		]:
			chain.request(&"light")
	var id_text := ""
	for id in played:
		id_text += (String(id) + ",") if id_text != "" else String(id)
	metrics["combo_ids"] = id_text
	metrics["combo_frames"] = speeds.size()
	if played.size() < 3:
		_fail("only %d of the three cuts came out, so the sentence was not read" % played.size())
		return
	var ids := played.slice(0, 3)
	var profiles: Array[Dictionary] = []
	for id in ids:
		var move := moveset.get_move(id)
		if move == null:
			_fail("%s does not exist in the moveset" % String(id))
			return
		profiles.append({
			"arc": absf(move.arc_degrees), "radius_to": move.radius_to,
			"recovery": move.recovery, "continue": move.continue_from_head,
			"path": move.path, "ease": move.ease,
		})
	# §8 NEVER RESET THE CHAIN BETWEEN HITS. A reset is not subtle: a chain that
	# restarts comes to rest first.
	#
	# The first 14 frames are skipped because they are cut one's own startup, which
	# legitimately begins from a held chain — that is the only place in the
	# sequence where the head is allowed to be at rest.
	#
	# AND THE SLOWEST FRAME IS NOT THE READING. It was, until measuring it showed
	# why it cannot be: a chain that reverses direction has to pass through zero to
	# get there, and a head flung overhead has to stop at the top of its arc. Both
	# are CORRECT, both are one frame wide, and neither is a reset. A reset is a
	# PAUSE — the head parked while the next technique decides what to do — so the
	# reading is the longest RUN of frames the chain spends doing nothing, plus a
	# floor under the minimum so "came to a complete stop" is still caught.
	#
	# Baseline for both, before the carry anticipation existed: five consecutive
	# frames at 0.5–1.2 m/s at every handover.
	var peak := 0.0
	for s in speeds:
		peak = maxf(peak, s)
	var worst := 999.0
	var stall := 0
	var run := 0
	for i in range(mini(14, speeds.size()), speeds.size()):
		worst = minf(worst, speeds[i])
		run = run + 1 if speeds[i] < COMBO_LIVE else 0
		stall = maxi(stall, run)
	metrics["combo_peak_speed"] = peak
	metrics["combo_slowest_speed"] = worst
	metrics["combo_stall_frames"] = stall
	# `combo_slowest_speed` is REPORTED AND NOT ASSERTED, and the mutation sweep is
	# why. The obvious assertion — "the head never gets below walking pace" — cannot
	# be reddened by any honest mutation of the handover, because the slowest frame
	# of a three-cut combo is not a handover at all: it is the frame the arc's last
	# sample completes, and that frame is fast (the head covers the remainder of an
	# arc it was already sweeping at ~14 m/s) whatever the handover does. An
	# assertion no mutation can redden is the same lie as one no honest measurement
	# can satisfy, so the number stays in the report for the reader and the guard is
	# the stall below, which the carry anticipation genuinely moves: 0 → 6 frames.
	_check(
		stall <= COMBO_STALL_MAX,
		"the chain spends %d consecutive frames below %.0f m/s between its cuts — §8 does not forbid the one frame a reversal costs, it forbids the PAUSE: a handover that has to be waited out is three separate swings, not one sentence"
			% [stall, COMBO_LIVE]
	)
	# §7 THE COAST HAS A SHAPE, AND THE SHAPE IS NOT FREE.
	#
	# The handover's DISTANCE is the authored overrun, and `chain_integration` guards
	# it (direction, deadness, ceiling). What no other reading touches is how the head
	# covers that distance — and the sweep proved it, by re-shaping the coast from a
	# deceleration into the "deliver me to a pose" curve that every other move uses
	# and watching BOTH test files stay green. It matters because the two shapes say
	# opposite things about who is driving: a coast is at its FASTEST the moment the
	# cut starts and slows from there, because nothing is pulling any more; the
	# delivery curve starts slow, accelerates through the middle and eases off at the
	# end, which is a POWER STROKE the chain is not delivering — and the measured
	# version of it went 0.19 → 0.37 → 0.21 m/frame, i.e. the head picked speed back
	# up inside its own follow-through. So: the first frame of a carry is the fastest
	# frame of that carry, and the last is slower than the first.
	var carry := -1
	for k in range(1, ids.size()):
		if profiles[k]["continue"]:
			carry = k
			break
	if carry > 0 and starts.size() > carry:
		var carry_move := moveset.get_move(ids[carry])
		var a := starts[carry]
		var b := mini(a + maxi(2, int(roundf(carry_move.startup / DT))), heads.size() - 1)
		var steps: Array[float] = []
		for i in range(a + 1, b + 1):
			steps.append(heads[i].distance_to(heads[i - 1]))
		if steps.size() >= 3:
			var fastest := 0.0
			for s in steps:
				fastest = maxf(fastest, s)
			metrics["combo_coast_first_step"] = steps[0]
			metrics["combo_coast_last_step"] = steps[steps.size() - 1]
			metrics["combo_coast_fastest_step"] = fastest
			_check(
				steps[0] >= fastest * 0.75,
				"%s's startup peaks at %.3fm/frame in the middle of its coast against %.3fm in its first frame — the head is being DRIVEN through a follow-through, not left to coast (§7)"
					% [ids[carry], fastest, steps[0]]
			)
			_check(
				steps[0] > steps[steps.size() - 1],
				"%s's coast ends at %.3fm/frame against %.3fm where it started — it does not decelerate, so nothing about it reads as a mass nobody is pulling (§7)"
					% [ids[carry], steps[steps.size() - 1], steps[0]]
			)
		else:
			_fail(
				"%s's coast is only %d frames long, which is too short to read as a coast at all"
					% [ids[carry], steps.size()]
			)
	_check(
		profiles[1]["continue"] and profiles[1]["arc"] >= 120.0,
		"cut 2 (%s) does not pick the head up where cut 1 left it — §7 says the second beat CARRIES, not that it starts again"
			% [ids[1]]
	)
	# §A3 — THE THIRD BEAT CHANGES THE WEAPON'S SUBJECT, NOT ITS AXIS.
	#
	# The old assertion here was "cut 3 comes DOWN, because 横 · 横 · 纵", and it was
	# right about the old loop. V3's loop is 横 · 横 · 纵-to-the-HORIZON: the opening
	# pair are lateral arcs and the third throws the head down the crosshair, so what
	# has to be true is not a different axis but a different KIND of distance. Three
	# readings say that, and each of them can be reddened on its own:
	#   it is RADIAL — the head travels in/out on one bearing, not around the body;
	#   it out-reaches the sweeps by a margin a player can see, not by 10%;
	#   AND IT REACHES THE LIMIT, because the loop is the only place in normal play
	#   that can make the chain taut — and 绷切 / 曳 exist only while it is. A loop
	#   that cannot reach its own limit deletes two techniques from the weapon.
	_check(
		profiles[2]["path"] == ChainMove.Path.RADIAL,
		"cut 3 (%s) travels around the body instead of away from it — §A3 is the beat where the arc becomes a LINE"
			% [ids[2]]
	)
	_check(
		profiles[2]["radius_to"] > profiles[0]["radius_to"] * 1.8,
		"the throw ends at %.2fm against the opening sweep's %.2fm — §A3's precision attack has to be further away than the sweeps, or it is just another sweep with a narrower hitbox"
			% [profiles[2]["radius_to"], profiles[0]["radius_to"]]
	)
	_check(
		profiles[2]["radius_to"] >= moveset.max_radius * moveset.tension_ratio - 0.05,
		"the loop's longest technique stops at %.2fm of a %.2fm limit, so the normal attack loop can never make the chain taut — and while it is not taut, 绷切 and 曳 are techniques no input can reach"
			% [profiles[2]["radius_to"], moveset.max_radius]
	)
	_check(
		profiles[2]["recovery"] > profiles[0]["recovery"] * 1.3,
		"cut 3 recovers in %.2fs against the first cut's %.2fs — the CASH OUT is the heaviest beat of the three and its tail has to say so"
			% [profiles[2]["recovery"], profiles[0]["recovery"]]
	)
	# §8's mechanism, checked where it lives: a LATERAL arc must not end at zero
	# velocity, or the handover between sweeps is impossible however the moves are
	# ordered. The THROW is allowed to end at rest — but only because it ends AT THE
	# CHAIN'S LIMIT, which is not stopping, it is arriving. That exception is checked
	# above and this is the other half of it: nothing else may stop dead.
	for i in profiles.size():
		if profiles[i]["path"] == ChainMove.Path.RADIAL:
			continue
		_check(
			profiles[i]["ease"] == ChainMove.Ease.WHIP,
			"cut %d (%s) uses a plain ease-out, which has zero velocity at the end of its arc — a cut that stops dead hands the next cut a stopped chain"
				% [i + 1, ids[i]]
		)


# ============================================================================
#  F · ORBIT BUILDS — 蓄势.  §9: holding Heavy has to feel like it is getting
#  dangerous, and the chain straightening is one of the channels that says so.
# ============================================================================

func _group_orbit() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"heavy")
	if chain.state != ChainDirector.State.ORBITING:
		_fail("holding heavy did not start the orbit")
		return
	var early := {}
	var late := {}
	var guard := 0
	while guard < 160:
		guard += 1
		await _tick(1)
		if early.is_empty() and float(chain.get("_orbit_hold")) >= 0.20:
			early = _orbit_sample()
		if late.is_empty() and float(chain.get("_orbit_hold")) >= 1.15:
			late = _orbit_sample()
	if early.is_empty() or late.is_empty():
		_fail("the orbit never reached 1.15s of hold, so its build-up was not measured")
		return
	metrics["orbit_speed_early"] = early["speed"]
	metrics["orbit_speed_late"] = late["speed"]
	metrics["orbit_tension_early"] = early["tension"]
	metrics["orbit_tension_late"] = late["tension"]
	_check(
		late["speed"] > early["speed"] * 1.3,
		"the head goes round at %.1f m/s after a fifth of a second and %.1f m/s after a second — holding the button has to be visibly building something"
			% [early["speed"], late["speed"]]
	)
	_check(
		late["tension"] > early["tension"] + 0.08,
		"the chain's straightness barely changes across a full spin-up (%.2f → %.2f) — §9 lists 'chain straightening' as one of the channels that says THIS IS GETTING DANGEROUS"
			% [early["tension"], late["tension"]]
	)


# ============================================================================
#  G · THREE WEIGHTS, THREE PHYSICS PROBLEMS — 拉 (§18–§21).
# ============================================================================

func _group_weights() -> void:
	var out := {}
	for weight in [&"light", &"medium", &"heavy"]:
		var r := await _measure_yank(weight)
		if r.is_empty():
			continue
		out[weight] = r
		metrics["yank_%s_target" % weight] = r["target_moved"]
		metrics["yank_%s_player" % weight] = r["player_moved"]
	if out.size() < 3:
		_fail("only %d of the three weights could be pulled, so the weight table was not compared" % out.size())
		return
	_check(
		out[&"light"]["target_moved"] > out[&"light"]["player_moved"] * 1.8,
		"a light body moves %.2fm and the player %.2fm — §19: hooking something light is supposed to throw IT, not to drag you"
			% [out[&"light"]["target_moved"], out[&"light"]["player_moved"]]
	)
	_check(
		out[&"heavy"]["player_moved"] > out[&"heavy"]["target_moved"] + 0.25,
		"a heavy body moves %.2fm and the player %.2fm — §21: the first time you hook something heavier than you, the chain has to move YOU, or the weight table is a rumour"
			% [out[&"heavy"]["target_moved"], out[&"heavy"]["player_moved"]]
	)
	_check(
		out[&"medium"]["target_moved"] > 0.2 and out[&"medium"]["player_moved"] > 0.2,
		"a medium body moves %.2fm and the player %.2fm — §20: a medium pull is both bodies taking the load, not one of them sliding"
			% [out[&"medium"]["target_moved"], out[&"medium"]["player_moved"]]
	)


# ============================================================================
#  H · RECOVERY IS WHERE THE WEIGHT LIVES — 砸完还有分量 (§29).
# ============================================================================

func _group_recovery() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"chain_hook")
	var guard := 0
	while guard < 240 and not chain.is_taut():
		guard += 1
		await _tick(1)
	if not chain.is_taut():
		_fail("a thrown chain never reached its limit, so its return was not measured")
		return
	while guard < 900 and chain.state != ChainDirector.State.RETRACTING:
		guard += 1
		await _tick(1)
	if chain.state != ChainDirector.State.RETRACTING:
		_fail("the chain never began reeling in, so its recovery was not measured")
		return
	var frames := 0
	var prev := chain.head_position()
	var biggest_hop := 0.0
	var travelled := 0.0
	var slack_early := 0.0
	while guard < 900 and chain.state == ChainDirector.State.RETRACTING:
		guard += 1
		await _tick(1)
		frames += 1
		var now := chain.head_position()
		var hop := now.distance_to(prev)
		biggest_hop = maxf(biggest_hop, hop)
		travelled += hop
		prev = now
		if frames == 3:
			slack_early = visual.drawn_slack()
	metrics["recovery_frames"] = frames
	metrics["recovery_biggest_hop"] = biggest_hop
	metrics["recovery_travelled"] = travelled
	metrics["recovery_slack_early"] = slack_early
	_check(
		frames >= 12,
		"the full-length chain comes home in %d frame(s) — §29: reeling in a head thrown to the end of a rope is a piece of physical work and has to take time"
			% frames
	)
	# A SNAP-TO IS A SHARE OF THE JOURNEY, NOT A NUMBER OF METRES.
	#
	# This used to assert a flat 0.45m ceiling, which was calibrated when the reel
	# was 3.5m long. On a 10m chain the head genuinely has 8.5m to cover and the same
	# 0.30s reel moves it 0.47m in an average frame, so the old ceiling would have
	# failed a haul that was working perfectly — and raising it to 0.9 would have
	# been a guess that rots the next time the rope changes. What "not a snap-to"
	# ACTUALLY means is that no single frame contains the whole journey, so the
	# reading is the biggest hop as a share of the distance: measured at 9% here,
	# against 100% for a teleport.
	_check(
		biggest_hop < travelled * 0.35,
		"the head covers %.2fm of its %.2fm journey home in a single frame — that is a snap-to, not a haul"
			% [biggest_hop, travelled]
	)
	_check(
		moveset.retract_time >= 0.24,
		"the reel takes %.2fs, which is short for a mass on a rope" % moveset.retract_time
	)


# ============================================================================
#  RECORDING
# ============================================================================

# One throw into open space, sampled every frame. Deliberately NOT a hook onto a
# body: what is being measured is the rope on its way out, and a target would end
# the flight early by catching it.
func _record_throw() -> Array:
	var out: Array = []
	chain.request(&"chain_hook")
	if chain.active_move == null:
		_fail("the throw never started")
		return out
	var guard := 0
	while guard < 300:
		guard += 1
		await _tick(1)
		var st := chain.state
		var flying := st == ChainDirector.State.EXTENDING or st == ChainDirector.State.SWINGING
		out.append({
			"t": float(guard) * DT,
			"ratio": chain.radius / maxf(0.001, moveset.max_radius),
			"tension": chain.tension,
			"slack": visual.drawn_slack(),
			"flying": flying,
			"taut": chain.is_taut(),
			"state": st,
		})
		if not flying and chain.tension >= 0.98:
			break
	return out


func _orbit_sample() -> Dictionary:
	return {
		"speed": (chain.get("_head_velocity") as Vector3).length(),
		"tension": chain.tension,
		"momentum": chain.momentum,
	}


# Hook the body of a given weight, bind it, and measure how far each body went.
func _measure_yank(weight: StringName) -> Dictionary:
	await _park_everything()
	var target := _place_target(weight, Vector3(0.0, 0.0, -25.0))
	if target == null:
		return {}
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	var p0: Vector3 = player.global_position
	var t0: Vector3 = target.global_position
	chain.request(&"chain_hook")
	var guard := 0
	while guard < 240 and not chain.is_hooked():
		guard += 1
		await _tick(1)
	if not chain.is_hooked():
		_fail("缠锁 never caught the %s body" % String(weight))
		return {}
	# 缚 is the committed pull; it is the one that has to separate the weights.
	chain.request(&"chain_lock")
	while guard < 700 and int(chain.get("_tug_left")) > 0:
		guard += 1
		await _tick(1)
	await _wait(10)
	return {
		"target_moved": t0.distance_to(target.global_position),
		"player_moved": p0.distance_to(player.global_position),
	}


func _on_chain_event(event: StringName, _data: Dictionary) -> void:
	events.append({"name": String(event), "frame": _frame})
	if events.size() > 64:
		events.pop_front()


func _event_frame(name: String) -> int:
	for e in events:
		if e["name"] == name:
			return int(e["frame"])
	return -1


func _event_order() -> Array:
	var out: Array = []
	for e in events:
		out.append(e["name"])
	return out


# ============================================================================
#  STAGE
# ============================================================================

func _park_everything() -> void:
	var all: Array[Node3D] = [world.get_node("TechnicalDummy")]
	for t in lab.targets:
		all.append(t)
	for target in all:
		if not is_instance_valid(target):
			continue
		target.set_process(false)
		target.global_position = PARK
	for i in lab.crates.size():
		var crate := lab.crates[i]
		if not is_instance_valid(crate):
			continue
		crate.freeze = true
		crate.linear_velocity = Vector3.ZERO
		crate.global_position = PARK + Vector3(0.0, 0.5, 2.0 + float(i) * 1.2)
	chain.reset()


func _place_target(weight: StringName, position: Vector3) -> Node3D:
	var target := lab.target_for(weight)
	if target == null:
		_fail("the lab has no %s body to place" % String(weight))
		return null
	target.set_process(false)
	target.global_position = position
	target.rotation = Vector3.ZERO
	target.call("reset_dummy")
	return target


func _stand(position: Vector3, direction: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.set("external_velocity", Vector3.ZERO)
	player.look_at_from_position(position, position + direction, Vector3.UP)
	_pin = true
	_pin_at = position
	await _wait(14)


# THE PLAYER IS PART OF THE INSTRUMENT.
#
# `_head_velocity` is a WORLD-space quantity, and a CharacterBody3D left where
# `_stand` put it falls until it finds the deck. Measured on this rig's own probe:
# after a single cut the player was at 9.8 m/s downward, and that vector is added to
# every speed and every aim reading in this file. The one recovery frame the rig
# reported as 8.1 m/s belonged to a chain that was actually moving at 1.6 — a
# five-fold lie, in the direction that flatters the chain. So the players these
# groups measure FROM are held at the height they were stood at.
#
# The HEIGHT only: several groups deliberately move the player sideways (the walk
# away from a hooked body, and the three-weight pull), and those displacements are
# the measurement. What is neutralised is the fall, nothing else.
func _hold_ground() -> void:
	if not _pin:
		return
	var p := player.global_position
	player.global_position = Vector3(p.x, _pin_at.y, p.z)
	var v := player.velocity
	player.velocity = Vector3(v.x, 0.0, v.z)


# ONE CLOCK. `_wait` used to advance the world without advancing the chain, which
# is a second clock wearing the same name, and it cost a real measurement: the hook's
# bite is 0.09s of the DIRECTOR's time, so waiting it out with `_wait(24)` froze the
# chain through the one window the bite lives in and the rig reported a hook that
# announced two beats instead of four. Everything either advances both or neither.
func _tick(frames: int) -> void:
	for i in frames:
		await physics_frame
		_frame += 1
		_hold_ground()
		if chain != null:
			chain.step(DT)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
		_frame += 1
		_hold_ground()
		if chain != null:
			chain.step(DT)


# ============================================================================
#  I · THE WEAPON IS LONG, AND YOU CAN SEE IT — 链有多长 (§1 / §2 / §25 / §26).
#
#  THIS IS THE WHOLE OF V3's VISUAL BRIEF, AND NONE OF THE OTHER GROUPS TOUCH IT.
#  Every reading above is about how the chain BEHAVES — sag, snap, aim, carry,
#  weight — and all of them passed on a 4.7m weapon that read as a very long sword.
#  What V3 adds is not a behaviour at all: it is that a player standing still,
#  looking at their own hands, can see that they are holding ten metres of chain
#  and not two.
#
#  Two drawings answer that — the bundle in the hand and the links in the air — and
#  both are pure functions of the reach, so these assertions ask the same functions
#  the drawing asks and then check that a frame really was drawn from them (§25/§26).
# ============================================================================

func _group_coils() -> void:
	# 1 · THE COUNT AND THE ROPE AGREE. See `coil_per_loop`: a coil is the same loop
	#     size however much chain there is, so the NUMBER of loops is derived. Raising
	#     the rope without raising the bundle is exactly how a long weapon silently
	#     becomes a short one, so the two are checked against each other.
	var want_coils := int(roundf(moveset.chain_length / maxf(0.05, moveset.coil_per_loop)))
	metrics["coils_expected"] = want_coils
	_check(
		absi(moveset.coil_max - want_coils) <= 1,
		"a %.1fm rope is bundled into %d loops at %.2fm each — the bundle has to be a property of the ROPE, or making the chain longer makes it invisible (§26)"
			% [moveset.chain_length, moveset.coil_max, moveset.coil_per_loop]
	)
	# 2 · THE POOL IS BIG ENOUGH TO DRAW THE WHOLE ROPE. If it is not, the last metre
	#     of a full throw is dropped and the chain quietly ends short of its own limit
	#     — which is also the frame the snap is supposed to happen in.
	_check(
		float(moveset.links) * moveset.link_spacing >= moveset.chain_length,
		"the link pool draws %.2fm of rope but the chain is %.2fm — the end of a full throw would be missing"
			% [float(moveset.links) * moveset.link_spacing, moveset.chain_length]
	)
	# 3 · IDLE IS A FISTFUL.
	var at_home := visual.coils_for(moveset.home_radius)
	var at_limit := visual.coils_for(moveset.max_radius)
	metrics["coils_at_home"] = at_home
	metrics["coils_at_limit"] = at_limit
	_check(
		at_home >= 6,
		"a head hanging %.2fm from the hand leaves %d visible loops — §26 asks for 6–10, because the first thing a player has to understand is \"this chain is long, it is just coiled in my hand\""
			% [moveset.home_radius, at_home]
	)
	# 4 · …AND A FULL THROW IS NOT. Same hand, whole rope in the air.
	_check(
		at_limit <= 2,
		"with the head at the chain's limit %d loops are still coiled in the hand — the bundle has to empty as the rope pays out, or nothing about it reads as paying out (§2)"
			% at_limit
	)
	# 5 · PAYING OUT IS MONOTONE. A bundle that gains loops while the head is going
	#     away is a bundle that is not connected to the head.
	var previous := at_home
	var monotone := true
	for step in range(1, 9):
		var reach := moveset.max_radius * float(step) / 8.0
		var now := visual.coils_for(reach)
		if now > previous:
			monotone = false
		previous = now
	_check(
		monotone,
		"the bundle gains loops while the head is being thrown out — the coils are not reading the payout"
	)
	# 6 · A CONSTANT LINK SIZE, NOT A CONSTANT LINK COUNT (§25). The per-link length
	#     has to be the SAME at rest and at full stretch: that is the difference
	#     between a chain and a fence whose spacing changes with the throw.
	var short_link := 2.0 / maxf(1.0, float(visual.visible_links_for(2.0)))
	var long_link := moveset.max_radius / maxf(1.0, float(visual.visible_links_for(moveset.max_radius)))
	metrics["link_size_at_2m"] = short_link
	metrics["link_size_at_limit"] = long_link
	_check(
		absf(short_link - long_link) < 0.035,
		"a link measures %.3fm at 2m of reach and %.3fm at %.1fm — the link SIZE is changing with the throw, which is a fence being pulled straight rather than a chain being paid out (§25)"
			% [short_link, long_link, moveset.max_radius]
	)
	# 7 · AND A FRAME REALLY WAS DRAWN FROM THEM. The six readings above are about
	#     functions. A director that never calls them, or calls them with the wrong
	#     number, passes every one of them — so the last two ask the FRAME.
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	# A HELD CHAIN: no input at all, the pose the player spends most of the game in.
	await _tick(30)
	var drawn_coils := visual.coils()
	var drawn_links := visual.links_drawn()
	metrics["coils_drawn_idle"] = drawn_coils
	metrics["links_drawn_idle"] = drawn_links
	var lit := 0
	for loop in visual.coil_loops():
		if loop.visible:
			lit += 1
	_check(
		drawn_coils >= 6 and lit == drawn_coils,
		"the resting chain reports %d coils and lights %d of them — a bundle that is counted but not drawn is a number, not a weapon"
			% [drawn_coils, lit]
	)
	# And the other end of the same reading: throw it and watch the bundle empty.
	chain.request(&"chain_hook")
	var guard := 0
	while guard < 120 and chain.radius < moveset.max_radius * 0.9:
		guard += 1
		await _tick(1)
	var thrown_coils := visual.coils()
	var thrown_links := visual.links_drawn()
	metrics["coils_drawn_thrown"] = thrown_coils
	metrics["links_drawn_thrown"] = thrown_links
	_check(
		thrown_coils <= 2,
		"with the head thrown out to %.1fm there are still %d loops in the hand — the rope is not paying out" % [chain.radius, thrown_coils]
	)
	_check(
		thrown_links >= drawn_links * 5,
		"the rope is drawn with %d links hanging and %d links thrown — the drawing is not scaling with the payout at all (§25)"
			% [drawn_links, thrown_links]
	)


# ============================================================================
#  REPORT
# ============================================================================

func _report() -> void:
	print("")
	print("缚星链 · REAL CHAIN PHYSICALITY PASS 02")
	print("  松  slack %.3fm at home → %.3fm at the limit · hangs %.3fm below its own chord"
		% [metrics.get("slack_at_home", 0.0), metrics.get("slack_at_limit", 0.0), metrics.get("sag_drop", 0.0)])
	print("  甩  throw: %d frames · with rope to spare it strays %.3fm (%.3fm anywhere, %.3fm while loose) · reads %.0f%% taut before the limit · beat %.3fs"
		% [
			int(metrics.get("throw_frames", 0)), metrics.get("throw_spare_slack", 0.0),
			metrics.get("throw_min_slack", 0.0), metrics.get("throw_loose_slack", 0.0),
			float(metrics.get("throw_tension_before_limit", 0.0)) * 100.0,
			metrics.get("tension_beat", -1.0),
		])
	print("  绷  at the limit %.3fm off straight"
		% metrics.get("taut_slack", -1.0))
	print("  头  faces its motion to %.2f · bad for %d frames in a row / %.0f%% of the strike · turns %.0f°/frame · peak %.1f m/s · above 45%% for %d frames after it"
		% [
			metrics.get("head_align_worst", 1.0), int(metrics.get("head_aim_bad_run", 0)),
			float(metrics.get("head_aim_bad_share", 0.0)) * 100.0,
			metrics.get("head_turn_worst_deg", 0.0), metrics.get("head_peak_speed", 0.0),
			int(metrics.get("head_coast_frames", 0)),
		])
	print("  咬  order %s · bite %.3fs · %.0f%% taut at contact · caught at %.2fm after %d frames"
		% [
			metrics.get("hook_order", ""), metrics.get("bite_seconds", -1.0),
			float(metrics.get("hook_tension_at_contact", 0.0)) * 100.0,
			metrics.get("hook_radius_at_catch", 0.0), int(metrics.get("hook_frames_to_catch", 0)),
		])
	print("      events seen %d · state %d · hooked and standing still: %.0f%% taut · %.3fm off straight (%.2fm of rope spare)"
		% [
			int(metrics.get("hook_events", 0)), int(metrics.get("hook_state", -1)),
			float(metrics.get("hooked_idle_tension", 0.0)) * 100.0,
			metrics.get("hooked_idle_slack", 0.0),
			moveset.chain_length - float(metrics.get("hook_radius_idle", 0.0)),
		])
	print("      backed off to the limit: %.0f%% taut · %.3fm off straight"
		% [
			float(metrics.get("hooked_taut_tension", 0.0)) * 100.0,
			metrics.get("hooked_taut_slack", 0.0),
		])
	print("  返  %s · %d frames · slowest %.1f m/s (below %.0f for %d frames running) against a peak of %.1f"
		% [
			metrics.get("combo_ids", ""), int(metrics.get("combo_frames", 0)),
			metrics.get("combo_slowest_speed", 0.0), COMBO_LIVE,
			int(metrics.get("combo_stall_frames", 0)), metrics.get("combo_peak_speed", 0.0),
		])
	print("      咬之前的滑行  %.3f → %.3f m/frame（该段最快 %.3f，就在起手那一帧）"
		% [
			metrics.get("combo_coast_first_step", 0.0), metrics.get("combo_coast_last_step", 0.0),
			metrics.get("combo_coast_fastest_step", 0.0),
		])
	print("  蓄  orbit %.1f → %.1f m/s · straightness %.2f → %.2f"
		% [
			metrics.get("orbit_speed_early", 0.0), metrics.get("orbit_speed_late", 0.0),
			metrics.get("orbit_tension_early", 0.0), metrics.get("orbit_tension_late", 0.0),
		])
	print("  拉  轻 %.2fm/%.2fm · 中 %.2fm/%.2fm · 重 %.2fm/%.2fm  (目标/玩家)"
		% [
			metrics.get("yank_light_target", 0.0), metrics.get("yank_light_player", 0.0),
			metrics.get("yank_medium_target", 0.0), metrics.get("yank_medium_player", 0.0),
			metrics.get("yank_heavy_target", 0.0), metrics.get("yank_heavy_player", 0.0),
		])
	print("  收  reel %d frames · biggest single hop %.2fm · %.3fm off straight three frames in"
		% [
			int(metrics.get("recovery_frames", 0)), metrics.get("recovery_biggest_hop", 0.0),
			metrics.get("recovery_slack_early", 0.0),
		])
	print("  链  %.1fm 绳 / %d 圈（每圈 %.2fm）· 待机 %d 圈 %d 节 → 抛出 %d 圈 %d 节 · 每节 %.3fm · 池 %d 节 = %.1fm"
		% [
			moveset.chain_length, moveset.coil_max, moveset.coil_per_loop,
			int(metrics.get("coils_drawn_idle", -1)), int(metrics.get("links_drawn_idle", -1)),
			int(metrics.get("coils_drawn_thrown", -1)), int(metrics.get("links_drawn_thrown", -1)),
			metrics.get("link_size_at_limit", 0.0),
			moveset.links, float(moveset.links) * moveset.link_spacing,
		])
	print("")


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: the chain hangs, whips, bites, snaps, hauls and settles — read off the motion alone")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
