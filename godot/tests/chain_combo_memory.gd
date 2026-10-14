extends SceneTree
# 缚星链 · COMBO MEMORY (§6 of the CHAIN RESCUE brief).
#
# THE QUESTION: does the light sentence start at A1 exactly when it should, and
# continue exactly when it should? Three separate questions that the weapon used to
# answer with ONE number:
#
#   continue  a press soon after a cut ENDED          → the next beat of the sentence
#   forget    a press long after a cut ENDED          → A1
#   break     dodge / weapon switch / reset           → A1
#
# WHAT WAS ACTUALLY WRONG, MEASURED BEFORE ANY EDIT (`tools/probe_chain_combo.gd`).
#
# The only thing that reset the index was a `_idle_time` counter that advanced
# EXCLUSIVELY while the state was HELD and was zeroed at attack START. Both halves
# failed, in opposite directions:
#
#   · the clock ran from the cut's start and the retract on the end of every cut
#     (0.30s) was invisible to it, so a press 0.30s after a cut had SETTLED read as
#     ~0.95s and restarted at A1 — chaining by rhythm was impossible, you had to
#     press DURING the cut or lose the sentence;
#   · every frame in RETRACTING / TENSIONED / HOOKED was invisible too, so how long
#     the memory lasted was a function of which state the sentence ended in.
#
# So this file guards the replacement: ONE clock (`_cut_age`), counted in every
# state, measured from where a cut ENDED, compared against `combo_reset_timeout` —
# and a different number, `light_window`, for the separate question of how long a
# press is accepted at all (§7 says the two must not share a timer).
#
# WHY IT COUNTS FROM THE CUT'S END. The first version of the probe pressed, waited
# for the director to settle into HELD, then waited a gap — and reported "0.30s after
# settling → A1", which looked like a bug and was not: settling already spends the
# cut's retract plus the wait, so the real gap was ~0.95s and A1 was correct. A test
# that cannot say what it measured is worse than no test. This one finds the exact
# frame `active_move` goes null — the sentence's own `last_attack_end` — and counts
# from there.
#
# CLOCK: `chain.manual_step = true`, one tick per frame. Every expectation here is a
# frame count, so none of it may depend on a shared machine's frame rate.

const DT := 1.0 / 60.0
# Far from the lab's furniture: a throw must reach the chain's limit in open air so
# the states that follow A3 are the designed ones and not a wall.
const OPEN_STAND := Vector3(0.0, 1.0, -22.0)
# Inside the memory, so the press must CONTINUE the sentence…
const GAP_CONTINUE := 0.30
# …and comfortably outside it, so the press must FORGET.
const GAP_FORGET := 1.20

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var chain: ChainDirector
var weapon: WeaponSlot
var played: Array[StringName] = []
var failures: Array[String] = []
var metrics: Dictionary = {}


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
	chain.manual_step = true
	chain.move_started.connect(func(m: ChainMove) -> void: played.append(m.id))
	weapon.equip(WeaponSlot.CHAIN)
	await _wait(4)

	# §7 — the two windows must be DIFFERENT numbers. If someone ever "simplifies"
	# this back to one, this is the assertion that says why not.
	_check(
		not is_equal_approx(chain.moveset.light_window, chain.moveset.combo_reset_timeout),
		"the input window (%.2fs) and the combo memory (%.2fs) are the same number — §7 is explicit that they are two different questions and must not share a timer"
			% [chain.moveset.light_window, chain.moveset.combo_reset_timeout]
	)
	_check(
		chain.moveset.combo_reset_timeout >= 0.70 and chain.moveset.combo_reset_timeout <= 1.00,
		"the combo memory is %.2fs, outside the 0.70–1.00s the brief asks for" % chain.moveset.combo_reset_timeout
	)

	await _check_continues()
	await _check_forgets()
	await _check_sentence()
	await _check_breaks()
	_finish()


# A press inside the window continues the sentence. This is the half that was
# BROKEN before the fix — the case that made chaining by rhythm impossible.
func _check_continues() -> void:
	var got := await _press_gap_press(GAP_CONTINUE)
	metrics["continue_0.30s"] = String(got)
	_check(
		got == &"ch_return",
		"a press %.2fs after a cut ended played %s — inside a %.2fs memory it must be the NEXT BEAT, or the weapon cannot be chained by rhythm at all"
			% [GAP_CONTINUE, String(got), chain.moveset.combo_reset_timeout]
	)


