extends SceneTree
# SWORD BASIC ATTACK V2 — THE ACCEPTANCE GATE (§32).
#
# ===========================================================================
# WHAT THIS FILE IS FOR
# ===========================================================================
#
# The four beats of the new basic sentence are told apart by DISTANCE, RHYTHM,
# THE SAYA and SPACE — explicitly not by damage numbers. That makes them easy to
# author and hard to verify, because every failure mode available is one where
# the animation looks right and the mechanic does not exist:
#
#   * A2's "mid" range quietly becomes a bigger melee box.
#   * A3's three cuts are drawn but only one of them is ever resolved.
#   * A4's 270-degree sweep is a full circle, or a shockwave, and reads the same
#     in a still frame.
#   * pressing `1` puts a sword in the hand without a scabbard ever existing.
#   * stopping for a second still continues the chain, so the fifth press is not
#     a first press.
#
# None of those is visible in a screenshot and all of them are decidable by
# measurement. So this file measures. It runs EVERY scenario §32 names, against
# a real arena, a real moveset and real bodies, and it prints the numbers it got
# rather than only the verdict — a check that says PASS without saying WHAT it
# measured is a check nobody can debug on the day it starts failing.
#
# ===========================================================================
# THE ONE THING IT DOES NOT DO
# ===========================================================================
#
# It does not judge feel. §38's nine questions are the ones a human answers after
# watching the movie; this file answers "is the mechanic there", which is the
# half that has to be true first.

const ZONE := preload("res://scripts/training/sword_combo_zone.gd")
const MANAGER := preload("res://scripts/combat/weapon_manager.gd")

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var reach: SwordReach
var saya: SwordSayaRig
var weapon: WeaponSlot
var manager: Node
var zone: Node3D
var failures: Array[String] = []

# --- per-scenario record -------------------------------------------------
## Every landing, in order: `{move, target, mode}`.
var _cuts: Array[Dictionary] = []
## Which trace marks resolved, in order, with the angle each was authored at.
var _marks: Array[Dictionary] = []
## Which trace marks actually cut something.
var _marks_with_hits: Array[int] = []
## How many waves were launched this scenario.
var _waves := 0
## Once a target is cut it stays cut for the scenario, because §29 normalises the
## three cuts to one hit and a body already cut must not be counted twice.
var _cut_ids: Dictionary = {}
# --- whole-run record ----------------------------------------------------
var _combo_moves: Array[StringName] = []


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
	manager = player.get_node("WeaponManager")
	reach = combat.reach
	saya = combat.saya_rig
	if reach == null or saya == null:
		_fail("the controller never built its reach or its saya rig, so nothing below can be measured")
		_finish()
		return

	combat.hit_landed.connect(_on_hit)
	reach.wave_born.connect(func(_n: Node3D, _m: SwordMove) -> void: _waves += 1)
	reach.trace_resolved.connect(_on_trace)

	zone = ZONE.new()
	zone.name = "SwordComboZone"
	world.add_child(zone)
	zone.build(player)

	seal_clear()
	await _scenario_equip()
	await _scenario_a1_only()
	await _scenario_a1_a2()
	await _scenario_a1_a2_a3()
	await _scenario_full_combo()
	await _scenario_reset_after_one()
	await _scenario_reset_after_two()
	await _scenario_weapon_round_trip()

	_finish()


# ===========================================================================
#  §32 · 1 — EQUIP SWORD IS A DRAW, NOT A HAND-OFF (§3 / §19 / §20)
# ===========================================================================

