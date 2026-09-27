extends SceneTree
# PART J §27-§32. The Universal Sword measured through the six channels.
#
# WHY THIS FILE EXISTS: the sword currently passes "it works" and fails "it reads".
# A hundred lines of authoring can describe a beautiful swing that is completely
# indistinguishable from one that met nothing at all. This rig measures the four
# moments PART J §27 says must be SEPARATE - swing / contact / enemy reaction /
# recovery - and refuses an answer any of them borrows from another.
#
#   A. CONTACT vs WHIFF   §30  a swing over air must not read as a swing into a
#                              body. Measured against a whiff-vs-whiff noise floor,
#                              because two nominally identical runs are NOT bit
#                              identical in a real frame loop and any claim of
#                              "they differ" has to beat that noise first.
#   B. THE SWING MOMENT   §27  the whoosh and the camera must belong to the instant
#                              the blade leaves, not to the instant the key went
#                              down. Startup is 0.085s on a light and 0.185s on a
#                              heavy: that is 5 to 11 frames of audio leading the
#                              blade it claims to describe.
#   C. HITSTOP TAXONOMY   §28  Light / Heavy / Guard / Shatter must be four
#                              different answers, not one dial.
#   D. THE CLOCK          §28  hitstop must not eat the windows that were just
#                              fixed. Counted in PHYSICS FRAMES, which are
#                              simulation time, because wall-clock frames are
#                              exactly what a time scale steals.
#
# Every measurement here is taken in a stage assembled from the player alone. See
# movement_metrics.gd for why the shared sandbox is never the place to measure.

const TICK := 60.0
const BLADE_LENGTH := 0.95
# One frame of the authored 47rad/s tremor, measured, not guessed: this is the
# size of the thing that used to be mistaken for the swing.
const TREMOR_STEP := 0.0035

var world: Node3D
var player: CharacterBody3D
var lane: MovementLane
var combat: CombatController
var weapon: Node3D
var weapon_root: Node3D
var feedback: CameraFeedbackController
var audio: CombatAudioDirector
var failures: Array[String] = []
var metrics: Dictionary = {}
var target: Node3D

# Set from the controller's own signals so the measurement is the controller's
# claim, not the rig's bookkeeping.
var _swing_signal_at := -1.0
var _seen_cue: StringName = &""
var _seen_log := 0
var _audio_cue_at := -1.0
var _inject_travel := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _wait(frames: int) -> void:
	for _i in frames:
		await physics_frame


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	lane = MovementLane.new()
	world.add_child(lane)
	var packed: PackedScene = load("res://scenes/player/Player.tscn")
	player = packed.instantiate()
	# The controller reaches OUT of the player for its collaborators. A hermetic
	# stage therefore has to BE the scene it expects, not just contain a body:
	# without these three, `time_effects` is null and every request for hitstop
	# is a request into nothing, which reads exactly like "this build has no
	# hitstop" rather than "the stage forgot one".
	var screen := CombatScreenFX.new()
	screen.name = "CombatScreenFX"
	world.add_child(screen)
	var clock := TimeEffectManager.new()
	clock.name = "TimeEffectManager"
	world.add_child(clock)
	# The player goes in LAST on purpose: every @onready above resolves the
	# instant it enters the tree, so a collaborator added after it is invisible
	# to it and every hitstop below silently becomes "this game has none".
	world.add_child(player)
	combat = player.get_node("CombatController")
	# The player scene carries the sandbox's own coordinates and there is no
	# floor under them here: without this the body falls for the whole run and
	# every "swing" is a swing taken in mid-air, which no six-channel claim can
	# survive. This is the one thing the lane exists to answer.
	player.global_position = lane.start_position()
	await _wait(24)
	weapon = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")
	weapon_root = weapon.get_parent()
	feedback = player.get_node("CameraFeedbackController")
	audio = CombatAudioDirector.new()
	audio.name = "CombatAudioDirector"
	world.add_child(audio)
	await _wait(8)
	if player.get_node_or_null("WeaponSlot") != null:
		player.get_node("WeaponSlot").call("equip", &"sword")
	player.unlimited_resources = true
	if combat.has_signal("swing_started"):
		combat.swing_started.connect(func(_move: SwordMove) -> void:
			_swing_signal_at = combat.state_time
		)

	await _measure_contact_vs_whiff()
	await _measure_swing_moment()
	await _measure_hitstop_taxonomy()
	await _measure_window_under_hitstop()

	_report()
	if failures.is_empty():
		print("PASS: the universal sword answers swing / contact / enemy / recovery as four things")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)


# ------------------------------------------------------------------ A. contact

