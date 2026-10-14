extends SceneTree
## THE HERO WEAPON FAMILIES, REVIEWED INSIDE THE GAME.
##
##   "G:/Godot/Godot_v4.4.1-stable_win64_console.exe" --path F:/SEKAI/godot \
##     --resolution 1600x900 --audio-driver Dummy \
##     --script res://tools/shot_weapon_families.gd
##
## Needs a REAL WINDOW -- `--headless` disables rendering.
##
## WHY THIS EXISTS AND WHY IT IS NOT `shot_weapon_rack.gd`.  That tool answers
## "is the shipped SWORD the sword on the wall", on the rack, in the sword's own
## frame.  This tool answers the question the directive actually ends on -- PART
## P, the real game is the final acceptance environment -- for the assets that
## have never been in it: the three staffs and the three chain pieces built in
## Blender.  They passed `ASSERT` and `verify_glb`, which proves the CONTRACT.
## Nothing so far has proved the LOOK, and the look is what the last three
## self-critiques have been about.
##
## IT REVIEWS ON THE ROOM'S OWN EXTENSION POINT.  `training_ground.gd` builds a
## third stand labelled "MAGIC / 未装" and says out loud that it is left empty for
## Future Weapons.  That is exactly what these are, so they are stood on it --
## at true scale, on the floor pad, in the room's own sun and sky, with the court
## visible behind them for scale.  No scene file is edited; the exhibit is added
## by this tool and freed again.
##
## THE TONE CURVE IS THE POINT.  `TrainingGround.tscn` carries `tonemap_mode = 4`,
## which is AgX, and `tools/probe_tonemap.gd` measured on this engine that
## `gl_compatibility` DOES honour it -- contrary to a belief recorded in this
## project.  So these plates are the first ones in the weapon line rendered under
## the curve the asset is signed off under, and the Blender previews were moved
## to AgX in the same pass to match.  Read them together or not at all.

const SCENE := "res://scenes/training/TrainingGround.tscn"
const OUT_DIR := "F:/SEKAI/assets_source/review/weapon/ingame/"

## The room's stand, found by NAME and measured rather than assumed.  The literal
## below is only the fallback for the case where the node is renamed, and the
## tool says so out loud when it uses it.
const STAND_NAME := "CatalystStand"
const STAND_TOP_FALLBACK := Vector3(0.0, 0.84, -10.9)

const WARMUP := 12
const SETTLE := 3

## name, glb, world name, how far the ORIGIN sits above the butt, total length.
##
## `grip_behind` is read off `assets_source/weapons/specs/*_build.json`, where it
## is produced by the same builder that wrote the GLB.  It is what puts the BUTT
## on the stand instead of the origin, and getting it wrong would float every
## asset by a hand's width while still looking like a weapon.
const ASSETS := [
	["shard", "res://models/weapons/wpn_staff_shard.glb", "法杖·晶杖（短杖）", 0.282, 1.0620],
	["lattice", "res://models/weapons/wpn_staff_lattice.glb", "法杖·镂空杖（中杖）", 0.302, 1.3910],
	["orrery", "res://models/weapons/wpn_staff_orrery.glb", "法杖·环杖（长杖）", 0.322, 1.5520],
	["chain_handle", "res://models/weapons/wpn_chain_handle.glb", "缚星链·柄", 0.0415, 0.2805],
	["chain_link", "res://models/weapons/wpn_chain_link.glb", "缚星链·链节", 0.0456, 0.0911],
	["chain_trident", "res://models/weapons/wpn_chain_trident.glb", "缚星链·三叉链头", 0.0450, 0.7800],
]

## name, focus (fraction of the height above the stand top; -1 = the grip),
## distance (metres when `rel` is false, else a multiple of the asset's length),
## rel, camera height above the focus.
##
## `03_grip` sits at 0.45 m because PART I calls 0.3-1 m the highest quality bar
## for a first-person weapon, and the grip is where the hand actually is.  A
## review that only ever looks at the head is a review of the head.
const VIEWS := [
	["01_world", 0.45, 3.40, false, 0.75],
	["02_full", 0.52, 1.90, true, 0.22],
	["03_grip", -1.0, 0.45, false, 0.10],
	["04_head", 0.90, 0.90, false, 0.26],
]

## HOW FAR OFF THE SUN'S OWN BEARING THE CAMERA SITS.
##
## THE FIRST PASS SHOT THE ASSETS FROM THE SHADOW SIDE AND IT WAS NOT OBVIOUS
## FROM THE FIRST PLATE.  Every asset in that set stood in its own shadow: the
## shaft came back a flat dark bar, and the only reason it was not written up as
## "the wood is too dark" is that the stand's own lit top face was in the same
## frame, proving the light was behind the subject.  A review camera that does
## not know where the sun is will photograph the same asset as black or as white
## depending on the room, and call both of them the asset.
##
## So the bearing is DERIVED from the Sun node every run and only the offset is a
## constant -- 18 degrees, so no plate is dead-flat front-on, where a face and a
## silhouette cannot be told apart.
const AZIMUTH_OFFSET := 18.0