func _scenario_equip() -> void:
	var started: bool = manager.call("equip_weapon", &"chain")
	_check(bool(started), "the switch to the chain was refused, so the draw cannot be measured")
	await _settle_switch()
	_check(weapon.is_chain(), "the chain never arrived")

	seal_clear()
	manager.call("equip_weapon", &"sword")
	_check(weapon.is_sword(), "§19: pressing 1 did not take the sword")
	# THE BLADE IS IN THE SAYA, and that is a distance rather than a claim about
	# the picture. Measured on the frame of the press and against the SAYA'S OWN
	# MOUTH, because `equip_blend` is about to start climbing: three frames later
	# the blade has legitimately begun to leave, and a check that ran then would
	# be measuring the draw rather than the seating.
	var snap := combat.pose_snapshot()
	var seated := (snap["position"] as Vector3).distance_to(SwordBasic.SAYA_MOUTH)
	_check(
		seated < 0.001,
		"§20: on the frame of the draw the blade was %.4fm from its own saya mouth, "
			% seated
		+ "so the sword appeared rather than being taken out of something"
	)
	# ...and the rig agrees, to within the mouth's own length: `seat_error` walks
	# the blade's origin out along its axis by the tsuba-to-mouth distance, so
	# zero means the two systems put the same point in the same place.
	_check(
		saya.seat_error(snap["position"], snap["rotation"]) < 0.001,
		"§20: the saya rig disagreed with the sword about where the mouth is (%.4fm)"
			% saya.seat_error(snap["position"], snap["rotation"])
	)

	# ...AND IT IS NOT USABLE YET. A sword that can cut while it is still in the
	# scabbard is a sword that was never in the scabbard.
	var refused := not combat.request(&"light")
	_check(
		refused and combat.state == CombatController.State.IDLE,
		"§3: the blade swung while it was still coming out of the saya"
	)

	# ...AND THE DRAW TAKES THE TIME IT SAYS IT DOES, measured rather than read
	# off the constant: a constant in range with nothing animating is a number, a
	# constant in range with a blend climbing behind it is a draw.
	var frames := 0
	var saw_middle := false
	while float(combat.equip_blend) < 0.999 and frames < 240:
		await physics_frame
		frames += 1
		var blend := float(combat.equip_blend)
		if blend > 0.08 and blend < 0.92:
			saw_middle = true
	_check(saw_middle, "§19: the blade went from home to hand without a draw to watch")
	var drawn_seconds := float(frames) / 60.0
	_check(
		drawn_seconds >= MANAGER.DRAW_SECONDS * 0.6 and drawn_seconds <= MANAGER.DRAW_SECONDS * 1.8,
		"§3: the draw took %.2fs against an authored %.2fs"
			% [drawn_seconds, MANAGER.DRAW_SECONDS]
	)
	# The saya is still there — which is the whole of §2's "the sheath does not
	# disappear" — and it is in the hand rather than at the hip.
	_check(
		float(saya.presence) > 0.9,
		"§2: the saya did not come up with the sword (presence %.2f)" % float(saya.presence)
	)
	var after := combat.pose_snapshot()
	_check(
		saya.seat_error(after["position"], after["rotation"]) > 0.05,
		"§19: the saya is still sitting at the sword's mouth after the draw, so it "
		+ "never left the scabbard position"
	)
	_ok("§32-1  Equip = a draw (%.2fs, saya seats the blade at %.4fm then follows)" % [drawn_seconds, seated])
	await _settle_idle()


# ===========================================================================
#  §32 · 2 — A1 ONLY: BODY RANGE, NOTHING ELSE (§4 / §15)
# ===========================================================================

func _scenario_a1_only() -> void:
	await _arm_scenario()
	combat.request(&"light")
	await _settle_idle()

	_check(seal(&"near"), "A1 did not cut the body standing at arm's length")
	for id in [&"mid", &"far", &"off_axis", &"behind"]:
		_check(not seal(id), "A1 reached %s, so it is not a close-range cut" % String(id))
	for i in 4:
		_check(
			not seal(StringName("surround_%d" % i)),
			"A1 swept a surrounding target, so the first beat already has area"
		)
	_check(_waves == 0, "A1 launched a sword wave; §15 gives the wave to A2 and nobody else")
	_check(_marks.is_empty(), "A1 resolved a space cut; §15 gives those to A3")
	_check(
		int(combat.get("_arc_slice")) == 0,
		"A1 resolved an arc slice; §15 gives the sweep to A4"
	)
	_check(_mode_of(&"near") == &"body", "A1's landing was not delivered by the body hitbox")
	_ok("§32-2  A1 only — one body cut, no wave, no trace, no arc (%s)" % _summary())


# ===========================================================================
#  §32 · 3 + 9 — A1 → A2: THE WAVE, AT MID RANGE (§5 / §15)
# ===========================================================================