# A press outside it forgets. This is the behaviour the brief asks for by name
# ("隔很久按是否正确回 A1").
func _check_forgets() -> void:
	var got := await _press_gap_press(GAP_FORGET)
	metrics["forget_1.20s"] = String(got)
	_check(
		got == &"ch_sweep",
		"a press %.2fs after a cut ended played %s — past the %.2fs memory the sentence is over and the next press has to be A1"
			% [GAP_FORGET, String(got), chain.moveset.combo_reset_timeout]
	)


# The whole sentence, mashed the way it is actually played.
func _check_sentence() -> void:
	await _stand_reset()
	chain.request(&"light")
	var guard := 0
	while guard < 900 and played.size() < 3:
		guard += 1
		await _tick(1)
		if played.size() < 3 and chain._can_act() and chain.state in [
			ChainDirector.State.SWINGING, ChainDirector.State.EXTENDING,
			ChainDirector.State.SLAMMING,
		]:
			chain.request(&"light")
	var got := played.slice(0, 3)
	metrics["sentence"] = str(got)
	_check(
		got == [&"ch_sweep", &"ch_return", &"ch_throw"],
		"a mashed light chain played %s — A1/A2/A3 is the sentence and the loss of any beat means the handover is eating the next press" % str(got)
	)


# §6's interrupting inputs, each tested while the memory is still FRESH — so what
# breaks the sentence below is the breaker and not the clock running out.
func _check_breaks() -> void:
	# A dodge is announced by the controller; the chain listens (§6).
	await _check_break("dodge", func() -> void: combat.dodge_evaded.emit())
	# …and so is a stagger.
	await _check_break("stagger", func() -> void:
		combat.state_changed.emit(CombatController.State.ATTACK, CombatController.State.STAGGER))
	# A weapon switch and a scene reset both run through `reset()`.
	await _check_break("weapon switch", func() -> void:
		weapon.equip(WeaponSlot.SWORD)
		weapon.equip(WeaponSlot.CHAIN))
	await _check_break("reset()", func() -> void: chain.reset())


func _check_break(title: String, breaker: Callable) -> void:
	await _stand_reset()
	# One cut deep, so there is a sentence to break — and SETTLE first, because a
	# press during RETRACTING is refused by `_can_act()` and a refused press would
	# read as "the breaker failed" when it only proved the chain was still reeling.
	chain.request(&"light")
	await _to_cut_end(600)
	await _settle_to_held(300)
	var age_before: float = chain.get("_cut_age")
	breaker.call()
	await _tick(2)
	played.clear()
	chain.request(&"light")
	await _tick(2)
	var got := _first_played()
	metrics["break_" + title] = String(got)
	_check(
		got == &"ch_sweep",
		"a %s at %.2fs into a %.2fs memory left the sentence at %s — §6 lists it among the inputs that end one"
			% [title, age_before, chain.moveset.combo_reset_timeout, String(got)]
	)


# Press, run to the exact frame the cut ends, wait `gap`, press again.
func _press_gap_press(gap: float) -> StringName:
	await _stand_reset()
	chain.request(&"light")
	await _to_cut_end(600)
	await _tick(int(round(gap / DT)))
	played.clear()
	chain.request(&"light")
	await _tick(2)
	return _first_played()


func _first_played() -> StringName:
	return played[-1] if played.size() > 0 else &"<none>"


func _to_cut_end(max_frames: int) -> void:
	var guard := 0
	while guard < max_frames:
		guard += 1
		if chain.active_move == null:
			return
		await _tick(1)


func _settle_to_held(max_frames: int) -> void:
	var guard := 0
	while guard < max_frames:
		guard += 1
		if chain.state == ChainDirector.State.HELD:
			return
		await _tick(1)


func _stand_reset() -> void:
	player.global_position = OPEN_STAND
	var look := player.get_node_or_null("CameraRig/LookPivot") as Node3D
	if look != null:
		look.rotation = Vector3(0.0, 0.0, 0.0)
	chain.reset()
	played.clear()
	await _tick(2)


func _tick(n: int) -> void:
	for _i in n:
		chain.step(DT)
		await process_frame


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	print("\n")
	for key in metrics:
		print("  %-22s %s" % [key, str(metrics[key])])
	print("\n")
	if failures.is_empty():
		print("PASS: the light sentence is remembered for as long as it should be, forgotten when it should be, and every interrupting input starts it over at A1")
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for f in failures:
			print("  · %s" % f)
	print("\n")
	quit(0 if failures.is_empty() else 1)
