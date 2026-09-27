extends SceneTree
# The combat clock, and why it is not the wall.
#
# Every window in combat — combo, follow-up, riposte, bind, slip, sheath waiver,
# skill cooldown — is a timestamp compared against `_now()`. That one function is
# therefore load-bearing in a way almost nothing else in the controller is, and
# it has been wrong in two opposite directions, neither of which was visible
# from any of the code that USED it:
#
#   1. WALL CLOCK. A hitstop slows the world but not the wall, so a 0.25s
#      follow-up window spent a tenth of a second of itself completely frozen
#      and the player was handed two thirds of the decision they had bargained
#      for. The stop stopped being feedback and started being rent.
#
#   2. SIMULATION TIME STARTING AT ZERO. Every window timestamp is initialised
#      to 0.0 and never set until it is opened. Compared with `now <= until`,
#      at t=0 that reads 0 <= 0, which is TRUE — so a fresh game opened with its
#      riposte window and its sheath waiver already live, and the player's first
#      attack of the run came out as a COUNTER. The wall clock had been hiding
#      this for free, by starting at whatever second the engine happened to be
#      on, which is the only reason the bug waited for the fix to appear.
#
# Both are asserted here, because both are the kind of thing that only shows up
# as "the sword feels wrong" three weeks later.

var world: Node3D
var player: CharacterBody3D
var lane: MovementLane
var combat: CombatController
var failures: Array[String] = []


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
	# Collaborators BEFORE the player: @onready resolves on entry, so anything
	# added after it is invisible to it and every effect requested below would
	# silently be a request into nothing.
	var screen := CombatScreenFX.new()
	screen.name = "CombatScreenFX"
	world.add_child(screen)
	var clock := TimeEffectManager.new()
	clock.name = "TimeEffectManager"
	world.add_child(clock)
	var packed: PackedScene = load("res://scenes/player/Player.tscn")
	player = packed.instantiate()
	world.add_child(player)
	player.global_position = lane.start_position()
	combat = player.get_node("CombatController")
	player.unlimited_resources = true

	# BOTH OF THESE RUN BEFORE A SINGLE FRAME, AND THAT IS THE POINT.
	#
	# The bug they exist for only exists at t=0: every window timestamp starts
	# at 0.0 and `_now()` starts at 0.0, so `now <= until` answers "open" for a
	# window that has never been opened. One frame later the clock reads 0.016
	# and the whole class of bug disappears — meaning a rig that settles before
	# it measures, the way every other test in this project does, reports the
	# broken build as healthy. The ambiguous instant has to be asked for
	# directly, and asking for it means asking before the clock moves.
	_measure_windows_at_zero()
	await _measure_first_attack()

	await _wait(20)
	await _measure_frozen_clock()

	_report()


# ------------------------------------------- 1. nothing is open before it opens

# The 0.0-ambiguity. Every one of these fields is 0.0 until something sets it,
# and `_now()` is 0.0 too, so a `<=` comparison answers "open" for a window that
# has never existed. What makes this more than a tidiness complaint is that one
# of them — the riposte — changes which MOVE comes out when the player presses
# attack, so the very first swing of a fresh run was a counter-attack.
func _measure_windows_at_zero() -> void:
	# ASKED AT `now == 0.0`, not at whatever the clock happens to read. A rig
	# that measures "now" instead of "zero" is measuring a clock that has
	# already moved past the only instant where this can go wrong, and the
	# mutation sweep proved it: reverting the fix to `<=` left this test green
	# because by then the clock was at 1.2s and `1.2 <= 0` is false for free.
	var now := 0.0
	_check(
		not combat._riposte_open(now),
		"the riposte window is open at t=0 on a controller that has never parried anything — a timestamp of 0.0 is a window that was never opened, and reading it as open hands the player a counter they did not earn"
	)
	# BOTH OF THESE ARE GUARDED BY A SECOND CONDITION, and a guarded assertion
	# that is never actually reachable is decoration — the sweep proved it, by
	# reverting each fix and watching the test stay green. So the guard is
	# SATISFIED here rather than hoped about: `_bind_open` also wants the PARRY
	# state and a style that has a bind at all (universal does not — 白蔷庭
	# does), and `_followup_open` also wants a move waiting in the slot. Asking
	# with the guard left unsatisfied would test nothing that can fail.
	var saved_style := combat.style_id
	var saved_state := combat.state
	var saved_followup := combat.pending_followup_id
	combat.set_style(&"white_rose", true)
	combat.state = CombatController.State.PARRY
	_check(
		not combat._bind_open(now),
		"the bind window is open at t=0 on a controller that has never trapped a blade — see the riposte window: 0.0 means \"never\", not \"now\""
	)
	combat.state = saved_state
	combat.set_style(saved_style, true)
	combat.pending_followup_id = &"uni_l2"
	_check(
		not combat._followup_open(now),
		"the follow-up window is open at t=0 before any move has opened it — a fresh controller had %s waiting in the slot with no window ever set"
			% combat.pending_followup_id
	)
	combat.pending_followup_id = saved_followup
	_check(
		not combat._slip_open(),
		"折柳 is open at t=0 before it has ever been triggered"
	)
	# The sheath waiver is NOT asserted here, and the reason is worth writing
	# down: it is only ever read inside `_process`, and `_process` advances the
	# clock on its very first line, so by the time anything asks, `_now()` is
	# already 0.0167 and `0.0167 <= 0.0` is false for free. It cannot be reached
	# at t=0 no matter how the comparison is written. The riposte window can be,
	# because `request()` is an INPUT and an input can arrive before the first
	# frame ever runs — which is exactly how this bug reached the player. An
	# assertion that cannot fail is not an assertion, so there is none here.