# A SIGNAL has to beat a NOISE FLOOR to be called a signal. Two whiffs in a row
# answer different frames with different deltas, and the pose driver integrates
# those deltas, so "these two runs differ" is worthless until we know how much
# two identical runs already differ.
func _measure_contact_vs_whiff() -> void:
	# HITSTOP IS SWITCHED OFF, and the RECOVERY ASYMMETRY IS NEUTRALISED, both
	# deliberately. A connect freezes the world and shortens the settle, and
	# either of those alone would let this channel pass on borrowed time from
	# §28/§31 instead of proving §30. What is left after both are removed is the
	# only thing that cannot be faked by another system: the blade itself.
	var previous_hitstop := combat.hitstop_scale
	combat.hitstop_scale = 0.0
	var move: SwordMove = combat.moveset.get_move(&"uni_l1")
	if move == null:
		_fail("the universal light move is not in the moveset, so no contact claim can be made")
		return
	var saved_hit := move.hit_recovery_scale
	var saved_miss := move.miss_recovery_scale
	move.hit_recovery_scale = 1.0
	move.miss_recovery_scale = 1.0
	# AND THE TREMOR IS TAKEN OUT. It is authored high-frequency wobble, present
	# in both runs, invisible as an event and sampled at a different phase every
	# time the loop runs — two identical whiffs disagree by two centimetres of it,
	# which is half the size of the thing being measured. Measuring it would be
	# measuring the loop, not the blade.
	var saved_tremor := combat.moveset.tremor
	combat.moveset.tremor = 0.0
	var hit_run := await _swing_with_target()
	var miss_run := await _swing_without_target()
	var noise_run := await _swing_without_target()
	combat.moveset.tremor = saved_tremor
	move.hit_recovery_scale = saved_hit
	move.miss_recovery_scale = saved_miss
	combat.hitstop_scale = previous_hitstop

	var idle_hop: float = miss_run["idle"]
	metrics["idle_tip_travel"] = idle_hop
	_check(
		idle_hop < 0.02,
		"the blade travelled %.4fm while standing still — nothing downstream means anything if a resting sword will not hold still"
			% idle_hop
	)

	var contact_frame: int = hit_run["contact"]
	if contact_frame < 0:
		_fail("a swing aimed straight at a body never connected — nothing below can be read")
		return

	# THE MEASUREMENT'S OWN ALIBI. The driver takes its contact direction from the
	# blade's last frame of travel, and for a long time that number was the
	# authored tremor instead — 0.0035m of wobble standing in for 0.17m of cut,
	# pointing wherever the sine happened to be. Both runs looked identical and
	# the deflection "worked", so this is asserted, not printed: a contact
	# answered by the wobble is not a contact at all.
	metrics["contact_travel"] = _inject_travel
	_check(
		_inject_travel >= 0.02,
		"the blade was covering %.4fm per frame when it was stopped — the authored tremor alone is %.4fm, so this contact was answered by the wobble rather than by the cut, and every number below is noise"
			% [_inject_travel, TREMOR_STEP]
	)

	# How far one blade's PATH ever leaves the other blade's PATH.
	#
	# Neither frame-to-frame nor phase-to-phase. Frame-to-frame compares WALL
	# CLOCKS: landing a hit costs the tree a sliver of a frame, and during the
	# fastest part of the arc that sliver of phase shift reads as nineteen
	# centimetres of "difference" that vanishes again once the blade slows.
	# Phase-to-phase is honest but still measures timing, and timing between two
	# identical whiffs is not something a player can feel.
	#
	# `noise_run` exists so that nothing here is believed without being put next
	# to two runs that ARE the same swing: the floor is measured, never assumed.
	# Compared only while the move itself is running — past its end the two runs
	# are in different states and "the same instant" stops meaning anything.
	var into_body := _path_departure(hit_run, noise_run, contact_frame)
	var over_air := _path_departure(miss_run, noise_run, contact_frame)
	var shape := _path_departure(hit_run, miss_run, contact_frame)
	var pointwise_noise := minf(into_body, over_air)
	print("  [diag] shape-runs frames hit=%d miss=%d noise=%d · into_body=%.4f over_air=%.4f shape=%.4f"
		% [
			int(hit_run["move_frames"]), int(miss_run["move_frames"]), int(noise_run["move_frames"]),
			into_body, over_air, shape,
		])
	var travel_ratio := absf(_travel(hit_run["tips"], contact_frame) - _travel(miss_run["tips"], contact_frame)) / maxf(_travel(miss_run["tips"], contact_frame), 0.0001)

	metrics["tip_divergence_contact"] = shape
	metrics["tip_divergence_air"] = pointwise_noise
	metrics["tip_travel_ratio"] = travel_ratio
	metrics["tip_travel_into_body"] = _travel(hit_run["tips"], contact_frame)
	metrics["tip_travel_over_air"] = _travel(miss_run["tips"], contact_frame)

	# TWO claims, deliberately split. The second one (below) is the physical one
	# and it is measured against a floor; the first is exact, because it reads the
	# weapon's own spring instead of inferring it from a jittery trajectory. A
	# deflection that is committed but never reaches the transform is still a
	# broken channel, and a blade that moves without the force behind it is a
	# different bug — either one alone can satisfy only half of this.
	var deflection: float = hit_run["first_deflection"]
	metrics["contact_deflection"] = deflection
	metrics["whiff_deflection"] = miss_run["first_deflection"]
	metrics["stacked_deflection"] = hit_run["deflection"]
	_check(
		deflection >= 0.03 and miss_run["deflection"] <= 0.001,
		"the hand committed %.4fm of deflection into a body and %.4fm into air — §27: contact is its own channel, and a whiff must not be handed one"
			% [deflection, float(miss_run["deflection"])]
	)

	_check(
		shape >= 0.02 and shape > maxf(pointwise_noise * 2.0, 0.008),
		"a blade that met a body leaves the whiff's path by %.4fm against a %.4fm floor measured the same way between two whiffs — §30: a whiff has to read as a MISS, and these are one swing wearing two captions"
			% [shape, pointwise_noise]
	)

	# The second contact must still answer the CUT, not the spring. If the
	# driver reads its own deflection back into the travel that decides the next
	# one, the direction it commits here points along the spring's recovery
	# instead of along the blade — and a combo then feels like the sword is
	# fighting itself rather than the body.
	var second_dir: Vector3 = hit_run["second_dir"]
	var second_travel: Vector3 = hit_run["second_travel"]
	var agreement := second_dir.dot(second_travel) if second_dir.length_squared() > 0.0 else -1.0
	metrics["second_contact_agreement"] = agreement
	_check(
		agreement >= 0.5,
		"the second contact committed a direction %.2f against the pose's own travel (1.0 is the same way, -1.0 is straight back along the spring) — the hand is resisting its own recovery instead of the body, so every hit after the first one argues with the one before it"
			% agreement
	)

	var hit_frames: int = hit_run["move_frames"]
	var miss_frames: int = miss_run["move_frames"]
	_check(
		absf(hit_frames - miss_frames) < 2,
		"the two shape runs took %d and %d frames even with the recovery asymmetry switched off — the measurement above is comparing a finished swing against an unfinished one and its number means nothing"
			% [hit_frames, miss_frames]
	)

	# §31, and the one thing the shape measurement above was forbidden to use.
	# Recovery is where weight lives: connecting shortens it because the blade
	# found what it was looking for, missing leaves the arm out holding nothing.
	# Measured with the real authoring restored.
	var timed_hit := await _swing_with_target()
	var timed_miss := await _swing_without_target()
	metrics["hit_move_frames"] = int(timed_hit["move_frames"])
	metrics["miss_move_frames"] = int(timed_miss["move_frames"])
	_check(
		absf(int(timed_hit["move_frames"]) - int(timed_miss["move_frames"])) >= 2,
		"a connected cut and an identical whiff both take %d frames — §31: recovery is where weight lives, and nothing here distinguishes paying for a hit from paying for a miss"
			% int(timed_miss["move_frames"])
	)