var _scene: Node3D = null
var _cam: Camera3D = null
var _stand := Vector3.ZERO
var _mounted: Node3D = null
var _mounted_name := ""
var _cur := -1
var _frame := 0
var _settle := 0
var _job := 0
var _sub := 0
var _jobs: Array = []
var _ready := false
var _calib := 0
var _cards: Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		DisplayServer.window_move_to_foreground()
		var packed: PackedScene = load(SCENE)
		if packed == null:
			print("FAMILIES: FAILED to load ", SCENE)
			return true
		_scene = packed.instantiate() as Node3D
		root.add_child(_scene)
		# THE VIEWMODEL IS IN EVERY PLATE UNLESS REMOVED.  `ForegroundWeaponLayer`
		# draws the held sword as a full-screen CanvasLayer, so a camera looking
		# at a staff also photographs a placeholder sword at the same screen spot.
		_hide_noise()
		_stand = _find_stand_top()
		_cam = Camera3D.new()
		_cam.name = "FamilyCam"
		_cam.fov = 52.0
		# 2 cm, not the 5 cm default: the chain link is 9 cm long and the full
		# view of it stands 17 cm away, which is close enough that a thoughtless
		# near plane would silently eat it.
		_cam.near = 0.02
		_cam.far = 4000.0
		root.add_child(_cam)
		_cam.make_current()
		_build_jobs()
		print("FAMILIES  stand_top=%s  assets=%d  views=%d  plates=%d" % [
			str(_stand), ASSETS.size(), VIEWS.size(), _jobs.size()])
		return false

	if _frame < WARMUP:
		return false
	if _settle > 0:
		_settle -= 1
		return false
	if _calib < 3:
		return _calibration_step()
	return _advance()


# ==============================================================================
#  THE READING CARD
# ==============================================================================
#
# TWO CARDS, AND THEY SEPARATE THE TWO THINGS THAT ARE ALWAYS CONFUSED.
#
# The lit one answers "what does the ROOM do to a 0.5-albedo surface", which is
# the exact calibration `tools/level_art_review.gd` names -- a flat #808080
# surface under the rig has to land near mid-grey.  The unshaded one answers
# "what does the TONE CURVE do to 0.5", with the light rig taken out.
#
# WHY IT IS WORTH A PLATE.  The Blender previews light the models with a sun of
# energy 3.2 and a sky of 0.55, both chosen by eye; this room's sun is 1.2 with
# 0.5 sky ambient.  Those are different unit systems, so no amount of reading
# the two files settles which rig is brighter -- and the difference decides
# whether a staff that reads pale here is a MATERIAL fault or an INSTRUMENT
# fault.  Guessing that wrong is how a material gets "fixed" to compensate for a
# light rig, which is the two-bugs-one-compensating pattern the level line
# already paid for once.
const CARD_SIZE := 0.30
const CARD_ALBEDO := Color(0.5, 0.5, 0.5)


func _calibration_step() -> bool:
	if _calib == 0:
		var y := _stand.y + 0.90
		var eye := Vector3(_stand.x, y, _stand.z) \
			+ Vector3(cos(_lit_azimuth()) * 1.20, 0.10, sin(_lit_azimuth()) * 1.20)
		_cards = []
		for i in range(2):
			var mi := MeshInstance3D.new()
			mi.name = "Card_lit" if i == 0 else "Card_flat"
			var q := QuadMesh.new()
			q.size = Vector2(CARD_SIZE, CARD_SIZE)
			mi.mesh = q
			var m := StandardMaterial3D.new()
			m.albedo_color = CARD_ALBEDO
			if i == 1:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = m
			# BELOW the asset bay, not beside it, so the cards are lit by the same
			# sun and sky while standing where no exhibit ever is.
			mi.position = Vector3(_stand.x + (0.30 if i == 0 else -0.30), y, _stand.z)
			_scene.add_child(mi)
			# `Basis.looking_at(d, up)` points -Z along d, so passing the
			# vector AWAY from the camera leaves +Z -- the QuadMesh's front
			# face -- aimed straight at it.  A card judged at an angle is a card
			# measuring the cosine, not the rig.
			mi.global_basis = Basis.looking_at(mi.global_position - eye, Vector3.UP)
			_cards.append(mi)
		_cam.global_position = eye
		_cam.look_at(Vector3(_stand.x, y, _stand.z), Vector3.UP)
		_calib = 1
		_settle = 2
		return false
	if _calib == 1:
		_shoot_cards()
		_calib = 2
		_settle = 1
		return false
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards = []
	_calib = 3
	return false


