extends SceneTree
## PROBE · WHICH MOVE DOES EACH `light` ACTUALLY PRODUCE?
##
## ===========================================================================
## WHY THIS EXISTS
## ===========================================================================
## `probe_saya_motion.gd` drives the light chain and files its four legs under the
## names `a1`, `a2`, `a3`, `a4`. Those names are a CLAIM about which move was
## playing, and nothing in that file ever checks it. `combat.request(&"light")`
## returns whether an attack started, not which one -- see the note in
## `saya_controlled_stillness_movie.gd`, which does check and found four acts
## going missing when it did not.
##
## The chain only advances while the previous light is still swinging
## (`chain_active`) or within `moveset.combo_window` of the attack's START. The
## motion probe leaves 1.1 s of idle between legs, which is more than twice the
## 0.46 s window, so the arithmetic says every one of its five requests restarts
## the sentence at A1 -- and therefore that no leg of it has ever measured A2,
## A3 or A4.
##
## That is a claim about an instrument, so it gets measured rather than reasoned.
## This repeats the probe's own timing exactly (1.1 s of idle between requests)
## and prints `combo_index` and `active_move_id` for each, then repeats the run
## with the requests fired inside the cancel window for comparison.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/probe_chain_identity.gd

const GAP := 1.1

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var manager: Node
var _fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	await _frames(14)
	player = world.get_node("Player")
	combat = player.get_node("CombatController")
	manager = player.get_node_or_null("WeaponManager")
	if combat == null or manager == null:
		print("FAIL: no combat controller or no manager")
		quit(1)
		return
	manager.call("equip_weapon", WeaponSlot.SWORD)
	await _frames(6)
	await _sleep(2.6)

	var chain: Array = combat.moveset.light_chain
	print("")
	print("the sentence is %s" % str(chain))
	print("combo_window = %.2f s" % combat.moveset.combo_window)
	print("")

	print("── RUN A · the motion probe's own timing (%0.1f s of idle between requests)" % GAP)
	await _sweep(GAP, "A")
	print("")
	print("── RUN B · requests fired inside the cancel window (0.30 s after the request)")
	await _sweep(0.30, "B")

	print("")
	print("── verdict")
	if _fails.is_empty():
		print("   ok   both runs are self-consistent")
	else:
		for f in _fails:
			print("   FAIL %s" % f)
	print("P_CHAIN DONE")
	# Take the world back down: a probe that leaks on a clean run reports errors
	# that are about itself and teaches the next reader to ignore them.
	if world != null and is_instance_valid(world):
		root.remove_child(world)
		world.free()
	world = null
	quit(1 if not _fails.is_empty() else 0)


## Fires `light` five times with `gap` seconds of idle between, printing what each
## request actually produced. `expect_gap` is the label used in the verdict text.
func _sweep(gap: float, run: String) -> void:
	var seen: Array[String] = []
	for i in 5:
		if i > 0:
			await _sleep(gap)
		var before_state := combat.state
		var ok := combat.request(&"light")
		if not ok:
			print("   %s#%d  REQUEST REFUSED (state=%s)" % [run, i + 1, _state_name(before_state)])
			seen.append("(refused)")
			continue
		await _frames(2)
		var id := String(combat.active_move_id)
		var idx := combat.combo_index
		seen.append(id)
		print("   %s#%d  combo_index=%d  active_move_id=%-8s  chain[%d]=%s" % [
			run, i + 1, idx, id, idx - 1,
			str(chain_at(idx))])
		# Wait for the swing to finish so the next request starts from a quiet rig,
		# exactly as `_leg` does.
		await _until_idle(6.0)

	var distinct := {}
	for s in seen:
		distinct[s] = true
	print("   produced %d request(s) across %d distinct move(s): %s" % [
		seen.size(), distinct.size(), str(distinct.keys())])
	if run == "A" and distinct.size() < 2:
		_fails.append(
			"RUN A reached only %d distinct move(s) -- the motion probe's a1/a2/a3/a4 legs are all the same act" % distinct.size())
	if run == "B" and distinct.size() < 2:
		print("   note: RUN B also reached only %d -- chaining needs the request inside the swing" % distinct.size())


func chain_at(index: int) -> String:
	var chain: Array = combat.moveset.light_chain
	if index >= 0 and index < chain.size():
		return String(chain[index])
	return "(out of range)"


func _sleep(seconds: float) -> void:
	var deadline := combat.combat_time + seconds
	while combat.combat_time < deadline:
		await process_frame


func _until_idle(limit: float) -> void:
	var deadline := combat.combat_time + limit
	while combat.combat_time < deadline:
		await process_frame
		if combat.state == CombatController.State.IDLE and combat.state_time > 0.05:
			return


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _state_name(state: int) -> String:
	var names := ["IDLE", "ATTACK", "RIPOSTE", "SKILL", "CHARGE", "BLOCK", "PARRY",
		"CAST", "DODGE"]
	return names[state] if state >= 0 and state < names.size() else str(state)