func _scenario_a1_a2() -> void:
	await _arm_scenario()
	await _run_chain(2)

	_check(seal(&"mid"), "A2's wave did not reach a body at %.1fm" % _distance(&"mid"))
	_check(not seal(&"far"), "A2 reached %.1fm, so it is a map-wide attack" % _distance(&"far"))
	_check(not seal(&"off_axis"), "A2's wave caught the 60-degree target, so it is not aimed")
	_check(not seal(&"behind"), "A2's wave caught a body behind the player")
	_check(_waves >= 1, "§5: A2 did not launch a travelling cut")
	_check(_marks.is_empty(), "§15: A2 resolved a space cut, which belongs to A3")
	_check(
		_mode_of(&"mid") == &"wave",
		"§5: the mid landing was not delivered by the wave (got %s)" % String(_mode_of(&"mid"))
	)
	_check(
		_mode_of(&"near") == &"body" or _mode_of(&"near") == &"wave",
		"§5: A2's close landing came from neither the blade nor the wave"
	)
	# ...AND ONCE. A2 is the only beat with two mechanisms that overlap in space,
	# so it is the only one that can cut the same body twice — and the symptom is
	# invisible in a still frame and looks like "the second beat hits hard".
	var close_a2 := 0
	for cut in _cuts:
		if cut["move"] == SwordBasic.A2 and cut["target"] == &"near":
			close_a2 += 1
	_check(
		close_a2 <= 1,
		"§5: A2 cut the close body %d times — the blade and the wave it launched both "
			% close_a2
		+ "landed, so standing in an enemy's face doubles the second beat"
	)
	_ok("§32-3  A1→A2 — the wave arrives at %.1fm and stops before %.1fm (%s)"
		% [_distance(&"mid"), _distance(&"far"), _summary()])


# ===========================================================================
#  §32 · 4 + 10 — A1 → A2 → A3: THREE SPACE CUTS, LONG RANGE (§9 / §10)
# ===========================================================================

func _scenario_a1_a2_a3() -> void:
	await _arm_scenario()
	await _run_chain(3)
	_check(not seal(&"far"),"A3 retained remote damage after the body uppercut change")
	_check(not seal(&"off_axis"),"A3 uppercut reached the distant off-axis target")
	_check(not seal(&"behind"),"A3 uppercut reached behind the body")
	_check(_marks.is_empty(),"A3 uppercut retained legacy spatial trace dispatch")
	var rising := 0
	for cut in _cuts:
		if cut["move"] == SwordBasic.A3:
			rising += 1
			_check(cut["mode"] == &"body","A3 must use live close body contact")
	_check(rising>0,"The new A3 uppercut must actually contact the near target")
	_ok("Feel V2 A1-A3: rising body contacts=%d, remote targets survived" % rising)


# ===========================================================================
#  §32 · 5 + 11 — FULL COMBO: THE SENTENCE, AND A4'S SURROUND (§11 / §30)
# ===========================================================================

func _scenario_full_combo() -> void:
	await _arm_scenario()
	await _run_chain(4)

	# Every beat landed on something, and the four of them are four different
	# moves in the authored order.
	var seen: Array[StringName] = []
	for cut in _cuts:
		var id: StringName = cut["move"]
		if not seen.has(id):
			seen.append(id)
	var expected := combat.moveset.light_chain
	_check(
		seen == expected,
		"§37: the combo was %s instead of the four beats %s" % [str(seen), str(expected)]
	)

	var swept := 0
	var missed := PackedStringArray()
	for i in 4:
		var id := StringName("surround_%d" % i)
		if seal(id):
			swept += 1
		else:
			missed.append(String(id))
	_check(
		swept == 4,
		"§30: A4 caught %d of 4 surrounding targets (%s survived), so the 優弧 is "
			% [swept, ", ".join(missed) if not missed.is_empty() else "none"]
		+ "narrower than authored"
	)
	_check(
		_mode_of(&"surround_0") == &"arc",
		"§15: A4's sweep was not delivered by the arc (got %s)" % String(_mode_of(&"surround_0"))
	)
	_check(
		not seal(&"behind"),
		"§11: A4 cut a body behind it, so the 270-degree 優弧 is a full circle"
	)
	for id in [&"mid", &"far", &"off_axis"]:
		_check(
			_mode_of(id) != &"arc",
			"§15: A4's sweep cut %s at %.1fm, outside its own %.1fm radius"
				% [String(id), _distance(id), SwordBasic.a4().reach_radius]
		)
	_ok("§36  The sentence played in order: %s"
		% str(_combo_moves.map(func(m: StringName) -> String: return String(m))))
	# §29: the three cuts are ONE hit, not three heavy ones. Counted per BODY,
	# because "normalised" is a claim about what a single body receives — a
	# scenario-wide sum would fail simply because A3 cut two things.
	var per_body: Dictionary = {}
	for cut in _cuts:
		if cut["move"] != SwordBasic.A3:
			continue
		var key: StringName = cut["target"]
		per_body[key] = float(per_body.get(key, 0.0)) + float(cut["damage"])
	var a3_move := SwordBasic.a3()
	var worst := 0.0
	for key in per_body:
		worst = maxf(worst, float(per_body[key]))
	_check(
		per_body.is_empty() or worst <= a3_move.damage * 1.05,
		"§29: A3's three cuts delivered %.1f to one body against one cut's %.1f, so the "
			% [worst, a3_move.damage]
		+ "three scars are three heavy attacks wearing one move's name"
	)
	_ok("§32-5  Full A1→A2→A3→A4 — %s, distance grammar held"
		% str(seen.map(func(m: StringName) -> String: return String(m))))
	_ok("§32-11 A4 multi-target — %d/4 surrounding cut, the body behind survived" % swept)