func _shoot_cards() -> void:
	var path := OUT_DIR + "_calibration.png"
	var img := root.get_texture().get_image()
	if img == null:
		print("FAMILIES: calibration -> NO IMAGE")
		return
	var err := img.save_png(path)
	print("FAMILIES calibration -> %s (err=%d)" % [path, err])
	var vp := Vector2(root.size)
	for c in _cards:
		var mi := c as MeshInstance3D
		var p := _cam.unproject_position(mi.global_position)
		var px := int(clampf(p.x * float(img.get_width()) / vp.x, 0.0,
			float(img.get_width() - 1)))
		var py := int(clampf(p.y * float(img.get_height()) / vp.y, 0.0,
			float(img.get_height() - 1)))
		var col := img.get_pixel(px, py)
		print("FAMILIES   %-10s at %s -> #%02x%02x%02x" % [
			mi.name, str(mi.global_position.snappedf(0.001)),
			int(round(col.r * 255.0)), int(round(col.g * 255.0)),
			int(round(col.b * 255.0))])


func _build_jobs() -> void:
	for a in range(ASSETS.size()):
		for v in range(VIEWS.size()):
			_jobs.append([a, v])


# ==============================================================================
#  THE STAND, MEASURED
# ==============================================================================

## `training_ground.gd` places the stand with `TB.slab(court, "CatalystStand",
## Vector3(0.0, 0.42, plinth_z - 0.5), Vector3(2.0, 0.84, 2.0), ...)`, and
## `slab` centres a BoxMesh on its body's position -- so the top is at
## `0.42 + 0.84 / 2 = 0.84`.  That chain of reasoning is three files long and any
## link can move, so the number is read off the live mesh instead and the fallback
## is only reached if the node itself is gone.
func _find_stand_top() -> Vector3:
	var n := _scene.find_child(STAND_NAME, true, false) as Node3D
	if n == null:
		print("FAMILIES: '%s' not found -- using the literal fallback %s. "
			% [STAND_NAME, str(STAND_TOP_FALLBACK)]
			+ "EVERY ASSET IS NOW FLOATING OR SUNK BY WHATEVER THE ROOM CHANGED.")
		return STAND_TOP_FALLBACK
	var box := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var b := mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for g in c.get_children():
			stack.append(g)
	if first:
		print("FAMILIES: '%s' has no mesh -- using the fallback" % STAND_NAME)
		return STAND_TOP_FALLBACK
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)


# ==============================================================================
#  MOUNT / UNMOUNT
# ==============================================================================

func _unmount() -> void:
	if _mounted != null and is_instance_valid(_mounted):
		_mounted.queue_free()
	_mounted = null
	_mounted_name = ""


## The exhibit is added to the SCENE, not to the stand, because the stand is a
## generated `StaticBody3D` whose transform chain this tool has no business
## assuming -- and the world position is the thing that is actually known.
func _mount(a: int) -> bool:
	var path: String = ASSETS[a][1]
	if not ResourceLoader.exists(path):
		print("FAMILIES: %s -> MISSING, not imported? (%s)" % [ASSETS[a][0], path])
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAMILIES: %s -> not a PackedScene" % ASSETS[a][0])
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		print("FAMILIES: %s -> root is not a Node3D" % ASSETS[a][0])
		return false
	node.name = "Exhibit_" + String(ASSETS[a][0])
	var behind := float(ASSETS[a][3])
	node.position = _stand + Vector3(0.0, behind, 0.0)
	_scene.add_child(node)
	_mounted = node
	_mounted_name = String(ASSETS[a][0])
	_probe(node, a)
	_settle = SETTLE
	return true


## MEASURE, DON'T ASSUME.  The registry number and the shipped mesh are two
## descriptions of one object, and this line has already been bitten twice by a
## GLB that was copied but not re-imported -- Godot does not re-import on a
## non-editor run, so a stale `.scn` renders an asset that no longer exists on
## disk and every screenshot is of the wrong thing.
func _probe(node: Node3D, a: int) -> void:
	var box := AABB()
	var first := true
	var meshes := 0
	var tris := 0
	var mats: Array[String] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			meshes += 1
			var b := mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
			tris += _tris(mi)
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(s)
					if m is StandardMaterial3D and not mats.has(m.resource_name):
						mats.append(m.resource_name)
		for g in c.get_children():
			stack.append(g)
	var want_len := float(ASSETS[a][4])
	print("FAMILIES %-14s meshes=%d tris=%d  want_len=%.4f" % [
		ASSETS[a][0], meshes, tris, want_len])
	print("FAMILIES %-14s world y %.4f..%.4f  (height %.4f)  x %.4f..%.4f  z %.4f..%.4f" % [
		ASSETS[a][0], box.position.y, box.end.y, box.size.y,
		box.position.x, box.end.x, box.position.z, box.end.z])
	print("FAMILIES %-14s stand_top=%.4f  measured_height - want = %+.4f m" % [
		ASSETS[a][0], _stand.y, box.size.y - want_len])
	print("FAMILIES %-14s materials %s" % [ASSETS[a][0], ", ".join(mats)])


