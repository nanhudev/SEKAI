extends SceneTree
## Photographs the THIRD DOOR: the title screen, then whatever clicking it puts
## the player inside.
##
## WHY THIS EXISTS AND NOT "just run training_ground_renderer.gd". That renderer
## loads the compound DIRECTLY. It therefore proves the compound renders, and
## proves nothing about the thing that changed: that 进入战斗沙盒 in
## `scenes/main/Main.tscn` now opens it. A door that opens nothing photographs
## beautifully when you bypass the door.
##
## So this walks the real path — `Main.tscn`, the real menu node, the real signal
## `main_menu.gd` emits — and then asserts what came up. It is the picture AND the
## check in one run, which is the only version of this worth keeping.
##
## Run (REAL WINDOW - `--headless` disables rendering and every frame is black;
## the same rule the training-ground renderer carries):
##
##   G:/Godot/Godot_v4.4.1-stable_win64_console.exe --path F:/SEKAI/godot \
##     --resolution 1600x900 --audio-driver Dummy \
##     --script res://tools/shot_combat_door.gd
##
## Exit code is the number of failed assertions, so a silent run is a passing run.

const MAIN := "res://scenes/main/Main.tscn"
const OUT_DIR := "F:/SEKAI/assets_source/review/door/"

## Frames to let go by before any shutter opens, so a transform set on a node has
## actually been through the renderer. See the same constant in
## `training_ground_renderer.gd`.
const WARMUP := 8
## Frames AFTER the gate comes true before reading the framebuffer back.
##
## `root.get_texture()` hands back the render target as it stands when `_process`
## runs, and this frame has not been drawn yet — so a capture taken on the frame a
## gate comes true contains the frame BEFORE it. Two frames is what it costs to
## photograph the state instead of the transition into it.
const CAPTURE_LAG := 2
## A gate that never comes true is a bug in the gate, and a run that waits forever
## on one produces no picture and no error either. The compound builds from
## literals and a 12-piece kit rather than a heightfield, so 20 s is already an
## order of magnitude beyond what it should need.
const GATE_TIMEOUT := 20.0

## The kit pieces the compound places. Named here to assert the map is the compound
## rather than merely a scene with the right name.
const ENV_PREFIX := "ENV01_"

var _main: Node = null
var _frame := 0
var _phase := 0
var _settle := 0
var _clicked_at := -1.0
var _elapsed := 0.0
var _fail := 0
var _lines := PackedStringArray()
var _aerial: Camera3D = null


func _initialize() -> void:
	pass


func _process(delta: float) -> bool:
	_frame += 1
	_elapsed += delta

	if _phase == 0:
		if _frame == 1:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
			DisplayServer.window_move_to_foreground()
			var packed: PackedScene = load(MAIN)
			if packed == null:
				return _bail("could not load " + MAIN)
			_main = packed.instantiate()
			root.add_child(_main)
			# The menu is a Control; nothing needs a camera until a world is
			# mounted, so the title frame is captured without one.
			return false
		if _frame < WARMUP:
			return false
		_capture("01_title")
		_phase = 1
		return false

	# ---------------------------------------------------------------- the click
	if _phase == 1:
		# THE REAL DOOR. `start_pressed` is the signal `main_menu.gd` emits from the
		# 进入战斗沙盒（训练场） button; emitting it is exactly what a click does,
		# and it is what `menu_flow_integration.gd` does for the same reason.
		_check(_menu().visible, "title screen was visible before the click")
		_clicked_at = _elapsed
		_menu().emit_signal("start_pressed")
		_phase = 2
		return false

	# ---------------------------------------------------------------- the gate
	if _phase == 2:
		var world: Node3D = _main.get("combat_world") as Node3D
		if world == null:
			if _elapsed - _clicked_at > GATE_TIMEOUT:
				return _bail("start_pressed opened no world after %.1f s" % GATE_TIMEOUT)
			return false
		# THE GATE IS THE FIXTURE'S OWN READING, not a duration: the compound builds
		# inside `_ready()`, so a world that exists with kit pieces in it has
		# finished building, and one that exists without them has not.
		if _kit_count(world) == 0:
			if _elapsed - _clicked_at > GATE_TIMEOUT:
				return _bail("the world opened but placed no ENV-01 pieces")
			return false
		_settle += 1
		if _settle < WARMUP + CAPTURE_LAG:
			return false
		_photograph_the_door()
		_phase = 3
		return false

	# ---------------------------------------------------------------- the aerial
	if _phase == 3:
		if _aerial == null:
			# The same vantage `training_ground_renderer.gd` uses for 01_aerial, so
			# the two sheets can be put side by side without an argument about which
			# camera is right.
			_aerial = Camera3D.new()
			_aerial.name = "DoorAerialCam"
			_aerial.fov = 70.0
			_aerial.near = 0.1
			_aerial.far = 4000.0
			root.add_child(_aerial)
			_aerial.global_position = Vector3(0.0, 86.0, 30.0)
			_aerial.look_at(Vector3(0.0, 0.0, -19.0), Vector3.UP)
			_aerial.make_current()
			_settle = 0
			return false
		_settle += 1
		if _settle < WARMUP + CAPTURE_LAG:
			return false
		_capture("03_compound_aerial")
		return _finish()

	return _finish()


