extends SceneTree
## Boots Main.tscn, takes the SECOND door (start_region), and proves the region
## actually mounts and simulates — the thing a "menu entry" commit usually ships
## untested, because clicking a button is not something a headless run can do.
##
## It also asserts the two things that break when a scene built to be the whole
## game is mounted inside another one: the walker must still be reachable by the
## HUD, and the pause path must survive a world that has no IaidoDirector.
##
## Run:
##   Godot --headless --path F:/SEKAI/godot --script res://tools/smoke_region_entry.gd

var _fail := 0

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	print("[1] Main.tscn mounted")

	# The menu must offer the door before anything can walk through it.
	var menu := main.get_node_or_null("MainMenu")
	if menu == null:
		_fail += 1
		print("    FAIL: no MainMenu")
	elif not menu.has_signal("region_pressed"):
		_fail += 1
		print("    FAIL: MainMenu has no region_pressed signal")
	else:
		print("    ok: MainMenu exposes region_pressed")

	main.call("start_region")
	# start_region() is a coroutine: it flushes a loading notice, then builds.
	# Wait for the world to appear rather than counting frames, so the test does
	# not depend on how many frames the notice costs.
	var waited := 0
	while main.call("active_world") == null and waited < 600:
		await process_frame
		waited += 1
	print("    ok: region mounted after %d frames" % waited)

	var world: Node3D = main.call("active_world")
	if world == null:
		_fail += 1
		print("[2] FAIL: start_region mounted nothing after %d frames" % waited)
		_done()
		return
	print("[2] region: %s" % world.name)
	if world.name != "MistvaleRegion":
		_fail += 1
		print("    FAIL: wrong world: %s" % world.name)

	var walker := world.get_node_or_null("ReviewWalker")
	if walker == null:
		_fail += 1
		print("    FAIL: no ReviewWalker")
	else:
		print("    ok: walker at %v" % walker.global_position)

	var hud := world.get_node_or_null("RegionWalkHUD")
	if hud == null:
		_fail += 1
		print("    FAIL: no RegionWalkHUD")
	elif hud.get("_walker") == null:
		_fail += 1
		print("    FAIL: HUD did not resolve the walker")
	elif hud.get("_label") == null:
		_fail += 1
		print("    FAIL: HUD did not build its label")
	else:
		print("    ok: HUD bound (band=%s)" % hud.call("_band_name", 500.0))

	# Let gravity settle the walker onto the terrain, then confirm the HUD is
	# producing text rather than crashing on frame cost.
	var y0: float = walker.global_position.y if walker != null else 0.0
	for i in range(90):
		await physics_frame
	if walker != null:
		print("[3] walker settled at %v  (dropped %.2f m off spawn)" % [
			walker.global_position,
			y0 - walker.global_position.y,
		])

	var label: Label = hud.get("_label") if hud != null else null
	if label != null:
		print("[4] HUD text: %s" % label.text.replace("\n", " | "))

	# The pause path is the other thing that assumes CombatSandbox.
	main.call("pause_game")
	await process_frame
	var pm := main.get_node_or_null("PauseMenu")
	if pm == null or not pm.visible:
		_fail += 1
		print("[5] FAIL: pause_game did not show the pause menu")
	else:
		print("[5] ok: pause menu shown with region mounted")
	main.call("resume_game")
	main.call("return_to_title")
	await process_frame
	if main.call("active_world") != null:
		_fail += 1
		print("[6] FAIL: return_to_title left the world mounted")
	else:
		print("[6] ok: return_to_title unloaded the region")

	_done()


func _done() -> void:
	# Free the world BEFORE quitting. Calling quit() with the region still
	# resident segfaults during headless teardown — the terrain trimesh collision
	# and the flora multimeshes come apart in an order the shutdown path does not
	# expect, and the crash lands AFTER the PASS line, which is worse than a real
	# failure: it makes a green run look red.
	for c in root.get_children():
		root.remove_child(c)
		c.free()
	print("=== %s ===" % ("PASS" if _fail == 0 else "FAIL x%d" % _fail))
	quit(0 if _fail == 0 else 1)