func _tris(mi: MeshInstance3D) -> int:
	var total := 0
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			total += (idx as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


# ==============================================================================
#  CAMERA / SHUTTER
# ==============================================================================

func _pose(a: int, v: int) -> void:
	var length := float(ASSETS[a][4])
	var behind := float(ASSETS[a][3])
	var view: Array = VIEWS[v]
	var focus := float(view[1])
	var y := _stand.y + (behind if focus < 0.0 else focus * length)
	var target := Vector3(_stand.x, y, _stand.z)
	var dist := float(view[2])
	if bool(view[3]):
		dist *= length
	var az := _lit_azimuth()
	var eye := target + Vector3(cos(az) * dist, float(view[4]), sin(az) * dist)
	_cam.global_position = eye
	_cam.look_at(target, Vector3.UP)


## WHICH WAY THE SUN IS.  A `DirectionalLight3D` shines along its own -Z, so the
## direction an object must FACE to be lit head-on is its +Z -- but the sign
## convention is exactly the kind of thing that is remembered wrong, so the
## vector is flipped until its Y is positive and the printed bearing is checked
## against the room rather than trusted.
func _lit_azimuth() -> float:
	var sun := _scene.find_child("Sun", true, false) as DirectionalLight3D
	if sun == null:
		print("FAMILIES: no Sun node -- falling back to a fixed bearing")
		return deg_to_rad(200.0)
	var to_light := sun.global_transform.basis.z.normalized()
	if to_light.y < 0.0:
		to_light = -to_light
	var az := atan2(to_light.z, to_light.x) + deg_to_rad(AZIMUTH_OFFSET)
	print("FAMILIES  sun to_light=%s energy=%.2f  camera bearing=%.1f deg" % [
		str(to_light.snappedf(0.0001)), sun.light_energy, rad_to_deg(az)])
	return az


func _advance() -> bool:
	if _job >= _jobs.size():
		print("FAMILIES_DONE  %d plates in %s" % [_jobs.size(), OUT_DIR])
		return true
	var a := int(_jobs[_job][0])
	var v := int(_jobs[_job][1])
	if _sub == 0:
		if a != _cur:
			_unmount()
			if not _mount(a):
				_job += 1
				return false
			_cur = a
		_pose(a, v)
		_sub = 1
		return false
	_shoot("%s_%s" % [ASSETS[a][0], VIEWS[v][0]])
	_job += 1
	_sub = 0
	return false


func _shoot(name: String) -> void:
	var path := OUT_DIR + name + ".png"
	var img := root.get_texture().get_image()
	if img == null:
		print("FAMILIES: %s -> NO IMAGE" % name)
		return
	var err := img.save_png(path)
	print("FAMILIES shot %-22s eye=%s -> %s (err=%d)" % [
		name, str(_cam.global_position.snappedf(0.001)), path, err])


## EVERYTHING THAT IS NOT THE SUBJECT HAS TO GO, AND THE FIRST PASS DID NOT GO
## FAR ENOUGH.  Two separate families of noise survived it:
##
##   * the held viewmodel, drawn as a full-screen CanvasLayer by
##     `ForegroundWeaponLayer` -- a placeholder sword at a fixed screen position
##     in EVERY plate, which is the trap `shot_weapon_rack.gd` documents;
##   * the ROOM'S OWN SIGNAGE.  `training_ground.gd` builds its zone labels with
##     `TB.label`, which makes `Label3D` -- WORLD geometry, not UI.  The stand
##     these assets are reviewed on is labelled "MAGIC / 未装" at y = 1.75, which
##     is exactly the height of a staff's shaft, so the first plate had the label
##     running straight across the thing it was labelling.
##
## The HUD is a third: it is a `CanvasLayer`, and hiding only those that carry a
## `WeaponViewport` left the weapon list and the zone readout burned into the
## last plate.  So: every CanvasLayer anywhere under the room, and every Label3D.
func _hide_noise() -> void:
	var player := _scene.find_child("Player", true, false) as Node3D
	if player != null:
		player.visible = false
	else:
		print("FAMILIES: no Player -- the viewmodel may still be composited")
	var n_labels := 0
	var n_layers := 0
	var stack: Array[Node] = [_scene]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Label3D:
			(c as Label3D).visible = false
			n_labels += 1
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
			n_layers += 1
		for g in c.get_children():
			stack.append(g)
	for child in root.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
			n_layers += 1
	print("FAMILIES  hid Player, %d Label3D, %d CanvasLayer" % [n_labels, n_layers])