# How far one blade's PATH ever leaves the other blade's path.
#
# Not frame-to-frame, and not phase-to-phase. The tip covers seven centimetres
# between physics frames while the blade is actually moving, so asking "where
# was the other blade at the same instant" turns a sliver of timing difference
# into several centimetres of imaginary disagreement — including between two
# whiffs that a player could not tell apart. Sampling timing is not something
# the player can feel, so a metric that can hear it is measuring the wrong thing.
#
# Distance from each point of one run to the other run's POLYLINE measures what
# actually differs: does this blade trace somewhere the other one never went?
# That is insensitive to where the samples happened to land, and it is what "the
# swing reads differently" means.
# How far one blade's PATH ever leaves the other blade's PATH, compared as
# SHAPES: same fraction of the arc travelled, whatever speed either one took.
#
# This has to be speed-invariant or it is not measuring shape. A connected cut
# and a whiff no longer take the same time (§31, measured separately below), so
# comparing them at the same frame — or at the same state_time — silently
# answers "yes they differ" out of the timing difference alone. A mutation that
# deleted the contact deflection entirely still PASSED that version, which is
# what proved it: the assertion was being fed by the clock, not by the blade.
#
# Reprogramming by arc length takes speed out of the question. Two runs of the
# same curve at different rates land on top of each other and return the floor.
# How much FURTHER the blade had to travel, measured over each run's own whole
# remaining arc — not to the same frame, and not to the same fraction of one.
#
# The two runs no longer take the same time (§31, measured separately below), so
# any comparison that stops both at the same frame compares a finished swing
# against an unfinished one. And resampling by fraction-of-arc compares "30% of
# this swing" against "30% of that swing", which are not the same anatomical
# instant either — that version returned 0.27m between two cuts that differ by
# five centimetres.
#
# Total path length over the move's own duration is the one shape measure that
# is blind to speed: a slower swing traces the same curve and covers the same
# distance. What it does see is the detour — the blade knocked off its line and
# brought back — which is precisely what a whiff does not contain.
# How far one blade's PATH ever leaves the other blade's PATH.
#
# Deliberately boundary-free: every sample of one run is measured against the
# other run's WHOLE curve. Integrating "how far did each travel" fails here
# because the answer then depends on where the window was cut, and a window cut
# on frames moves by half a frame between two identical runs — two whiffs
# differed by 0.028m purely on that, which is the size of the whole effect.
# Points at the end of a swing lie on the other swing's curve, so adding or
# losing one changes nothing: what is left is genuine departure.
func _path_departure(sample_a: Dictionary, sample_b: Dictionary, first: int) -> float:
	var tips_a: Array = _smooth(sample_a["tips"] as Array)
	var tips_b: Array = _smooth(sample_b["tips"] as Array)
	var worst := 0.0
	var i := first
	while i < tips_a.size():
		worst = maxf(worst, _distance_to_polyline(tips_a[i] as Vector3, tips_b))
		i += 1
	return worst


