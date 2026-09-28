extends SceneTree
## THE FIRST-PERSON SWORD, CAPTURED FROM THE PLAYER'S OWN EYE.
##
##   $GODOT --path F:/SEKAI/godot --resolution 1280x720 --audio-driver Dummy \
##     --script res://tools/shot_fp_sword.gd
##
## Needs a REAL WINDOW -- `--headless` disables rendering.
##
## WHY THIS IS NOT `shot_weapon_rack.gd`.  That tool measures the sword lying on a
## rack, at 0.6-2.5 m, with the viewmodel hidden, because it is answering "is the
## shipped asset the asset on the wall".  This tool answers the other half of
## PART O/PART I: what does the weapon look like where the player actually sees
## it, composited into the first-person layer, during an attack.
##
## WHAT IT IS REALLY FOR.  A model swap can pass every numeric check -- node paths
## intact, hitbox unmoved, blade_length corrected -- and still be wrong on screen,
## because the weapon in the player's hands is not drawn by the world camera.  It
## is drawn by `ForegroundWeaponLayer`, which copies every MeshInstance3D under
## WeaponRoot into its own SubViewport and composites it as a full-screen
## TextureRect on a CanvasLayer.  That layer scans the subtree exactly ONCE, in
## its own `_ready`, so a rig created after that scan renders in the world and
## disappears from the held weapon.  Only an image catches that.
##
## The same layer is why the lighting bug was only ever visible here: it renders
## the weapon in a PRIVATE World3D, so the world's sun never reached it and the
## blade came back as a black bar.  See `foreground_weapon_layer.gd` §LIGHT and
## REQ-8.  A rack capture cannot see that, because the rack is not in the layer.
##
## `root.get_texture().get_image()` is the right capture and `get_viewport()` is
## not: this is a SceneTree script, so there is no viewport on `self`, and `root`
## is the Window whose texture is the FINAL composed frame -- world, glass, HUD
## and the weapon layer, in the order the player sees them.

const SCENE := "res://scenes/training/TrainingGround.tscn"
const OUT_DIR := "F:/SEKAI/assets_source/review/fp_sword/"

## READ THE IMAGES, NOT THE EXIT CODE.
##
## This tool very often ends with `Program crashed with signal 11` -- always
## AFTER every image has been written and after `SHOT_DONE` is printed, so it has
## never cost a capture. It is an intermittent crash in Godot's own teardown of
## this scene, and it is not this tool's doing: measured with the attack removed
## and with `ForegroundWeaponLayer._mirror_world_lighting()` disabled, and it
## still crashed. It is not a settle threshold either -- 40 frames crashed, 120
## crashed, 240 both crashed and did not, which is a coin flip rather than a
## boundary. Freeing the scene before quitting, and quitting via `_finalize`,
## were both tried and both still crashed.
##
## So a caller should treat `SHOT_DONE` plus 5 PNGs on disk as success. The settle
## below is only long enough for the weapon swap, the layer's one-time mesh scan
## and the pose to be settled before the first shutter.
const SETTLE_FRAMES := 60

## Frames after `request(&"light")` at which to fire the shutter.  The authored
## light opening runs well inside a second, so these are spread over the
## anticipation, the cut and the follow-through rather than being evenly spaced.
const SWING_FRAMES := [7, 13, 19, 27]

## `CombatController.State.IDLE`, read off the controller's own enum rather than
## assumed. Used only to decide when the move is over, so the last shutter is not
## taken mid-recovery.
const IDLE_STATE := 0