# ---------------------------------------------------------------- the checks

## Everything the picture is claimed to show, asserted. A picture with no
## assertions beside it is a picture of an unverified scene: the four failures
## below are all cases where the frame would look plausible and the wiring would
## be wrong.
func _photograph_the_door() -> void:
	var world: Node3D = _main.get("combat_world") as Node3D
	_check(world != null, "start_pressed mounted a world")
	_check(String(world.scene_file_path).ends_with("TrainingGround.tscn"),
		"the world behind the third door IS the training compound (got %s)"
		% world.scene_file_path)
	# The room's own two nodes, one from ART (Ground) and one from COMBAT
	# (MovementLane, instanced rather than rebuilt). A scene that mounted the right
	# FILE but failed to build its body would still pass a path check.
	_check(world.has_node("Ground"), "the compound built its ground")
	_check(world.has_node("MovementLane"), "the compound hosts MovementLane")
	_check(world.has_node("Player"), "the compound mounted the player")
	# THE OLD ARENA'S PLACEHOLDER. `ArenaDressing` existed for one reason — an empty
	# box had no silhouettes for a cut to act on — and it is the single most
	# recognisable thing about the map this door used to open. If it is still here,
	# the door moved and the map did not.
	_check(not world.has_node("ArenaDressing"),
		"the old 24 m arena's placeholder dressing is gone (this is the new map)")
	var kit := _kit_count(world)
	_check(kit > 0, "the ENV-01 kit actually loaded (%d pieces placed)" % kit)
	_check(_main.call("active_world") == world, "active_world() reports the mounted world")
	_check(not _menu().visible, "the menu got out of the way")
	# THE FRAME MUST BE THE PLAYER'S. `ForegroundWeaponLayer` creates a second
	# camera and makes it current — inside its own SubViewport — so "some camera is
	# current" is not the question; the question is whether the MAIN viewport's
	# camera is the player's eye. If it is not, the frame is a still of the inside
	# of the viewmodel.
	var eye := world.get_node_or_null(
		"Player/CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	_check(eye != null, "the player still has a camera")
	if eye != null:
		_check(eye.is_current(), "the captured frame is the player's own eye")
		_say("spawn eye=%s forward=%s" % [str(eye.global_position), str(-eye.global_basis.z)])
	_capture("02_spawn")


## The title screen's menu node, typed. `_main.get("main_menu")` is a Variant, and
## a Variant method chain is how a typo in a property name becomes a runtime error
## inside an assertion instead of a parse error at the top of the file.
func _menu() -> Control:
	return _main.get("main_menu") as Control


func _kit_count(world: Node3D) -> int:
	var n := 0
	for node in world.find_children(ENV_PREFIX + "*", "Node3D", true, false):
		# `find_children` matches the pattern anywhere in the tree; the kit pieces
		# are the roots of their own instanced scenes, so counting node names that
		# start with the prefix and have no kit-piece parent would double-count a
		# hierarchy. Counting only names that ARE a kit piece (the parent is not one)
		# is what makes this a count of pieces.
		if not String(node.get_parent().name).begins_with(ENV_PREFIX):
			n += 1
	return n


func _check(ok: bool, what: String) -> void:
	if ok:
		_say("  ok   %s" % what)
	else:
		_fail += 1
		_say("  FAIL %s" % what)


func _capture(name_v: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		_fail += 1
		_say("  FAIL null image at %s" % name_v)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := OUT_DIR + name_v + ".png"
	var err := img.save_png(path)
	_say("  saved %s (err=%d) %dx%d" % [path, err, img.get_width(), img.get_height()])
	if err != OK:
		_fail += 1


func _bail(reason: String) -> bool:
	_fail += 1
	_say("  FAIL " + reason)
	return _finish()


func _say(line: String) -> void:
	_lines.append(line)


func _finish() -> bool:
	print("=== combat door: %s ===" % ("FAILED %d" % _fail if _fail > 0 else "OK"))
	for line in _lines:
		print(line)
	flush()
	quit(_fail)
	return true


## The run log, beside the frames, for the same reason every other renderer here
## writes one: a sheet of pictures with no line saying which vantage or which
## assertion produced it cannot be checked by anyone but the person who ran it.
func flush() -> void:
	var f := FileAccess.open("F:/SEKAI/assets_source/review/door_render.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