# The blade is authored with a high-frequency tremor on purpose, and the loop
# does not sample that tremor at the same phase twice. Two IDENTICAL whiffs
# therefore disagree by up to five centimetres of wobble that no player can see
# — and that is the size of the effect being measured here. A five-tap mean is
# blind to it (the tremor cycles about eight times a second) and keeps the
# deflection, which lasts ten times as long.
func _smooth(tips: Array) -> Array:
	var out: Array[Vector3] = []
	for i in tips.size():
		var sum := Vector3.ZERO
		var count := 0
		for k in range(-2, 3):
			var j := i + k
			if j < 0 or j >= tips.size():
				continue
			sum += tips[j] as Vector3
			count += 1
		out.append(sum / maxf(count, 1))
	return out


func _distance_to_polyline(point: Vector3, line: Array) -> float:
	var best := 1e9
	for j in line.size() - 1:
		var a := line[j] as Vector3
		var b := line[j + 1] as Vector3
		var edge := b - a
		var span := edge.length_squared()
		var u := 0.0 if span < 1e-9 else clampf((point - a).dot(edge) / span, 0.0, 1.0)
		best = minf(best, point.distance_to(a + edge * u))
	return best



func _travel(tips: Array, first: int) -> float:
	var total := 0.0
	var i := first
	while i < tips.size() - 1:
		total += (tips[i + 1] as Vector3).distance_to(tips[i] as Vector3)
		i += 1
	return total


# One attack, nothing carried into it. Without this the third light of this file
# is not a light at all: a live riposte window turns `request(&"light")` into the
# RIPOSTE move (hitstop 0.050), and the measurement reports a number for a move
# nobody asked for. That is not a false reading of a value, it is a reading of a
# different song.
func _neutralise() -> void:
	combat.chain_expires_at = 0.0
	combat.combo_index = 0
	combat.last_light_at = -10.0
	combat.pending_followup_id = &""
	combat.followup_until = 0.0
	combat.riposte_until = 0.0
	combat.bind_until = 0.0
	combat.slip_until = 0.0
	combat.slip_skill = null
	combat.edge_glint = false
	combat.move_startup_override = -1.0
	combat.move_startup_scale = 1.0
	combat.next_move_startup_scale = 1.0
	combat.buffer.clear()


func _swing_with_target() -> Dictionary:
	_spawn_target()
	await _wait(3)
	return await _swing_sample(true)


func _swing_without_target() -> Dictionary:
	if target != null:
		_remove_target()
		await _wait(3)
	return await _swing_sample(false)


func _spawn_target() -> void:
	target = Node3D.new()
	target.name = "ChannelTarget"
	world.add_child(target)
	var forward := -player.global_basis.z
	target.global_position = weapon_root.global_position + forward * 1.35
	CombatHurtbox.build_for(target, Vector3(0.9, 1.8, 0.9))


func _remove_target() -> void:
	if target == null:
		return
	target.queue_free()
	target = null
	await _wait(2)


