extends SceneTree
## PROBE · HOW MANY SCABBARDS IS THE PLAYER WEARING, AND WHEN
##
## Four different owners can each put a saya on the same player, and every one of
## them is individually correct:
##
##   * `WeaponRoot/SwordSayaRig`                  -- COMBAT's second weapon actor
##                                                   (this line's own, driven by
##                                                   `equip_blend` + `saya_pull`).
##   * `WeaponRoot/SheathAnchor/CeremonyScabbard` -- the iaido ceremony's sheath,
##                                                   opened by `IaidoDirector`.
##   * `WeaponRoot/TempSwordVisual/Scabbard`      -- 藏锋's sheathed idle, opened
##                                                   by `SwordMoveset.sheath_enabled`.
##   * `WeaponRoot/TempSwordVisual/Sword_FP/Sheath` -- the rack exhibit's seated
##                                                   saya.
##
## Nothing tells them about each other, so "is there one saya or two on screen
## right now" is not answerable by reading any one file. It is a measurement, and
## this is the instrument.
##
## The output is deliberately the minimum that answers it: at each beat, the LIST
## of scabbard subtrees that are actually visible in the tree. One line means one
## saya. Two lines means the bug, and it names both owners.
##
## Run:  Godot --headless --path F:/SEKAI/godot --script res://tools/probe_saya_visibility.gd

const STAGE := "res://scenes/combat/CombatSandbox.tscn"

## Name fragments that mean "this node is a scabbard". Lower-cased because the
## rigs disagree about capitalisation by author, not by contract.
const KEYS := ["saya", "scabbard", "sheath"]

var _stage: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed := load(STAGE) as PackedScene
	if packed == null:
		print("PROBE FAIL: no stage")
		quit(1)
		return
	_stage = packed.instantiate() as Node3D
	root.add_child(_stage)
	for _i in 4:
		await process_frame

	var player := _stage.get_node_or_null("Player")
	if player == null:
		print("PROBE FAIL: no player")
		quit(1)
		return
	var combat := player.get_node_or_null("CombatController")
	var manager := player.get_node_or_null("WeaponManager")
	if combat == null or manager == null:
		print("PROBE FAIL: combat=%s manager=%s" % [combat, manager])
		quit(1)
		return
	print("PROBE style=%s sheath_enabled=%s" % [
		combat.get("style_id"), combat.moveset.sheath_enabled,
	])

	_dump("T0 · initial, sword NOT in hand")

	manager.call("equip_weapon", &"sword")
	await _wait(1.4)
	_dump("T1 · after DRAW completes")

	await _beat(combat, "T2 · A1")
	await _beat(combat, "T3 · A2")
	await _beat(combat, "T4 · A3 (micro iaido domain)")
	await _beat(combat, "T5 · A4")

	manager.call("equip_weapon", &"chain")
	await _wait(2.2)
	_dump("T6 · switched TO CHAIN")

	manager.call("equip_weapon", &"sword")
	await _wait(2.2)
	_dump("T7 · back TO SWORD")

	# 藏锋's sheathed idle is the third owner: `SwordMoveset.sheath_enabled` makes
	# `TempSwordVisual/Scabbard` visible for as long as the style is on. It is a
	# different scabbard node from the ceremony's, so it can collide too.
	combat.call("set_style", &"hidden_edge", true)
	await _wait(1.8)
	_dump("T8 · HIDDEN EDGE style (sheath_enabled=true)")
	combat.call("set_style", &"universal", true)
	await _wait(1.2)

	await _ceremony(
		"T9 · 居合斩 through the player's door (request)",
		func() -> void: combat.call("request", &"iaido"),
	)
	await _wait(1.2)
	await _ceremony(
		"T10 · 居合斩 started directly on the director (robustness)",
		func() -> void: (_stage.get_node("IaidoDirector") as Node).call("start_iaido"),
	)

	print("")
	print("PROBE done")
	quit(0)


## One light attack, then far enough past its total for the beat to have settled.
func _beat(combat: Node, tag: String) -> void:
	combat.call("request", &"light")
	await _wait(1.5)
	_dump(tag)


## 居合斩. Started through the PLAYER'S OWN DOOR — `CombatController.request` — and
## not by calling `IaidoDirector.start_iaido` directly, because the two are not
## the same path: the ceremony pauses the tree, and the controller's own
## stand-down happens in the request handler. A probe that bypasses the door
## tests code no player ever runs.
##
## Runs to the ceremony's natural end (it is 9.9s long) and reports the PEAK
## number of simultaneous scabbards, which is the whole question.
func _ceremony(tag: String, opener: Callable) -> void:
	var iaido := _stage.get_node_or_null("IaidoDirector")
	if iaido == null:
		print("")
		print("==== ", tag, " -- NO IaidoDirector IN STAGE")
		return
	print("")
	print("==== ", tag)
	opener.call()
	if not bool(iaido.get("active")):
		print("  ceremony REFUSED -- never became active")
		return
	var last := ""
	var seconds := 0.0
	var peak := 0
	while seconds < 16.0:
		await process_frame
		seconds += 1.0 / 60.0
		var shown := _visible_saya()
		peak = maxi(peak, shown.size())
		var now := ", ".join(shown)
		if now != last:
			print("  t=%.2f  visible: [%s]" % [seconds, now])
			last = now
		if not bool(iaido.get("active")):
			break
	print("  ceremony ran %.2fs -- PEAK SIMULTANEOUS SCABBARDS = %d" % [seconds, peak])
	await _wait(0.5)
	_dump(tag + " · after")


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## The answer to the whole question: every scabbard subtree visible in the tree,
## right now. A subtree is reported by its top, and its inside is not descended
## into — a GLB scabbard is one object however many nodes it is made of.
func _visible_saya() -> Array:
	var out: Array = []
	_collect(_stage, "", out)
	out.sort()
	return out


func _collect(node: Node, prefix: String, out: Array) -> void:
	for child in node.get_children():
		var path := prefix + "/" + String(child.name)
		if _names_a_scabbard(String(child.name)):
			if child is Node3D and (child as Node3D).is_visible_in_tree():
				out.append(path)
			continue
		_collect(child, path, out)


## An ANCHOR IS NOT A SCABBARD, and getting this wrong cost a whole probe run.
##
## `SheathAnchor` carries the mouth's frame and draws nothing. When it was
## counted, it not only reported a phantom saya on every single frame -- it also
## SWALLOWED THE REAL ONE, because the walk stops at the first match and
## `CeremonyScabbard` is parented underneath it. The ceremony then measured as
## "one scabbard, never changes", which is the opposite of the truth.
func _names_a_scabbard(node_name: String) -> bool:
	var low := node_name.to_lower()
	if low.ends_with("anchor"):
		return false
	for key in KEYS:
		if low.contains(key):
			return true
	return false


func _dump(tag: String) -> void:
	var shown := _visible_saya()
	print("")
	print("==== %s" % tag)
	print("  VISIBLE SCABBARDS: %d" % shown.size())
	for path in shown:
		print("    %s" % path)