var _scene: Node = null
var _combat: Node = null
var _frame := 0
var _stage := 0
var _swing_index := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_scene = load(SCENE).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return false
	# One action per frame, so the settle, the request and each shutter each get
	# their own rendered frame beneath them.  This matters because the capture
	# reads the LAST DRAWN frame, not the current one -- `_process` runs before
	# the renderer, so an image taken in the same frame that changed the pose
	# would show the pose before the change.  The spacing below is what makes
	# each shutter land on a frame the move actually had time to reach.
	#
	# The idle shutter is split across two stages for the same reason, and this
	# was measured rather than reasoned: with `_hide_ui()` and `_shoot()` in one
	# stage the capture wrote a frame with the full HUD in it -- "SEKAI TRAINING
	# GROUND", the weapon list, the element swatches -- even though `_hide_ui()`
	# had just reported hiding eight layers.  Nothing was broken; the shutter was
	# simply photographing the frame from before the hide.  So the hide gets its
	# own frame and the shutter takes the next one.
	if _stage == 0:
		_hide_ui()
		_combat = _scene.get_node_or_null("Player/CombatController")
		_stage = 1
		return false
	if _stage == 1:
		_shoot("01_idle_eye")
		_stage = 2
		return false
	if _stage == 2:
		if _combat == null:
			print("SHOT: no Player/CombatController, only the idle frame was taken")
			return true
		var started := bool(_combat.call("request", &"light"))
		print("SHOT: request(&\"light\") -> %s" % str(started))
		_stage = 3
		_frame = 0
		return false
	if _stage == 3:
		if _swing_index < SWING_FRAMES.size() and _frame >= int(SWING_FRAMES[_swing_index]):
			_shoot("%02d_swing_f%02d" % [_swing_index + 2, int(SWING_FRAMES[_swing_index])])
			_swing_index += 1
		if _swing_index >= SWING_FRAMES.size():
			_stage = 4
			_frame = 0
		return false
	# LET THE MOVE FINISH BEFORE QUITTING, AND SAY WHAT STATE IT ENDED IN.
	#
	# This does NOT prevent the signal-11 noted in the header above -- that was
	# tested directly: it survives being removed. What it does is keep the run
	# honest at the tail. The last shutter fires at `SWING_FRAMES[-1]`, which is
	# mid-move, so quitting there would tear the scene down with the attack still
	# live and print a final line that describes a state the player never saw.
	# Waiting for the controller's own IDLE makes the logged state the real one.
	#
	# It waits on the controller rather than on a frame count because the length
	# of a move is the move's business; the count is only a backstop so a stuck
	# state cannot hang the run.
	if _stage == 4:
		var state := int(_combat.get("state")) if _combat != null else -1
		if state == IDLE_STATE or _frame >= 300:
			print("SHOT: combat state at exit = %d (IDLE=%d), after %d frames" % [
				state, IDLE_STATE, _frame])
			print("SHOT_DONE")
			return true
		return false
	return true


## THE WEAPON LAYER IS THE SUBJECT, SO IT IS THE ONE LAYER THAT STAYS.
##
## `root.get_texture().get_image()` captures the fully COMPOSED frame -- world,
## glass, HUD and the weapon layer, stacked in the order the player sees them. So
## unlike `shot_weapon_rack.gd`, which hides the weapon layer because the weapon
## is the thing it must not photograph, this tool must keep it and drop
## everything else. A HUD panel or the iaido glass is opaque geometry sitting on
## top of the asset in several of these frames, and "the blade looks dark" is a
## reading the composition can produce all by itself.
##
## The layer is identified by name AND by its `WeaponViewport` child, because the
## node is declared in the scene but the SubViewport under it is the thing that
## proves what it is. `shot_weapon_rack.gd` uses the same two-part test from the
## other direction, and the day the layer is renamed this keeps working.
func _hide_ui() -> void:
	var kept: Array[String] = []
	var dropped: Array[String] = []
	var stack: Array[Node] = [_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer:
			var cl := n as CanvasLayer
			var is_weapon := cl.name == &"ForegroundWeaponLayer" \
				or cl.find_child("WeaponViewport", true, false) != null
			if is_weapon:
				kept.append(String(cl.name))
			else:
				cl.visible = false
				dropped.append(String(cl.name))
		for c in n.get_children():
			stack.append(c)
	print("SHOT: kept weapon layer(s) %s; hid %s" % [str(kept), str(dropped)])
	# A capture with no weapon layer is a capture of nothing -- say so loudly
	# rather than writing four pictures of an empty sky and reporting success.
	if kept.is_empty():
		print("SHOT: !! NO ForegroundWeaponLayer FOUND -- the frame will not contain a weapon")


## Writes `OUT_DIR/<shot_name>.png` off the root Window's final texture.
##
## Returns nothing: this is a diagnostic tool and a failed write must not abort
## the run, or one missing frame hides the four that worked. The size is printed
## so a caller can tell a real capture from a 0x0 texture without opening it.
func _shoot(shot_name: String) -> void:
	var path := OUT_DIR + shot_name + ".png"
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT: %s -> NO IMAGE (root texture unavailable)" % shot_name)
		return
	var err := img.save_png(path)
	print("SHOT: %s -> %s (%dx%d, err=%d)" % [
		shot_name, path, img.get_width(), img.get_height(), err])