# One light cut, stepped by hand on a FIXED delta.
#
# Stepping the real frame loop makes every swing a different experiment: the
# pose driver is an exponential lag on a delta that varies by a few percent per
# frame, so two IDENTICAL whiffs drift a centimetre or two apart on the fastest
# part of the arc — and the effect being looked for here is four. Every metric
# tried against that loop measured the loop: the "noise floor" between two
# whiffs was the same size as the signal, and smoothing, arc-length
# reparameterisation and phase alignment all failed to separate them.
#
# So the controller, the weapon and the body are taken off the tree's clock and
# advanced here, 1/60s at a time. Two whiffs then produce two trajectories that
# are identical to the last bit, and any difference left is the contact.
#
# The blow itself is delivered rather than detected (the overlap that would
# normally fire it needs a physics step we are deliberately not taking), but it
# enters through the same `_on_hitbox_landed` a real one does.
func _swing_sample(with_contact: bool) -> Dictionary:
	await _wait_until_idle()
	_release_block()
	await _wait(1)
	_neutralise()
	await _wait_until_still()
	weapon.pose_time = 0.0
	combat.set_process(false)
	weapon.set_process(false)
	player.set_physics_process(false)
	feedback.set_process(false)
	var tips: Array[Vector3] = []
	var times: Array[float] = []
	var peak_dip := 0.0
	var contact := -1
	var move_frames := 0
	var idle_tips: Array[Vector3] = []
	var second_dir := Vector3.ZERO
	var first_deflection := 0.0
	var second_pose_travel := Vector3.ZERO
	for _i in 10:
		_step()
		idle_tips.append(_tip())
	combat.request(&"light")
	for _i in 140:
		_step()
		tips.append(_tip())
		times.append(combat.state_time)
		move_frames += 1
		peak_dip = maxf(peak_dip, absf(float(contact_readout().get("contact", 0.0))))
		# Mid-strike, not at the first frame of the strike window: at that instant
		# the blade has just finished the wind-up and is barely moving, so there
		# is no travel direction worth resisting and the driver is right to refuse.
		# A real hit arrives while the blade is actually going somewhere.
		if with_contact and contact < 0 and combat.state == CombatController.State.ATTACK and combat.state_time >= combat.effective_startup() + combat.active_move.strike * 0.5:
			# How far the blade was actually going when it was stopped. Reported
			# rather than asserted, because it is the sanity check on every number
			# below: a contact whose travel is the size of the authored tremor is a
			# contact answered by the wobble, not by the cut, and it was — the
			# driver used to take its direction from whatever the tremor happened
			# to be doing that frame, which is why this is measured at all.
			_inject_travel = (weapon.get("_travel_step") as Vector3).length()
			combat._on_hitbox_landed({
				"damage": 18.0, "poise_damage": 15.0, "impulse": 2.0,
				"element": &"physical", "target": target, "source": player,
			})
		# A SECOND CONTACT, four frames into the first one's spring.
		#
		# One hit cannot reveal what a sword does when it is still ringing from
		# the last one, and the driver's own comment says the trap: if the
		# deflection is read back into the travel that decides the NEXT contact,
		# then the second blow of a combo argues with the first, and the hand
		# starts resisting the spring instead of the body. Nothing in a
		# single-contact measurement can see that, so there are two here, and the
		# direction the driver commits on the second one is compared against the
		# POSE's own travel — computed here, independently, so that a driver
		# polluting its own bookkeeping cannot agree with itself.
		if with_contact and contact >= 0 and second_dir == Vector3.ZERO and tips.size() >= contact + 4:
			# Banked before the second blow lands: `peak_dip` from here on is two
			# contacts stacked on one spring, which is a fine thing to know and a
			# useless thing to quote as "what one contact does".
			first_deflection = peak_dip
			combat._on_hitbox_landed({
				"damage": 14.0, "poise_damage": 10.0, "impulse": 1.0,
				"element": &"physical", "target": target, "source": player,
			})
			second_dir = (weapon.get("_contact_dir") as Vector3).normalized()
			second_pose_travel = _pose_travel.normalized()
		if combat.move_hit and contact < 0:
			contact = tips.size() - 1
		if combat.state != CombatController.State.ATTACK and tips.size() > 4:
			break
	for _i in 40:
		_step()
		tips.append(_tip())
		times.append(combat.state_time)
		peak_dip = maxf(peak_dip, absf(float(contact_readout().get("contact", 0.0))))
	combat.set_process(true)
	weapon.set_process(true)
	player.set_physics_process(true)
	feedback.set_process(true)
	await _wait_until_idle()
	var distance := -1.0
	if target != null:
		distance = weapon_root.global_position.distance_to(target.global_position)
	return {
		"tips": tips, "times": times, "contact": contact, "move_frames": move_frames,
		"idle": _travel(idle_tips, 0), "hit": combat.move_hit, "target_distance": distance,
		"deflection": peak_dip, "second_dir": second_dir, "second_travel": second_pose_travel,
		"first_deflection": first_deflection,
	}


const STEP := 1.0 / 60.0


# The pose's own travel, worked out here rather than read from the driver. A
# driver that feeds its own output back into its input will happily agree with
# itself, so the second-contact direction below is checked against an
# independently computed curve — see the two-contact note in _swing_sample.
var _pose_prev := Vector3.ZERO
var _pose_travel := Vector3.ZERO