# ---------------------------------------------------- 2. the first attack of a run

# The same bug read from the player's side instead of the field's: this is what
# it actually did to the game.
func _measure_first_attack() -> void:
	var at := combat._now()
	combat.request(&"light")
	await physics_frame
	var move: SwordMove = combat.active_move
	# If the clock has already moved, this test is not testing anything: the
	# whole defect lives in the first tick, and a rig that arrives late has to
	# say so rather than report a healthy build.
	_check(
		at <= 0.02,
		"the first attack was requested at %.3fs, not at t=0 — this test only means anything if it arrives before the clock moves, and it arrived %d frames late"
			% [at, int(at * 60.0)]
	)
	_check(
		move != null and move.id != &"uni_riposte",
		"the first attack of a fresh game came out as %s — the riposte window was live before anyone parried, so the player's opening swing is a move that belongs to a moment that has not happened"
			% (move.id if move != null else &"nothing")
	)
	await _wait(40)


# ------------------------------------------------------- 3. the clock is the game

# Not the wall. A freeze must stop the combat clock too, or every window is
# being paid for in a currency the player cannot spend.
func _measure_frozen_clock() -> void:
	combat.time_effects.reset()
	await _wait(2)
	var before := combat._now()
	var wall_before := Time.get_ticks_msec()
	# Long enough to cover the whole measurement, deliberately: a real hitstop is
	# 0.03-0.11s but a stopwatch that runs off the end of one measures partly
	# frozen time and partly running time and reports the average of the two,
	# which is exactly the number that made this look like it was working.
	combat.time_effects.request_hitstop(1.0)
	var frozen_frames := 0
	while frozen_frames < 20:
		await physics_frame
		frozen_frames += 1
	var spent := combat._now() - before
	var wall_spent := (Time.get_ticks_msec() - wall_before) / 1000.0
	combat.time_effects.reset()
	_check(
		spent < wall_spent * 0.35,
		"the combat clock spent %.3fs of game across %.3fs of wall with the world frozen (%.0f%%) — a hitstop has to stop the clock the windows are measured in, or it is taking them out of the player's pocket"
			% [spent, wall_spent, spent / maxf(wall_spent, 0.0001) * 100.0]
	)
	# And it must not have stopped dead either: a clock that never advances is
	# just as broken as one that ignores the freeze, and it would look identical
	# from inside a window.
	await _wait(10)
	var after := combat._now()
	_check(
		after > before,
		"the combat clock is still at %.3fs after the freeze was lifted and %d frames ran — a clock that stops for a hitstop and never restarts is the same bug wearing a different hat"
			% [after, 10]
	)
	# pose_time drives the weapon's own animation and combat_time drives every
	# window. They are two integrators over the same scaled delta, and if they
	# ever drift apart then the blade and the rules that judge it are living in
	# different games.
	_check(
		absf(combat.pose_time - combat.combat_time) < 0.05,
		"the blade's clock (%.3fs) and the rules' clock (%.3fs) have drifted apart — both integrate the same scaled delta for the same node, so a gap here means one of them stopped being simulation time"
			% [combat.pose_time, combat.combat_time]
	)


# ------------------------------------------------------------------- reporting

func _check(condition: bool, reason: String) -> void:
	if condition:
		return
	failures.append(reason)


func _report() -> void:
	print("")
	print("COMBAT CLOCK")
	print("  t=0           riposte=%s bind=%s followup=%s slip=%s"
		% [
			combat._riposte_open(combat._now()), combat._bind_open(combat._now()),
			combat._followup_open(combat._now()), combat._slip_open()
		])
	print("  clocks        combat %.3fs · pose %.3fs"
		% [combat._now(), combat.pose_time])
	print("")
	if failures.is_empty():
		print("PASS: every combat window is measured in game time and none of them is open before it is opened")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
