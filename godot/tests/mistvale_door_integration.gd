extends SceneTree

## Does the region door actually open the imported UE5 town, with the real
## Player, standing on the baked collision?
##
## Why this test exists rather than a probe that instantiates the scene directly:
## instantiating MistvalePlayable.tscn proves the scene works. It does not prove
## the DOOR reaches it, and the door is one exported PackedScene in main_flow.gd
## pointing at a path -- the exact kind of thing that silently keeps opening the
## old world after everything else has been rewired. So this walks the real path:
## Main.tscn, the real signal, the real start_region().
##
## The discriminator between the two worlds is structural, not a name check on
## the scene file: MistvalePlayable mounts Player.tscn and derives Anchors/Art at
## run time, while MistvaleRegion mounts ReviewWalker and has no Player at all.

const MAX_SETTLE_FRAMES := 240
const STAND_FRAMES := 90
## How far the player may drift vertically once placed. Standing still, this is
## physics noise; falling through the map is metres.
const STAND_TOLERANCE := 0.30


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main/Main.tscn")
	if scene == null:
		return _fail("cannot load Main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	if not main.main_menu.visible or main.region_world != null:
		return _fail("expected the main menu on launch")

	# The real door: the button's own signal.
	main.main_menu.region_pressed.emit()

	# start_region() awaits two process frames, and the world's _ready() awaits
	# two physics frames before it places the player. Wait for the STATE, not for
	# a frame count: "the world exists" is not "the player has been placed", and
	# checking Anchors alone returned a report whose spawn audit was still empty.
	var world: Node3D = null
	var frames := 0
	while frames < MAX_SETTLE_FRAMES:
		await process_frame
		await physics_frame
		frames += 1
		var candidate: Node3D = main.region_world
		if candidate == null or not candidate.has_node("Anchors"):
			continue
		var seen: Dictionary = candidate.call("report")
		if (seen.get("spawn_audit", {}) as Dictionary).is_empty():
			continue
		if candidate.has_node("Art") and candidate.has_node("Player"):
			world = candidate
			break
	if world == null:
		return _fail("region door never produced a settled world (%d frames)" % frames)

	if main.main_menu.visible:
		return _fail("the menu stayed up over the world")
	if main.active_world() != world:
		return _fail("active_world() is not the region door's world")

	# --- is this the imported town, or the blockout? ------------------------
	if not world.has_node("Player"):
		return _fail("no Player: the door opened a world without the real player")
	if world.has_node("ReviewWalker"):
		return _fail("ReviewWalker present: the door opened the LD-01 blockout, not the imported town")
	if not world.has_node("Art"):
		return _fail("no Art: the imported UE5 geometry was not mounted")

	# --- did the anchors resolve, and are any of them on a roof? ------------
	var report: Dictionary = world.call("report")
	if not report["missing_sources"].is_empty():
		return _fail("anchor sources missing: %s" % [report["missing_sources"]])
	if not report["missing_anchors"].is_empty():
		return _fail("anchors unresolved: %s" % [report["missing_anchors"]])
	if report["safe_points"] != 6:
		return _fail("expected 6 safe points, got %s" % report["safe_points"])
	if report["anchor_audit"].size() != 22:
		return _fail("expected 22 anchors, got %d" % report["anchor_audit"].size())
	if not report["suspect_roof"].is_empty():
		return _fail("anchors sitting on their own source's roof: %s" % [report["suspect_roof"]])

	# --- is the player standing on the road, or floating / inside it? -------
	var player: CharacterBody3D = world.get_node("Player")
	var spawn: Dictionary = report["spawn_audit"]
	var expected_y: float = spawn["ground_y"] + 0.95
	if absf(player.global_position.y - expected_y) > 0.25:
		return _fail("player y=%.2f is not on the reported ground (%.2f + capsule)"
			% [player.global_position.y, spawn["ground_y"]])

	var start_y := player.global_position.y
	for _i in STAND_FRAMES:
		await physics_frame
	var dropped := start_y - player.global_position.y
	if absf(dropped) > STAND_TOLERANCE:
		return _fail("player fell %.2f m in %d frames -- not standing on the collision"
			% [dropped, STAND_FRAMES])

	# Read everything off the live nodes NOW. Returning to title frees the world,
	# so a print placed after it dereferences a freed object -- which is how the
	# first version of this test reported success and then crashed.
	var spawn_x := player.global_position.x
	var spawn_y := player.global_position.y
	var spawn_z := player.global_position.z
	var ground_y: float = spawn["ground_y"]

	# --- the world must survive the pause path -----------------------------
	main.pause_game()
	if not main.pause_menu.visible or world.process_mode != Node.PROCESS_MODE_DISABLED:
		return _fail("pause did not stop the imported town")
	main.pause_menu.resume_pressed.emit()
	if main.pause_menu.visible or world.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return _fail("resume did not restore the imported town")
	main.pause_menu.title_pressed.emit()
	await process_frame
	if not main.main_menu.visible or main.region_world != null:
		return _fail("return to title did not free the imported town")

	print("PASS: region door -> imported town, real player on the road, %d anchors, 6 safe points"
		% report["anchor_audit"].size())
	print("PASS: spawn x=%.2f y=%.2f z=%.2f on ground y=%.2f; drift over %d frames %.3f m"
		% [spawn_x, spawn_y, spawn_z, ground_y, STAND_FRAMES, dropped])
	quit(0)


func _fail(reason: String) -> void:
	push_error("FAIL: " + reason)
	quit(1)