func _step() -> void:
	# Typed explicitly: `weapon` is declared Node3D, so its pose fields come back
	# as Variant and an inferred `tip` will not compile.
	var posed: Vector3 = weapon.pose_position
	var tip := posed + (Basis.from_euler(weapon.pose_rotation as Vector3) * Vector3.UP) * BLADE_LENGTH
	_pose_travel = tip - _pose_prev
	_pose_prev = tip
	combat._process(STEP)
	weapon._process(STEP)


# The weapon's own spring, read from the driver rather than inferred. Jitter
# cannot touch this number, which is why the claim below is split in two: this
# says the force was COMMITTED, the path departure says the blade actually went.
func contact_readout() -> Dictionary:
	return weapon.locomotion_readout() if weapon != null else {}


func _tip() -> Vector3:
	return weapon.position + (Basis.from_euler(weapon.rotation) * Vector3.UP) * BLADE_LENGTH


# The blade holding still, which is a different claim from the state being IDLE.
func _wait_until_still() -> void:
	for _i in 400:
		var before := _tip()
		await physics_frame
		await physics_frame
		if before.distance_to(_tip()) < 0.0008:
			return


func _wait_until_idle() -> void:
	for _i in 200:
		if combat.state == CombatController.State.IDLE:
			return
		await physics_frame


# -------------------------------------------------------------- B. swing moment

# §27: four moments, four answers. Firing the whoosh on `move_started` answers
# the INPUT; the blade it describes has not moved yet.
func _measure_swing_moment() -> void:
	await _wait_until_idle()
	_release_block()
	await _wait(1)
	_neutralise()
	_swing_signal_at = -1.0
	_audio_cue_at = -1.0
	# Cue ids REPEAT between swings, so watching the id would read the previous
	# swing's answer (or the one before it). The log counts plays, which is what
	# "the whoosh happened" actually means.
	audio.log_cues = true
	audio.cue_log.clear()
	_seen_log = 0
	combat.request(&"light")
	await physics_frame
	var move: SwordMove = combat.active_move
	if move == null:
		_fail("no move started, so the swing moment cannot be measured at all")
		return
	var startup := combat.effective_startup()
	metrics["move_startup"] = startup
	for _i in 120:
		await physics_frame
		if audio.cue_log.size() > _seen_log:
			_seen_log = audio.cue_log.size()
			if _audio_cue_at < 0.0:
				_audio_cue_at = combat.state_time
		if combat.state != CombatController.State.ATTACK and combat.state_time > 0.001:
			break
	metrics["swing_signal_at"] = _swing_signal_at
	metrics["swing_audio_at"] = _audio_cue_at

	_check(
		combat.has_signal("swing_started"),
		"the controller never reports the moment the blade leaves — every cue has to ride `move_started`, which is the INPUT, so audio and camera lead the swing they describe by the whole startup"
	)
	_check(
		_swing_signal_at >= 0.0 and absf(_swing_signal_at - startup) <= 0.03,
		"swing_started fired at %.3fs against a %.3fs blade departure — §27: the swing is its own moment, %.3fs away from the input that ordered it"
			% [_swing_signal_at, startup, startup]
	)
	_check(
		_audio_cue_at >= startup - 0.03,
		"the swing cue played at %.3fs while the blade leaves at %.3fs — the whoosh arrives %.0f frames before the sword it belongs to"
			% [_audio_cue_at, startup, maxf(startup - _audio_cue_at, 0.0) * TICK]
	)


# ---------------------------------------------------------- C. hitstop taxonomy

# Every value is read off the requested duration rather than off a stopwatch: a
# hitstop slows the tree, so measuring one by waiting inside it measures the
# measuring too. Read, record, reset — never let it run.
func _measure_hitstop_taxonomy() -> void:
	_spawn_target()
	await _wait(3)

	var light: float = await _start_and_inject(&"light", 2)
	var heavy: float = await _start_and_inject(&"heavy", 2)
	var block: float = await _block_and_strike(false)
	var perfect: float = await _block_and_strike(true)
	var shatter: float = await _measure_shatter()
	_remove_target()

	metrics["hitstop_light"] = light
	metrics["hitstop_heavy"] = heavy
	metrics["hitstop_guard"] = block
	metrics["hitstop_perfect"] = perfect
	metrics["hitstop_shatter"] = shatter

	_check(
		light > 0.0 and heavy > 0.0 and block > 0.0 and shatter > 0.0,
		"§28 wants four different answers and these are some of them missing — light=%.3f heavy=%.3f guard=%.3f shatter=%.3f"
			% [light, heavy, block, shatter]
	)
	_check(
		heavy > light * 1.4,
		"heavy lands at %.3fs and light at %.3fs — a cut twice as committed has to stop the world differently"
			% [heavy, light]
	)
	_check(
		block > 0.0 and block < light,
		"a blocked hit requests %.3fs — §28: absorbing is its own answer, shorter than landing one, never zero"
			% block
	)
	_check(
		shatter > heavy,
		"a body coming apart requests %.3fs against %.3fs for a heavy connect — shattering is the loudest thing the sword can do and must own its own silence"
			% [shatter, heavy]
	)


