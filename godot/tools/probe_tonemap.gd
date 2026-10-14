extends SceneTree
## DOES `gl_compatibility` ACTUALLY IMPLEMENT AGX?  ASK THE RENDERER, NOT THE DOCS.
##
##   "G:/Godot/Godot_v4.4.1-stable_win64_console.exe" --path F:/SEKAI/godot \
##     --resolution 1280x720 --audio-driver Dummy \
##     --script res://tools/probe_tonemap.gd
##
## Needs a REAL WINDOW -- `--headless` disables rendering.
##
## WHY THIS TOOL EXISTS.  The hero weapon line makes every material judgement off
## Blender preview plates, and the plates were moved onto FILMIC on the stated
## belief that `gl_compatibility` does not implement AgX and falls back to FILMIC.
## But `scenes/training/TrainingGround.tscn` -- the room the assets are actually
## reviewed in -- sets `tonemap_mode = 4`, and 4 IS AgX.  One of the two is wrong,
## and neither is checkable by reading the file: `Environment.tonemap_mode` is
## whatever it says, and what the COMPATIBILITY renderer then does with it is a
## property of the renderer.
##
## So this renders ONE scene, with ONE geometry, under four tone mappers, and
## reads the pixel values back.  If mode 4 and mode 2 produce the same bytes, the
## compatibility renderer is collapsing them and the plates were right.  If they
## differ, the plates have been tone-mapped differently from the game the whole
## time -- and this is the third member of a family that already includes the
## metallic ceiling and the camera near plane: a setting nobody looked at,
## silently changing every decision, with the tool reporting success.
##
## IT IS A DIFFERENCE TEST FIRST AND AN ABSOLUTE TEST SECOND.  Whether Godot
## converts `albedo_color` from sRGB before shading changes every absolute number
## below, and does not change the answer to the question being asked.  The LINEAR
## column is printed as the reference that settles the convention anyway.
##
## WHY UNSHADED.  A lit surface folds the light rig into the measurement, and the
## light rig is the next thing that would need its own probe.  An unshaded
## material puts its albedo straight into the shading result, so what survives to
## the framebuffer is the tone curve and nothing else.

const OUT_DIR := "F:/SEKAI/assets_source/review/tonemap/"

## Row 1: a grey ramp, so the SHAPE of each curve is readable and not just its
## endpoint.  0.5 is the value that decides whether mid-grey is still mid-grey --
## the exact complaint written into TrainingGround.tscn's own comment.
## Row 2: the values this line actually ships.  `crystal` and `crystal_warm` are
## the staff head's emission colours, `steel_link` is the chain link's albedo,
## and `overdrive` is the pastel case that took three material passes to find.
const GREY_RAMP := [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

const ASSET_COLORS := [
	["crystal_em", Color(0.045, 0.310, 0.560)],
	["crystal_warm", Color(0.560, 0.155, 0.028)],
	["steel_link", Color(0.474, 0.478, 0.492)],
	["wood_shaft", Color(0.075, 0.058, 0.042)],
	["overdrive", Color(0.090, 0.620, 1.120)],
]

const MODES := [
	["00_linear", 0],
	["01_filmic", 2],
	["02_aces", 3],
	["03_agx", 4],
]

const SETTLE := 4

var _scene: Node3D = null
var _cam: Camera3D = null
var _env: Environment = null
var _quads: Array = []
var _frame := 0
var _mode := 0
var _stage := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_scene = Node3D.new()
	_scene.name = "TonemapProbe"
	root.add_child(_scene)

	_cam = Camera3D.new()
	_cam.name = "ProbeCam"
	_cam.fov = 45.0
	_cam.near = 0.05
	_cam.far = 100.0
	_scene.add_child(_cam)
	_cam.look_at_from_position(Vector3(0.0, 0.0, 6.0), Vector3.ZERO, Vector3.UP)
	_cam.make_current()

	# A black background so the only thing the tone curve can act on is the
	# quads, and `tonemap_white = 1.0` so this matches TrainingGround.tscn's own
	# Environment as closely as a probe can without importing it.
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.0, 0.0, 0.0)
	_env.tonemap_white = 1.0
	var we := WorldEnvironment.new()
	we.name = "ProbeEnv"
	we.environment = _env
	_scene.add_child(we)

	var ramp: Array = []
	for v in GREY_RAMP:
		ramp.append(["g%02d" % int(round(v * 100.0)), Color(v, v, v)])
	_build_row(0.55, ramp)
	_build_row(-0.45, ASSET_COLORS)

	# WHAT A SCENE THAT SAYS NOTHING ACTUALLY GETS.  `.tscn` files only write
	# properties that differ from the default, so a scene with no `tonemap_mode`
	# line is not "Filmic" and not "the project's choice" -- it is whatever
	# `Environment` initialises to, which is a fact about the engine and has to
	# be read off the engine.  `scenes/combat/CombatSandbox.tscn` names no tone
	# curve at all, so this line is the only place its look is written down.
	var probe := Environment.new()
	print("PROBE default tonemap_mode=%d  (0 linear, 1 reinhard, 2 filmic, "
		% probe.tonemap_mode + "3 aces, 4 agx)")
	print("PROBE quads=%d modes=%d  (%s)" % [
		_quads.size(), MODES.size(), ProjectSettings.get_setting(
			"rendering/renderer/rendering_method", "?")])
	_set_mode(0)


