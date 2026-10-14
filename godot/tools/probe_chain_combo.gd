extends SceneTree
# 缚星链 · COMBO MEMORY PROBE — §6 of the CHAIN RESCUE brief.
#
# THE QUESTION: does the light sentence start at A1 exactly when it should, and
# continue exactly when it should? Two separate numbers, two separate questions:
#
#   continue  a press soon after a cut ENDED            → the next beat
#   forget    a press long after a cut ENDED            → A1
#   break     dodge / stagger / weapon switch / reset   → A1
#
# WHY IT MEASURES FROM THE CUT'S END AND NOT FROM A SETTLE POINT.
#
# The first version of this probe pressed, waited for the director to settle into
# HELD, then waited a gap — and reported "0.30s after settling → A1", which looked
# like a bug and was not one: settling into HELD already spends the cut's retract
# (0.30s) plus whatever the wait condition cost, so the real gap was ~0.95s and
# starting at A1 was correct. A probe that cannot say what it measured is worse
# than no probe. This one finds the exact frame `active_move` goes null — the
# sentence's own `last_attack_end` — and counts the gap from there.
#
# CLOCK: `chain.manual_step = true`, one tick per frame. Every number here is a
# frame count, so it must not depend on a shared machine's frame rate.

const DT := 1.0 / 60.0
# Far from the lab's furniture: a throw must reach the chain's limit in open air so
# the states that follow A3 are the designed ones and not a wall.
const OPEN_STAND := Vector3(0.0, 1.0, -22.0)

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var chain: ChainDirector
var weapon: WeaponSlot
var played: Array[StringName] = []
var failures: Array[String] = []


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

	print("\n================ §6 COMBO MEMORY PROBE ================")
	print("light_window = %.2f s   combo_reset_timeout = %.2f s   loop = %s" % [
		chain.moveset.light_window,
		chain.moveset.combo_reset_timeout,
		str(chain.moveset.light_chain),
	])

	# The gap sweep. Three of these must CONTINUE and two must FORGET.
	await _gap_case(0.30, &"ch_return", "continue: a press 0.30s after the cut ended")
	await _gap_case(0.60, &"ch_return", "continue: a press 0.60s after the cut ended")
	await _gap_case(1.20, &"ch_sweep", "forget:    a press 1.20s after the cut ended")
	await _gap_case(5.00, &"ch_sweep", "forget:    a press 5.00s after the cut ended")
	# Mashed is how the sentence is actually played.
	await _sentence_case()
	# The three external breakers §6 names.
	await _break_case("dodge", func() -> void: combat.dodge_evaded.emit())
	await _break_case("weapon switch", func() -> void:
		weapon.equip(WeaponSlot.SWORD)
		weapon.equip(WeaponSlot.CHAIN))
	await _break_case("reset()", func() -> void: chain.reset())

	print("\n======================================================")
	if failures.is_empty():
		print("PASS: the sentence continues while it is fresh, forgets when it is stale,")
		print("      and every interrupting input starts it over at A1")
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for f in failures:
			print("  · %s" % f)
	print("======================================================\n")
	quit(0 if failures.is_empty() else 1)


# Press, run to the exact frame the cut ends, wait `gap`, press again.
func _gap_case(gap: float, expect: StringName, title: String) -> void:
	await _stand_reset()
	chain.request(&"light")
	var first := _first_played()
	await _to_cut_end(600)
	await _tick(int(round(gap / DT)))
	played.clear()
	chain.request(&"light")
	await _tick(2)
	var second := _first_played()
	var ok := second == expect
	print("\n### %s" % title)
	print("    cut 1 = %s   gap = %.2fs   cut 2 = %s   (want %s)  %s" % [
		String(first), gap, String(second), String(expect), "OK" if ok else "WRONG"])
	if not ok:
		failures.append("%s: got %s, want %s" % [title, String(second), String(expect)])


func _sentence_case() -> void:
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
	var ok := got == [&"ch_sweep", &"ch_return", &"ch_throw"]
	print("\n### mashed sentence (A1 → A2 → A3)")
	print("    played = %s   %s" % [str(got), "OK" if ok else "WRONG"])
	if not ok:
		failures.append("mashed sentence played %s" % str(got))


func _break_case(title: String, breaker: Callable) -> void:
	await _stand_reset()
	# Get one cut deep, so there is a sentence to forget — and SETTLE, because a
	# press during RETRACTING is refused outright by `_can_act()` and a refused press
	# would read as "the breaker failed" when it only proved the chain was reeling.
	chain.request(&"light")
	await _to_cut_end(600)
	await _settle_to_held(300)
	# Still well inside `combo_reset_timeout`, so what breaks it below is the breaker
	# and not the clock running out.
	var age_before: float = chain.get("_cut_age")
	breaker.call()
	await _tick(2)
	played.clear()
	chain.request(&"light")
	await _tick(2)
	var got := _first_played()
	var ok := got == &"ch_sweep"
	print("\n### break: %s" % title)
	print("    age at break = %.2fs (timeout %.2f)   next press = %s   (want ch_sweep)  %s" % [
		age_before, chain.moveset.combo_reset_timeout, String(got), "OK" if ok else "WRONG"])
	if not ok:
		failures.append("%s did not break the sentence (got %s)" % [title, String(got)])


func _settle_to_held(max_frames: int) -> void:
	var guard := 0
	while guard < max_frames:
		guard += 1
		if chain.state == ChainDirector.State.HELD:
			return
		await _tick(1)


func _first_played() -> StringName:
	return played[-1] if played.size() > 0 else &"<none>"


func _to_cut_end(max_frames: int) -> void:
	var guard := 0
	while guard < max_frames:
		guard += 1
		if chain.active_move == null:
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