# Read, record, reset — the hitstop is never allowed to run, because the act of
# waiting inside it slows the waiting too.
func _hitstop_seconds(action: Callable) -> float:
	var effects = combat.time_effects
	if effects == null:
		_fail("no TimeEffectManager in reach, so no hitstop number here means anything")
		return 0.0
	effects.reset()
	action.call()
	var left: int = effects.effect_end_ms - Time.get_ticks_msec()
	effects.reset()
	return maxi(left, 0) / 1000.0


func _inject(built: Dictionary) -> void:
	combat._on_hitbox_landed(built)


# Measured through a REAL body, not through a flag on a box. Shatter is not a
# property of the hit, it is what happens when a frozen body takes a heavy one,
# so the only honest way to ask for it is to freeze something and hit it hard.
# The injection below only delivers the blow; everything about the outcome is
# decided by the same dummy the game fights.
func _measure_shatter() -> float:
	_remove_target()
	await _wait(2)
	var packed: PackedScene = load("res://scenes/enemies/TechnicalDummy.tscn")
	target = packed.instantiate()
	world.add_child(target)
	target.global_position = player.global_position - player.global_basis.z * 1.35
	await _wait(4)
	if not bool(target.apply_debug_state(&"frozen")):
		_fail("the dummy refused a frozen state, so shatter was never reachable and %.3f below would be a lie")
		return 0.0
	var asked: float = await _start_and_inject(&"heavy", 2)
	_remove_target()
	return asked


func _start_and_inject(kind: StringName, settle_frames: int) -> float:
	await _wait_until_idle()
	_release_block()
	await _wait(1)
	_neutralise()
	if kind == &"heavy":
		combat.request(&"heavy")
		await _wait(settle_frames)
		combat.release_heavy()
	else:
		combat.request(&"light")
	await _wait(settle_frames)
	var built := {
		"damage": if_kind(kind), "poise_damage": if_kind(kind), "impulse": 2.0,
		"element": &"physical", "target": target, "source": player,
	}
	return _hitstop_seconds(Callable(self, "_inject").bind(built))


func if_kind(kind: StringName) -> float:
	return 42.0 if kind == &"heavy" else 18.0


# The two guard answers: pressed-and-hit inside the perfect window, and
# pressed-and-hit after it. Both are the same body being hit; only the reading
# differs, which is the whole point of §28.
func _block_and_strike(perfect: bool) -> float:
	await _wait_until_idle()
	# Guard is HELD, not toggled: the controller leaves BLOCK on key RELEASE, so
	# a rig with no keyboard has to release it explicitly or the next case opens
	# with a guard that has already been up for three seconds — and three seconds
	# in is never a perfect anything.
	_release_block()
	await _wait(1)
	combat.request(&"block")
	await _wait(2)
	if not perfect:
		# Past the 0.12s window: still guarding, no longer perfect.
		await _wait(12)
	var window: float = combat.moveset.guard.perfect_guard_window
	# Read BEFORE the strike: a successful perfect guard leaves BLOCK for PARRY,
	# so sampling afterwards reports that the perfect case was never in the
	# window and quietly voids the very number it just took.
	var was_block := combat.state == CombatController.State.BLOCK
	var guard_time := combat.state_time
	var asked: float = 0.0
	if was_block:
		asked = _hitstop_seconds(Callable(self, "_strike_player").bind(
			{"damage": 20.0, "poise_damage": 30.0}
		))
	else:
		_fail("a %s never reached BLOCK state (state=%d), so the guard answer was never asked for"
			% ["perfect guard" if perfect else "block", combat.state])
	_release_block()
	await _wait(8)
	_check(
		perfect == (was_block and guard_time <= window + 0.001),
		"the %s case was sampled at %.3fs into the guard against a %.3fs window — this channel measured the wrong moment and its number means nothing either way"
			% ["perfect guard" if perfect else "late block", guard_time, window]
	)
	return asked


# The honest way out of BLOCK without a keyboard: whatever production does on
# release has to be reachable, so ask it rather than poking `state` directly and
# finding out nothing about the real transition.
func _release_block() -> void:
	if combat.state in [CombatController.State.BLOCK, CombatController.State.PARRY]:
		combat.finish_action()


func _strike_player(hit: Dictionary) -> void:
	combat._on_player_hit(hit)


