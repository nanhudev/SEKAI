extends SceneTree
## Close captures of the weapon rack, so a hand-authored asset can be reviewed
## IN GODOT rather than in Blender (brief PART O / PART P / §X).
##
## Needs a REAL WINDOW -- `--headless` disables rendering.
##
##   $GODOT --path F:/SEKAI/godot --resolution 1600x900 --audio-driver Dummy \
##     --script res://tools/shot_weapon_rack.gd
##
## WHY A SEPARATE TOOL FROM training_ground_renderer.gd
## The zone renderer answers "can I tell the zones apart" and shoots from 8-80 m.
## The sword on the rack is 1.05 m long and needs 0.6-2.5 m, which is a different
## question with a different camera. Bolting these onto the zone renderer would
## have meant editing a tool three lines are currently mid-air on.

const SCENE := "res://scenes/training/TrainingGround.tscn"
const OUT_DIR := "F:/SEKAI/assets_source/review/weapon/"
const WARMUP := 10

# The rack is at training_ground.gd:199: `_rack(court, &"sword", ..., Vector3(-3.4,
# 0.42, plinth_z - 0.5), 0.0)` with `plinth_z = ZONE_SPAWN.y + 1.6`.  ZONE_SPAWN is
# Vector4(-9.0, -12.0, 9.0, 4.0) and its .y/.w are both used as Z, so the plinth
# sits at z = -10.4 and the rack at z = -10.9.
#
# The exhibit hangs at rack-local (0, RACK_H - 0.16, +0.17), RACK_H = 1.55, so the
# SWORD'S GRIP ORIGIN is at world (-3.4, 1.81, -10.73).  The measured GLB has its
# tip at local z = -0.765 and its kashira at +0.292, so once the rack lays it flat
# the blade spans world x -3.692 .. -2.635, tip toward +X, edge up, at y 1.771
# .. 1.849.  The probe prints these numbers live; if they disagree, fix the rack
# before believing any of the six images.
const RACK := Vector3(-3.4, 1.81, -10.73)
const TIP := Vector3(-2.635, 1.81, -10.73)
const BUTT := Vector3(-3.692, 1.81, -10.73)

# name, eye, look-at.  06 sits at 0.48 m, inside the 0.3-1 m band PART I calls the
# highest quality bar for a first-person weapon, so the rack doubles as a
# near-field material check without needing the sword in a hand.
const SHOTS := [
	["01_rack_wide", Vector3(-3.40, 2.05, -8.40), Vector3(-3.40, 1.76, -10.73)],
	["02_sword_full", Vector3(-3.16, 1.83, -9.15), Vector3(-3.16, 1.81, -10.73)],
	["03_tip_close", Vector3(-2.64, 1.88, -10.08), Vector3(-2.66, 1.81, -10.72)],
	["04_guard_close", Vector3(-3.30, 1.88, -10.10), Vector3(-3.42, 1.81, -10.73)],
	["05_grip_close", Vector3(-3.58, 1.88, -10.10), Vector3(-3.62, 1.81, -10.73)],
	["06_fp_distance", Vector3(-3.10, 1.95, -10.35), Vector3(-3.36, 1.80, -10.72)],
	# The scabbard hangs one bay below the sword, sharing the frame: rack-local
	# (0, RACK_H - 0.46, 0.17) with the rack at (-3.4, 0.42, -10.9), so its MOUTH
	# is at world (-3.4, 1.51, -10.73) and the body runs +X to -2.597.
	["07_saya_full", Vector3(-3.30, 1.62, -9.25), Vector3(-3.35, 1.51, -10.73)],
	["08_saya_mouth", Vector3(-3.44, 1.60, -10.05), Vector3(-3.40, 1.51, -10.73)],
]

var _scene: Node3D = null
var _cam: Camera3D = null
var _frame := 0
var _shot := 0
var _settle := 0
var _probed := false