func _build_row(y: float, items: Array) -> void:
	var pitch := 0.52
	var w := 0.40
	var x0 := -float(items.size() - 1) * pitch * 0.5
	for i in range(items.size()):
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(w, w)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = items[i][1]
		mi.material_override = m
		mi.position = Vector3(x0 + float(i) * pitch, y, 0.0)
		mi.name = "Q_%s" % items[i][0]
		_scene.add_child(mi)
		_quads.append([items[i][0], mi, items[i][1]])


func _set_mode(i: int) -> void:
	_env.tonemap_mode = int(MODES[i][1])
	_frame = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < SETTLE:
		return false
	_shoot(MODES[_mode][0])
	_mode += 1
	if _mode >= MODES.size():
		print("PROBE_DONE")
		return true
	_set_mode(_mode)
	return false


func _shoot(tag: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		print("PROBE: %s -> NO IMAGE" % tag)
		return
	var path := OUT_DIR + tag + ".png"
	var err := img.save_png(path)
	print("PROBE %-10s tonemap=%d  -> %s (err=%d)" % [
		tag, _env.tonemap_mode, path, err])
	_sample(img)


## READ THE FRAMEBUFFER, NOT THE MATERIAL.
##
## `unproject_position` is how the sample point is found, so a camera change
## cannot silently start reading the black background and reporting a plausible
## zero.  The scale factor converts viewport coordinates to image coordinates in
## case the window and the captured texture ever disagree in size -- the exact
## trap that made window-grabs the wrong instrument earlier in this line.
func _sample(img: Image) -> void:
	var vp := Vector2(root.size)
	if vp.x < 1.0 or vp.y < 1.0:
		print("        (no window size; sampling skipped)")
		return
	var sx := float(img.get_width()) / vp.x
	var sy := float(img.get_height()) / vp.y
	var parts: Array[String] = []
	for row in _quads:
		var mi: MeshInstance3D = row[1]
		var p := _cam.unproject_position(mi.global_position)
		var px := int(clampf(roundf(p.x * sx), 0.0, float(img.get_width() - 1)))
		var py := int(clampf(roundf(p.y * sy), 0.0, float(img.get_height() - 1)))
		var c := img.get_pixel(px, py)
		parts.append("%s=%02x%02x%02x" % [
			row[0], int(round(c.r * 255.0)), int(round(c.g * 255.0)),
			int(round(c.b * 255.0))])
	print("        " + " ".join(parts))