# ----------------------------------------------------------------- D. the clock

# MEASURED IN SIMULATION SECONDS, not frames. This engine scales each tick's
# delta but keeps firing ticks sixty times a real second, so counting ticks
# during a time scale does not count game — it counts frames while the game
# crawls. `pose_time` is the controller's own scaled-delta integrator, which is
# the clock the rest of the combat NLP runs on, and it is the one being stolen
# from. The window is opened in the controller's units; what is measured is how
# much GAME the player actually got to spend inside it.
func _measure_window_under_hitstop() -> void:
	var clean := await _window_game_seconds(false)
	var frozen := await _window_game_seconds(true)
	metrics["window_game_clean"] = clean
	metrics["window_game_frozen"] = frozen
	var kept := frozen / maxf(clean, 0.0001)
	metrics["window_kept_ratio"] = kept
	# 0.90, not 1.00: the loop can only leave on a frame boundary, and a frame is
	# ~6% of a quarter second. Before this was fixed the number was 0.65, which no
	# amount of granularity explains.
	_check(
		kept >= 0.90 and clean >= WINDOW_SECONDS * 0.9,
		"a %.2fs window gave %.3fs of game clean and %.3fs after a %.2fs hitstop (%.0f%% left) — §28: a time stop is feedback, not rent taken out of the player's decision"
			% [WINDOW_SECONDS, clean, frozen, INTERRUPT_SECONDS, kept * 100.0]
	)


const WINDOW_SECONDS := 0.25
const INTERRUPT_SECONDS := 0.09


func _window_game_seconds(frozen: bool) -> float:
	await _wait_until_idle()
	combat.time_effects.reset()
	combat.pending_followup_id = &"uni_l2"
	combat.followup_until = combat._now() + WINDOW_SECONDS
	var started_at := combat.pose_time
	if frozen:
		combat.time_effects.request_hitstop(INTERRUPT_SECONDS)
	var frames := 0
	while frames < 400:
		await physics_frame
		frames += 1
		if not combat._followup_open(combat._now()):
			break
	combat.time_effects.reset()
	return combat.pose_time - started_at


# ------------------------------------------------------------------- reporting

func _check(condition: bool, reason: String) -> void:
	if condition:
		return
	failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)


func _report() -> void:
	print("")
	print("UNIVERSAL SWORD · SIX-CHANNEL READOUT")
	print("  A contact        after contact the two blades sit at most %.4fm apart (whiff-vs-whiff floor %.4fm, %.1f%% of travel)"
		% [
			metrics.get("tip_divergence_contact", 0.0), metrics.get("tip_divergence_air", 0.0),
			metrics.get("tip_travel_ratio", 0.0) * 100.0
		])
	print("                   connected cut %s frames, whiff %s frames"
		% [metrics.get("hit_move_frames", -1), metrics.get("miss_move_frames", -1)])
	print("                   blade travels %.3fm into a body vs %.3fm over air"
		% [metrics.get("tip_travel_into_body", 0.0), metrics.get("tip_travel_over_air", 0.0)])
	print("                   handspring commits %.4fm into a body, %.4fm into air"
		% [metrics.get("contact_deflection", 0.0), metrics.get("whiff_deflection", 0.0)])
	print("                   blade was covering %.4fm/frame at contact (one frame of tremor is %.4fm)"
		% [metrics.get("contact_travel", 0.0), TREMOR_STEP])
	print("                   shape floor measured between two whiffs: %.4fm"
		% metrics.get("tip_divergence_air", 0.0))
	print("                   second contact commits %.2f against the pose's travel (-1 = straight back along the spring)"
		% metrics.get("second_contact_agreement", -1.0))
	print("                   two contacts on one spring stack to %.4fm"
		% metrics.get("stacked_deflection", 0.0))
	print("  B swing moment   startup %.3fs · signal %.3fs · whoosh %.3fs"
		% [metrics.get("move_startup", -1.0), metrics.get("swing_signal_at", -1.0), metrics.get("swing_audio_at", -1.0)])
	print("  C hitstop        light %.3f · heavy %.3f · guard %.3f · perfect %.3f · shatter %.3f"
		% [
			metrics.get("hitstop_light", 0.0), metrics.get("hitstop_heavy", 0.0),
			metrics.get("hitstop_guard", 0.0), metrics.get("hitstop_perfect", 0.0),
			metrics.get("hitstop_shatter", 0.0)
		])
	print("  D window         %.3fs of game clean · %.3fs after a %.2fs stop (%.0f%% kept)"
		% [
			metrics.get("window_game_clean", 0.0), metrics.get("window_game_frozen", 0.0),
			INTERRUPT_SECONDS, metrics.get("window_kept_ratio", 0.0) * 100.0
		])
	print("")