# MEASURE, DON'T ASSUME (PART O).  This tool exists to answer "is the shipped
# sword on the wall", and the cheapest way to get that answer wrong is to aim six
# cameras at a position computed on paper.  So the tool prints the exhibit's LIVE
# world AABB and the material names it actually resolved, and a capture session
# whose numbers disagree with the comment above is a capture session to throw
# away.  It is also the check that catches the stale-import trap: Godot does NOT
# re-import a GLB when a non-editor instance runs, so replacing the file on disk
# is invisible until `--import` is run.  A 30,398-byte cached .scn vs a
# 242,998-byte one is six screenshots of the wrong asset.
func _probe() -> void:
	# There are TWO exhibits (the sword rack and the chain rack), so name the
	# parent: `find_child("Exhibit")` alone would silently probe whichever rack
	# the tree walk reached first, and a probe that measures the wrong object is
	# worse than no probe.
	var rack := _scene.find_child("Rack_sword", true, false) as Node3D
	var exhibit: Node3D = rack.find_child("Exhibit", true, false) if rack != null else null
	if exhibit == null:
		print("PROBE: no Rack_sword/Exhibit node under the training ground")
		return
	var names: Array[String] = []
	var box := AABB()
	var first := true
	var stack: Array[Node] = [exhibit]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			# VISIBLE ONLY.  `Sword_FP.tscn` carries the scabbard as a child of the
			# sword, at the seated pose and hidden, because that is what makes
			# "fully sheathed" one translation for whoever animates it.  Merging a
			# hidden mesh into this box would report a 1.099 m sword and a set of
			# saya materials for an exhibit that shows neither, which is precisely
			# the kind of number this probe exists to prevent.
			if mi.mesh != null and mi.is_visible_in_tree():
				var b := mi.global_transform * mi.mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
				for i in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(i)
					var label := (m.resource_name if m != null else "<null>")
					if not names.has(label):
						names.append(label)
		for c in n.get_children():
			stack.append(c)

	var s := box.size
	print("PROBE: exhibit AABB size=(%.4f, %.4f, %.4f) tris=%d" % [s.x, s.y, s.z, _tris(exhibit)])
	print("PROBE: world pos=(%.3f, %.3f, %.3f) - min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % [
		box.get_center().x, box.get_center().y, box.get_center().z,
		box.position.x, box.position.y, box.position.z,
		box.end.x, box.end.y, box.end.z])
	print("PROBE: materials=%s" % str(names))

	# WHAT CHANNELS THE IMPORTED MESH ACTUALLY HAS.  A blade that renders as a
	# white bar has three possible causes -- too-bright albedo, no UVs so a texture
	# cannot be authored, or vertex colours present but not enabled as albedo -- and
	# they need completely different fixes.  Printing the surface format and the
	# material flags turns a guess into a decision.
	var blade := exhibit.find_child("Blade", true, false) as MeshInstance3D
	if blade != null and blade.mesh != null:
		for i in blade.mesh.get_surface_count():
			var fmt: int = blade.mesh.surface_get_format(i)
			var arr: Array = blade.mesh.surface_get_arrays(i)
			var m: StandardMaterial3D = blade.mesh.surface_get_material(i) as StandardMaterial3D
			print("PROBE: Blade surface %d  fmt=0x%03X  uv=%s  colour=%s" % [
				i, fmt,
				"yes" if (fmt & Mesh.ARRAY_FORMAT_TEX_UV) != 0 else "NO",
				"yes" if (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0 else "NO"])
			if m != null:
				print("PROBE:   albedo=(%.3f, %.3f, %.3f) metallic=%.2f roughness=%.2f vcol_as_albedo=%s" % [
					m.albedo_color.r, m.albedo_color.g, m.albedo_color.b,
					m.metallic, m.roughness, str(m.vertex_color_use_as_albedo)])
			# Index and colour arrays are ABSENT when the format says they are, and
			# `arr[...]` then yields null -- assigning that to a typed Packed*
			# variable is a runtime error, not a false. Keep it untyped.
			var vc = arr[Mesh.ARRAY_COLOR]
			if vc is PackedColorArray and (vc as PackedColorArray).size() > 0:
				var colours := vc as PackedColorArray
				# Color has no componentwise min()/max(), so fold by hand.
				var lo := Vector3(1.0, 1.0, 1.0)
				var hi := Vector3(0.0, 0.0, 0.0)
				for c in colours:
					lo = Vector3(minf(lo.x, c.r), minf(lo.y, c.g), minf(lo.z, c.b))
					hi = Vector3(maxf(hi.x, c.r), maxf(hi.y, c.g), maxf(hi.z, c.b))
				print("PROBE:   vertex colours n=%d  min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % [
					colours.size(), lo.x, lo.y, lo.z, hi.x, hi.y, hi.z])
	if s.z > s.x:
		print("PROBE: !! LONG AXIS IS Z -- the blade is standing up, not lying on the bar")
	else:
		print("PROBE: long axis is X, blade lies along the bar (as intended)")

	# WHAT ELSE IS IN FRAME.  The first two capture sessions showed a sword that
	# did not match this AABB at all -- a vertical pale slab with a flat gold
	# guard and a brown box grip -- and the temptation was to blame the import
	# cache a second time.  Naming every mesh near the exhibit settles it by
	# measurement instead: a viewmodel in the player's hands is a different
	# object in a different place, and it looks like a box because it IS boxes.
	print("PROBE: ---- every MeshInstance3D within 9 m of the exhibit ----")
	var origin := box.get_center()
	var all: Array[Node] = [_scene]
	while not all.is_empty():
		var n: Node = all.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var wb := mi.global_transform * mi.mesh.get_aabb()
				if wb.get_center().distance_to(origin) < 9.0:
					var ws := wb.size
					print("PROBE:   %-42s size=(%.4f, %.4f, %.4f) at (%.2f, %.2f, %.2f)" % [
						String(mi.get_path()).replace(String(_scene.get_path()), "."),
						ws.x, ws.y, ws.z,
						wb.get_center().x, wb.get_center().y, wb.get_center().z])
		for c in n.get_children():
			all.append(c)