# ===========================================================================
#  §32 · 6 + 7 — COMBO RESET (§17)
# ===========================================================================

func _scenario_reset_after_one() -> void:
	await _arm_scenario()
	combat.request(&"light")
	await physics_frame
	var first := combat.active_move_id
	await _settle_idle()
	await _pause_longer_than_the_window()
	combat.request(&"light")
	await physics_frame
	_check(
		combat.active_move_id == combat.moveset.light_chain[0],
		"§17: after one cut and a pause the next cut was %s, not A1"
			% String(combat.active_move_id)
	)
	_check(combat.combo_index == 1, "§17: the counter read %d after a reset" % combat.combo_index)
	_ok("§32-6  A1 → wait → A1 (first cut was %s)" % String(first))
	await _settle_idle()


func _scenario_reset_after_two() -> void:
	await _arm_scenario()
	await _run_chain(2)
	await _pause_longer_than_the_window()
	combat.request(&"light")
	await physics_frame
	_check(
		combat.active_move_id == combat.moveset.light_chain[0],
		"§17: after two cuts and a pause the next cut was %s, not A1"
			% String(combat.active_move_id)
	)
	_ok("§32-7  A1→A2 → wait → A1")
	await _settle_idle()


# ===========================================================================
#  §32 · 8 — SWORD → CHAIN → SWORD (§3 / §5 / §20)
# ===========================================================================

func _scenario_weapon_round_trip() -> void:
	await _arm_scenario()
	await _run_chain(2)

	# OUT: the slot must NOT change on the frame of the press, or the rig that is
	# mid-swing is hidden and the put-away is a disappearance.
	manager.call("equip_weapon", &"chain")
	_check(weapon.is_sword(), "§20: the slot took the chain on the frame of the press, so there is no sheathe")
	var blend_at_press := float(combat.equip_blend)
	await physics_frame
	_check(
		float(combat.equip_blend) < blend_at_press,
		"§3: the blade never started going home (blend %.2f -> %.2f)"
			% [blend_at_press, float(combat.equip_blend)]
	)
	_check(combat.active_move == null, "§5: a cut survived the frame of the weapon change")
	await _settle_switch()
	_check(weapon.is_chain(), "§3: the sheathe never delivered the chain")
	_check(
		float(combat.equip_blend) <= 0.001,
		"§3: the chain is in hand with the blade still out (blend %.2f)"
			% float(combat.equip_blend)
	)

	# BACK: pressing 1 is a draw again, and the first cut afterwards is A1.
	manager.call("equip_weapon", &"sword")
	var snap := combat.pose_snapshot()
	var seated := (snap["position"] as Vector3).distance_to(SwordBasic.SAYA_MOUTH)
	_check(
		seated < 0.001,
		"§20: the returning blade started %.4fm from the saya mouth, so it was placed "
			% seated
		+ "rather than drawn"
	)
	await _settle_draw()
	_check(float(combat.equip_blend) >= 0.999, "§3: the draw never completed")
	combat.request(&"light")
	await physics_frame
	_check(
		combat.active_move_id == combat.moveset.light_chain[0],
		"§17: the first cut after a weapon round trip was %s, not A1"
			% String(combat.active_move_id)
	)
	await _settle_idle()
	_ok("§32-8  Sword → Chain → Sword — sheathe, then a seated draw, then A1")


# ===========================================================================
#  HARNESS
# ===========================================================================

func _on_hit(move: SwordMove, hit: Dictionary) -> void:
	var target: Node3D = hit.get("target")
	if target == null or move == null:
		return
	var id := StringName(String(target.name).replace("Target_", ""))
	_cut_ids[id] = true
	_cuts.append({
		"move": move.id, "target": id, "mode": move.reach_mode,
		"damage": float(hit.get("damage", 0.0)),
	})


func _on_trace(index: int, hits: int, mark: Dictionary) -> void:
	_marks.append({"index": index, "hits": hits, "angle": float(mark.get("angle", 0.0))})
	if hits > 0 and not _marks_with_hits.has(index):
		_marks_with_hits.append(index)


## Clears the per-scenario record. Deliberately does NOT clear `_combo_moves`,
## which is the whole-run order log.
func seal_clear() -> void:
	_cuts.clear()
	_marks.clear()
	_marks_with_hits.clear()
	_cut_ids.clear()
	_waves = 0


func seal(id: StringName) -> bool:
	return _cut_ids.has(id)


func _mode_of(id: StringName) -> StringName:
	for cut in _cuts:
		if cut["target"] == id:
			return cut["mode"]
	return &""


func _distance(id: StringName) -> float:
	var body := zone.target(id) as Node3D
	if body == null:
		return -1.0
	return player.global_position.distance_to(body.global_position)


func _summary() -> String:
	var parts := PackedStringArray()
	for cut in _cuts:
		parts.append("%s/%s" % [String(cut["target"]), String(cut["move"])])
	return ", ".join(parts) if not parts.is_empty() else "nothing was cut"


## What each of A3's cuts found, printed rather than only asserted on: a run that
## says "1 of 3" is a run whose next question is always "which one".
func _mark_summary() -> String:
	var parts := PackedStringArray()
	for mark in _marks:
		parts.append("%.0f°→%d" % [float(mark["angle"]), int(mark["hits"])])
	return "[" + ", ".join(parts) + "]"


## Puts the rig back to a known fighting state before a scenario: sword drawn,
## idle, every window closed, and a clean record.
##
## THE SCENARIO BOUNDARY IS A SCENE RESET, and §17 lists a scene reset as one of
## the things that resets the combo. That is not test convenience: without it,
## scenario two inherits scenario one's `combo_index` and its still-open grace
## window, so "A1 only" silently runs A3 — and the failure shows up as an
## assertion about A3's mechanics rather than as the one-line truth that the
## player never stopped pressing. The first run of this file failed on exactly
## that, eleven checks deep, which is the cost of not modelling the boundary.
func _arm_scenario() -> void:
	manager.call("reset_weapons")
	await _wait(2)
	if not weapon.is_sword() or float(combat.equip_blend) < 0.999:
		manager.call("equip_weapon", &"sword")
		await _settle_switch()
		await _settle_draw()
	combat.finish_action()
	await _wait(2)
	seal_clear()
	_combo_moves.clear()


## Presses Light `beats` times, each press landing inside the previous cut's own
## cancel window — i.e. the way a player chains, not the way a script would.
func _run_chain(beats: int) -> void:
	combat.request(&"light")
	if combat.active_move != null:
		_combo_moves.append(combat.active_move_id)
	for i in beats - 1:
		if not await _advance_to_cancel():
			_fail("the combo stalled after %d of %d beats" % [i + 1, beats])
			break
		combat.request(&"light")
		if combat.active_move != null:
			_combo_moves.append(combat.active_move_id)
	await _settle_idle()


func _advance_to_cancel() -> bool:
	var guard := 0
	while guard < 300:
		if combat.state == CombatController.State.IDLE:
			return false
		if combat.active_move != null and bool(combat.call("_can_cancel", &"light")):
			return true
		await physics_frame
		guard += 1
	return false


func _settle_idle() -> void:
	var guard := 0
	while combat.state != CombatController.State.IDLE and guard < 600:
		await physics_frame
		guard += 1
	await _wait(2)


func _settle_switch() -> void:
	var guard := 0
	while (String(manager.get("_pending_slot")) != "" or bool(manager.get("switching"))) and guard < 400:
		await physics_frame
		guard += 1
	await _wait(2)


func _settle_draw() -> void:
	var guard := 0
	while (bool(manager.get("drawing_in")) or float(combat.equip_blend) < 0.999) and guard < 400:
		await physics_frame
		guard += 1
	await _wait(2)


## Waits longer than `moveset.combo_window`, derived rather than hard-coded, so
## this stays a test of the window and not of a number someone typed twice.
func _pause_longer_than_the_window() -> void:
	var seconds: float = combat.moveset.combo_window * 1.6
	var frames := int(ceil(seconds * 60.0))
	await _wait(frames)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)


func _ok(line: String) -> void:
	print("  " + line)


func _finish() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await _wait(8)
	_cuts.clear()
	_cut_ids.clear()
	if failures.is_empty():
		print("PASS: sword basic attack V2 — every §32 scenario measured, in a real arena")
		call_deferred("quit",0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	call_deferred("quit",1)