## Triangles actually on display, so it agrees with the AABB above.  The hidden
## seated scabbard inside `Sword_FP.tscn` is 3,130 tris that no one can see, and a
## count that includes it reports the sword as 13,508.
func _tris(node: Node) -> int:
	var total := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		total += _mesh_tris(n)
		for c in n.get_children():
			stack.append(c)
	return total


func _mesh_tris(n: Node) -> int:
	if not (n is MeshInstance3D):
		return 0
	var mi := n as MeshInstance3D
	if mi.mesh == null or not mi.is_visible_in_tree():
		return 0
	var total := 0
	for i in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(i)
		# Absent index arrays come back as null, and `null` assigned to a typed
		# Packed* is a runtime error rather than an empty array.
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			total += (idx as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _initialize() -> void:
	pass


# THE VIEWMODEL IS IN EVERY SCREENSHOT UNLESS YOU REMOVE IT.
# `root.get_texture().get_image()` captures the whole root viewport, and
# ForegroundWeaponLayer composites the player's held weapon into a SubViewport
# that is drawn as a full-screen TextureRect CanvasLayer on top of the world.
# So every capture of a rack 0.7 m away ALSO contained a box-primitive sword
# 0.3 m from the camera -- larger on screen than the real asset, at the same
# screen position in all six shots, and pale with a flat guard, which is exactly
# what an unreviewed placeholder looks like.  Two capture sessions were spent
# reading the wrong object.  Hiding the Player removes it at the source: the
# layer sets `copy.visible = source.is_visible_in_tree()` every frame, so the
# copies follow the Player down, and no layers or cull bits have to be fought.
#
# Same trap lives in training_ground_renderer.gd - its 8 zone shots carry the
# viewmodel too, and the pale blob in 02_spawn_equipment is this same object.
func _hide_viewmodel() -> void:
	var player := _scene.find_child("Player", true, false) as Node3D
	if player != null:
		player.visible = false
		print("PROBE: hid Player (viewmodel source) at ", player.global_position)
	else:
		print("PROBE: no Player in the scene - the viewmodel may still be composited")

	for child in root.get_children():
		if child is CanvasLayer:
			var cl := child as CanvasLayer
			var sub := cl.find_child("WeaponViewport", true, false)
			print("PROBE: CanvasLayer '%s' layer=%d viewport=%s" % [
				cl.name, cl.layer, "yes" if sub != null else "no"])
			if sub != null:
				cl.visible = false
				print("PROBE:   -> hidden (this layer is what the earlier captures showed)")


func _process(_delta: float) -> bool:
	_frame += 1

	if _frame == 1:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		DisplayServer.window_move_to_foreground()
		var packed: PackedScene = load(SCENE)
		if packed == null:
			print("shot_weapon_rack: FAILED to load ", SCENE)
			return true
		_scene = packed.instantiate()
		root.add_child(_scene)
		_hide_viewmodel()
		_cam = Camera3D.new()
		_cam.fov = 52.0
		_cam.near = 0.05
		_cam.far = 4000.0
		root.add_child(_cam)
		_cam.make_current()
		return false

	if _frame < WARMUP:
		return false

	if not _probed:
		_probed = true
		_probe()

	if _settle < 3:
		_settle += 1
		return false
	_settle = 0

	var shot: Array = SHOTS[_shot]
	var eye: Vector3 = shot[1]
	var look: Vector3 = shot[2]
	_cam.global_position = eye
	_cam.look_at(look, Vector3.UP)
	var path: String = OUT_DIR + String(shot[0]) + ".png"
	var err := _save(path)
	print("shot %s eye=%s -> %s (err=%d)" % [shot[0], str(eye), path, err])

	_shot += 1
	if _shot >= SHOTS.size():
		print("shot_weapon_rack: done, %d shots" % SHOTS.size())
		return true
	return false


func _save(path: String) -> int:
	var img := root.get_texture().get_image()
	if img == null:
		return -1
	return img.save_png(path)
